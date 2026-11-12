#!/usr/bin/env python3
"""Local, read-only GPU diagnostics. No driver changes, network or screen capture.

Inventory is not a benchmark. Optional decode probes require an explicit local
file and force GPU frames (no silent software fallback). Qt reports its own
backend and media/shader results separately in GpuCompatibility.qml.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


def read(path):
    try:
        return Path(path).read_text(errors="replace").strip()
    except OSError:
        return ""


def run(argv, timeout=6):
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, errors="replace",
                              timeout=timeout, env={**os.environ, "LC_ALL": "C"})
        return {"status": "ok" if proc.returncode == 0 else "error",
                "output": (proc.stdout + "\n" + proc.stderr).strip()[-24000:]}
    except FileNotFoundError:
        return {"status": "missing", "output": "Command is not installed: " + argv[0]}
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "output": "Probe timed out: " + argv[0]}
    except OSError as exc:
        return {"status": "error", "output": str(exc)}


def inventory(sys_root=Path("/sys"), dev_root=Path("/dev"), runner=run):
    drm = Path(sys_root) / "class/drm"
    devices = {}
    for node in sorted(drm.glob("*")):
        if not re.fullmatch(r"(?:card|renderD)\d+", node.name):
            continue
        device = node / "device"
        if not device.exists():
            continue
        address = device.resolve().name
        if address not in devices:
            vendor = read(device / "vendor").lower()
            pci_id = read(device / "device").lower()
            driver_path = device / "driver"
            driver = driver_path.resolve().name if driver_path.exists() else ""
            info = runner(["lspci", "-D", "-s", address, "-nn"]) if re.fullmatch(r"[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]", address) else {"status": "unknown", "output": ""}
            devices[address] = {
                "address": address, "vendorId": vendor, "deviceId": pci_id,
                "vendor": {"0x1002": "AMD", "0x10de": "NVIDIA", "0x8086": "Intel"}.get(vendor, "Other"),
                "model": info["output"] if info["status"] == "ok" and info["output"] else (vendor + ":" + pci_id),
                "driver": driver or "unknown", "bootVga": read(device / "boot_vga") == "1",
                "nodes": [], "connectors": [], "renderNodes": [],
            }
        gpu = devices[address]
        path = Path(dev_root) / "dri" / node.name
        access = path.exists() and os.access(path, os.R_OK | os.W_OK)
        gpu["nodes"].append({"name": node.name, "path": str(path), "accessible": access})
        if node.name.startswith("renderD") and access:
            gpu["renderNodes"].append(str(path))
        if node.name.startswith("card"):
            for connector in sorted(drm.glob(node.name + "-*")):
                gpu["connectors"].append({"name": connector.name,
                    "status": read(connector / "status") or "unknown",
                    "enabled": read(connector / "enabled") or "unknown"})
    return sorted(devices.values(), key=lambda gpu: gpu["address"])


def fingerprint(gpus):
    # Independent of card numbering and driver version. Includes PCI location so
    # replacing/moving one of two identical cards is visible. Empty != removal.
    if not gpus:
        return ""
    identity = sorted((g["address"], g["vendorId"], g["deviceId"]) for g in gpus)
    return hashlib.sha256(json.dumps(identity).encode()).hexdigest()


def diagnose(gpus, env, modeset, monitors, config_errors):
    issues = []
    def add(code, severity, message):
        issues.append({"code": code, "severity": severity, "message": message})
    if not gpus:
        add("no-drm", "warning", "DRM GPU not detected. Check /sys/class/drm and the kernel driver; containers may hide devices.")
    for gpu in gpus:
        if gpu["driver"] == "unknown":
            add("driver-" + gpu["address"], "warning", gpu["model"] + ": no bound driver found. Check the distro driver packages and kernel log.")
        if not gpu["renderNodes"]:
            add("access-" + gpu["address"], "warning", gpu["address"] + ": no accessible render node. Check session/device permissions; do not chmod devices globally.")
        if gpu["driver"] == "nvidia" and modeset.lower() not in ("y", "1"):
            add("nvidia-kms", "warning", "NVIDIA DRM modeset is disabled or unreadable. Check nvidia_drm.modeset and the installed driver; no automatic changes are made.")
    if env.get("XDG_SESSION_TYPE") != "wayland" or not env.get("WAYLAND_DISPLAY"):
        add("session", "warning", "A Wayland session is not confirmed. Run the shell inside the intended Hyprland session.")
    if env.get("LIBGL_ALWAYS_SOFTWARE") in ("1", "true") or env.get("QSG_RHI_BACKEND") == "software" or env.get("QT_QUICK_BACKEND") == "software":
        add("software", "warning", "An environment override requests software rendering. Check session overrides if this was not intentional.")
    if env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        if monitors["status"] != "ok":
            add("hypr-ipc", "warning", "Hyprland IPC did not answer. Check hyprctl, session ownership and HYPRLAND_INSTANCE_SIGNATURE.")
        if config_errors["status"] == "ok" and config_errors["output"].strip() not in ("", "ok"):
            add("hypr-config", "warning", "Hyprland reports configuration errors. Review the diagnostics before changing graphics settings.")
    else:
        add("hypr-absent", "info", "Hyprland session not detected; Hyprland-specific checks are unavailable.")
    if len(gpus) > 1:
        add("multi-gpu", "info", "Multiple GPUs detected. Monitor connectors, Qt rendering and video decoding can use different GPUs. boot_vga does not identify Qt's GPU.")
    if any(env.get(key) for key in ("AQ_DRM_DEVICES", "DRI_PRIME", "__NV_PRIME_RENDER_OFFLOAD", "QT_FFMPEG_DECODING_HW_DEVICE_TYPES")):
        add("overrides", "info", "Graphics/decoder overrides are set. Recheck paths and backend choices after replacing a GPU.")
    return issues


def collect(sys_root=Path("/sys"), dev_root=Path("/dev"), env=None, runner=run, which=shutil.which, platform=None):
    env = dict(os.environ if env is None else env)
    platform = sys.platform if platform is None else platform
    if platform != "linux":
        return {"schema": 1, "status": "unsupported", "gpus": [], "fingerprint": "",
                "issues": [{"code": "platform", "severity": "warning", "message": "Linux DRM probes require Linux; results on this host are not a Fedora/Wayland test."}]}
    gpus = inventory(sys_root, dev_root, runner)
    modeset = read(Path(sys_root) / "module/nvidia_drm/parameters/modeset") or "unknown"
    unavailable = {"status": "unavailable", "output": "No Hyprland session"}
    monitors = runner(["hyprctl", "-j", "monitors"]) if env.get("HYPRLAND_INSTANCE_SIGNATURE") else unavailable
    errors = runner(["hyprctl", "configerrors"]) if env.get("HYPRLAND_INSTANCE_SIGNATURE") else unavailable
    hwaccels = runner(["ffmpeg", "-hide_banner", "-hwaccels"])
    encoders = runner(["ffmpeg", "-hide_banner", "-encoders"])
    protocols = runner(["wayland-info"]) if env.get("WAYLAND_DISPLAY") else {"status": "unavailable", "output": "No Wayland display"}
    capture_protocols = sorted(set(re.findall(r"\b(?:zwlr_screencopy_manager_v1|ext_image_copy_capture_manager_v1|ext_output_image_capture_source_manager_v1)\b", protocols["output"]))) if protocols["status"] == "ok" else []
    enc = sorted(set(re.findall(r"\b\w+_(?:nvenc|vaapi|qsv)\b", encoders["output"]))) if encoders["status"] == "ok" else []
    accelerators = [s.strip() for s in hwaccels["output"].splitlines()
                    if s.strip() in ("vaapi", "cuda", "qsv", "vdpau", "vulkan", "drm")] if hwaccels["status"] == "ok" else []
    keep = ("XDG_SESSION_TYPE", "WAYLAND_DISPLAY", "QSG_RHI_BACKEND", "QT_QUICK_BACKEND",
            "QT_FFMPEG_DECODING_HW_DEVICE_TYPES", "LIBGL_ALWAYS_SOFTWARE", "DRI_PRIME",
            "AQ_DRM_DEVICES", "__NV_PRIME_RENDER_OFFLOAD", "GBM_BACKEND")
    return {"schema": 1, "status": "ok", "timestamp": int(time.time()), "gpus": gpus,
            "fingerprint": fingerprint(gpus), "nvidiaModeset": modeset,
            "environment": {k: env[k] for k in keep if env.get(k)},
            "hyprland": {"monitors": monitors, "configErrors": errors},
            "decode": {"status": "unverified", "compiledBackends": accelerators,
                       "ffmpeg": hwaccels["status"], "note": "Compiled backends are candidates, not a successful decode."},
            "recording": {"status": "unverified", "tools": {k: bool(which(k)) for k in ("gpu-screen-recorder", "wf-recorder", "ffmpeg")},
                          "compiledEncoders": enc, "captureProtocols": capture_protocols, "protocolProbe": protocols["status"],
                          "note": "No screen capture started. Tool/encoder/protocol availability does not prove capture or encoding works."},
            "issues": diagnose(gpus, env, modeset, monitors, errors)}


def decode_probe(path, backend, device, runner=run):
    path = Path(path).expanduser().resolve()
    if not path.is_file() or path.suffix.lower() not in (".mp4", ".mkv", ".webm", ".mov"):
        return {"status": "error", "message": "Select an existing local MP4/MKV/WebM/MOV file."}
    if backend not in ("vaapi", "cuda"):
        return {"status": "error", "message": "Choose an explicit VA-API or CUDA backend."}
    if backend == "vaapi" and not re.fullmatch(r"/dev/dri/renderD\d+", device):
        return {"status": "error", "message": "Select a VA-API render node from the inventory."}
    if backend == "cuda" and not re.fullmatch(r"\d+", device):
        return {"status": "error", "message": "CUDA device must be a numeric CUDA ordinal (not a DRM card number)."}
    # GPU pixel format is mandatory on both input and the filter. This rejects
    # software fallback. Null muxer discards wrapped frames, no output is saved.
    output_format = "cuda" if backend == "cuda" else "vaapi"
    result = runner(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-nostats", "-progress", "pipe:1",
                     "-protocol_whitelist", "file,pipe",
                     "-hwaccel", backend, "-hwaccel_device", device,
                     "-hwaccel_output_format", output_format, "-i", str(path),
                     "-map", "0:v:0", "-an", "-sn", "-dn", "-vf", "format=" + output_format,
                     "-frames:v", "12", "-f", "null", "-"], timeout=20)
    frames = max([int(n) for n in re.findall(r"(?m)^frame=(\d+)\s*$", result["output"])] or [0])
    passed = result["status"] == "ok" and frames > 0
    return {"status": "passed" if passed else ("error" if result["status"] == "ok" else result["status"]),
            "frames": frames,
            "backend": backend, "device": device,
            "message": (str(frames) + " GPU frames decoded for this file. Qt Multimedia uses its own decoder; this does not verify it.") if passed else (result["output"][-4000:] or "No decoded frames were reported.")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decode-file")
    parser.add_argument("--backend", choices=("vaapi", "cuda"))
    parser.add_argument("--device", default="")
    args = parser.parse_args()
    try:
        result = decode_probe(args.decode_file, args.backend, args.device) if args.decode_file else collect()
    except Exception as exc:
        result = {"schema": 1, "status": "error", "message": str(exc)}
    print(json.dumps(result, ensure_ascii=True))


if __name__ == "__main__":
    main()
