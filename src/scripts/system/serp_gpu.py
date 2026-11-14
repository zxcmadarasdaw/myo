#!/usr/bin/env python3
"""GPU load for the desktop widgets: one JSON line per interval on stdout.

Sources, in order:
  * sysfs (amdgpu, recent i915/xe): /sys/class/drm/cardN/device/gpu_busy_percent,
    mem_info_vram_used / mem_info_vram_total and hwmon temp1_input;
  * nvidia-smi in its own loop mode (-l), relayed line by line (one child process).

When no source reports a load the line says {"available": false, "reason": ...}
and the widget shows "not measured" instead of an invented 0 %.
Reads only; never writes to sysfs and never needs privileges.
"""
import json
import os
import shutil
import subprocess
import sys
import time

SYS = os.environ.get("SERP_SYSFS", "/sys")


def read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return None


def number(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def sysfs_cards():
    base = os.path.join(SYS, "class", "drm")
    try:
        names = sorted(c for c in os.listdir(base) if c.startswith("card") and "-" not in c)
    except OSError:
        return []
    return [os.path.join(base, n, "device") for n in names
            if read(os.path.join(base, n, "device", "gpu_busy_percent")) is not None]


def hwmon_temp(device):
    root = os.path.join(device, "hwmon")
    try:
        entries = sorted(os.listdir(root))
    except OSError:
        return None
    for entry in entries:
        value = number(read(os.path.join(root, entry, "temp1_input")))
        if value is not None:
            return round(value / 1000.0)
    return None


def sample_sysfs(device):
    busy = number(read(os.path.join(device, "gpu_busy_percent")))
    if busy is None:
        return None
    used = number(read(os.path.join(device, "mem_info_vram_used")))
    total = number(read(os.path.join(device, "mem_info_vram_total")))
    driver = os.path.basename(os.path.realpath(os.path.join(device, "driver")))
    out = {"available": True, "source": "sysfs", "name": driver or "gpu", "percent": max(0, min(100, round(busy)))}
    if used is not None and total:
        out["vramUsedMb"] = round(used / 1048576)
        out["vramTotalMb"] = round(total / 1048576)
    temp = hwmon_temp(device)
    if temp is not None:
        out["temp"] = temp
    return out


def emit(payload):
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def parse_nvidia(line):
    parts = [p.strip() for p in line.split(",")]
    if len(parts) < 5:
        return None
    busy, used, total, temp = (number(p) for p in parts[:4])
    if busy is None:
        return None
    out = {"available": True, "source": "nvidia-smi", "name": parts[4] or "NVIDIA", "percent": max(0, min(100, round(busy)))}
    if used is not None and total:
        out["vramUsedMb"] = round(used)
        out["vramTotalMb"] = round(total)
    if temp is not None:
        out["temp"] = round(temp)
    return out


def run_nvidia(interval):
    command = ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,name",
               "--format=csv,noheader,nounits", "-l", str(max(1, int(interval)))]
    try:
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    except OSError:
        return False
    seen = False
    try:
        for line in child.stdout:
            sample = parse_nvidia(line.strip())
            if sample is None:
                continue
            seen = True
            emit(sample)
    finally:
        child.terminate()
    return seen


def main(argv):
    interval = 2.0
    once = "--once" in argv
    if "--interval" in argv:
        try:
            interval = max(0.5, float(argv[argv.index("--interval") + 1]))
        except (IndexError, ValueError):
            pass

    cards = sysfs_cards()
    if cards:
        while True:
            emit(sample_sysfs(cards[0]) or {"available": False, "reason": "sysfs"})
            if once:
                return 0
            time.sleep(interval)

    if shutil.which("nvidia-smi") and not once and run_nvidia(interval):
        return 0

    emit({"available": False, "reason": "no-source"})
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
