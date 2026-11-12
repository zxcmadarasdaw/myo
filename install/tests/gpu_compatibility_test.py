"""Portable tests of Linux probe logic; fake sysfs/commands, no host changes."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("gpu", ROOT / "src/scripts/system/gpu_compatibility.py")
gpu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gpu)


def card(address="0000:03:00.0", vendor="0x1002", device="0x73ff", driver="amdgpu"):
    return {"address": address, "vendorId": vendor, "deviceId": device, "vendor": "AMD",
            "model": vendor + ":" + device, "driver": driver, "renderNodes": ["/dev/dri/renderD128"],
            "nodes": [], "connectors": []}


class ProbeTests(unittest.TestCase):
    def test_replacement_changes_identity_but_driver_update_does_not(self):
        old = card()
        self.assertEqual(gpu.fingerprint([old]), gpu.fingerprint([{**old, "driver": "updated"}]))
        self.assertNotEqual(gpu.fingerprint([old]), gpu.fingerprint([card(vendor="0x10de", device="0x2d05", driver="nvidia")]))

    def test_multigpu_order_and_card_number_do_not_change_identity(self):
        a, b = card(), card(address="0000:00:02.0", vendor="0x8086", driver="xe")
        self.assertEqual(gpu.fingerprint([a, b]), gpu.fingerprint([b, a]))
        self.assertEqual(gpu.fingerprint([a]), gpu.fingerprint([{**a, "nodes": [{"name": "card9"}]}]))
        self.assertEqual(gpu.fingerprint([]), "")

    def test_nvidia_kms_unknown_is_warning_not_supported(self):
        env = {"XDG_SESSION_TYPE": "wayland", "WAYLAND_DISPLAY": "wayland-1"}
        issues = gpu.diagnose([card(vendor="0x10de", driver="nvidia")], env, "unknown", {}, {})
        self.assertIn("nvidia-kms", [i["code"] for i in issues])
        issues = gpu.diagnose([card(vendor="0x10de", driver="nvidia")], env, "Y", {}, {})
        self.assertNotIn("nvidia-kms", [i["code"] for i in issues])

    def test_session_permissions_and_hyprland_errors(self):
        env = {"HYPRLAND_INSTANCE_SIGNATURE": "x", "LIBGL_ALWAYS_SOFTWARE": "1"}
        g = {**card(driver="unknown"), "renderNodes": []}
        issues = gpu.diagnose([g], env, "unknown", {"status": "error"}, {"status": "ok", "output": "bad config"})
        codes = {i["code"] for i in issues}
        self.assertTrue({"session", "hypr-ipc", "hypr-config", "software", "access-0000:03:00.0", "driver-0000:03:00.0"} <= codes)

    def test_unavailable_tools_are_not_claimed_supported(self):
        missing = lambda *a, **kw: {"status": "missing", "output": "missing"}
        with tempfile.TemporaryDirectory() as tmp:
            result = gpu.collect(Path(tmp), Path(tmp), env={}, runner=missing, which=lambda _: None, platform="linux")
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["decode"]["compiledBackends"], [])
        self.assertEqual(result["recording"]["status"], "unverified")
        self.assertFalse(any(result["recording"]["tools"].values()))
        self.assertEqual(result["fingerprint"], "")

    def test_compiled_codecs_are_candidates_only(self):
        def runner(argv, **kw):
            if "-hwaccels" in argv: return {"status": "ok", "output": "Hardware acceleration methods:\nvaapi\ncuda\n"}
            if "-encoders" in argv: return {"status": "ok", "output": " V....D h264_nvenc\n V....D av1_vaapi"}
            return {"status": "ok", "output": "interface: 'zwlr_screencopy_manager_v1', version: 3"}
        with tempfile.TemporaryDirectory() as tmp:
            result = gpu.collect(Path(tmp), Path(tmp), env={"WAYLAND_DISPLAY": "wayland-1"}, runner=runner, which=lambda _: "/bin/tool", platform="linux")
        self.assertEqual(result["decode"]["compiledBackends"], ["vaapi", "cuda"])
        self.assertEqual(result["decode"]["status"], "unverified")
        self.assertEqual(result["recording"]["compiledEncoders"], ["av1_vaapi", "h264_nvenc"])
        self.assertEqual(result["recording"]["captureProtocols"], ["zwlr_screencopy_manager_v1"])

    def test_non_linux_is_explicit_and_runs_no_commands(self):
        def forbidden(*args, **kw): self.fail("must not probe this host")
        self.assertEqual(gpu.collect(platform="win32", runner=forbidden)["status"], "unsupported")

    def test_command_missing_and_timeout(self):
        with patch.object(subprocess, "run", side_effect=FileNotFoundError):
            self.assertEqual(gpu.run(["missing"])["status"], "missing")
        with patch.object(subprocess, "run", side_effect=subprocess.TimeoutExpired("test", 1)):
            self.assertEqual(gpu.run(["test"])["status"], "timeout")

    def test_inventory_deduplicates_card_and_render_nodes(self):
        # Resolve fixture paths instead of relying on symlink privileges on Windows.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            mappings = {}
            for node in ("card0", "renderD128"):
                dev = root / "sys/class/drm" / node / "device"
                dev.mkdir(parents=True)
                (dev / "vendor").write_text("0x8086")
                (dev / "device").write_text("0x1234")
                (dev / "driver").mkdir()
                mappings[dev] = root / "0000:00:02.0"
                mappings[dev / "driver"] = root / "drivers/xe"
                node_file = root / "dev/dri" / node
                node_file.parent.mkdir(parents=True, exist_ok=True)
                node_file.touch()
            connector = root / "sys/class/drm/card0-DP-1"
            connector.mkdir()
            (connector / "status").write_text("connected")
            (connector / "enabled").write_text("enabled")
            real_resolve = Path.resolve
            def resolve(path, *a, **kw): return mappings.get(path) or real_resolve(path, *a, **kw)
            with patch.object(Path, "resolve", resolve):
                result = gpu.inventory(root / "sys", root / "dev", lambda argv: {"status": "ok", "output": "Intel test GPU"})
            self.assertEqual(len(result), 1)
            self.assertEqual(result[0]["driver"], "xe")
            self.assertEqual(len(result[0]["nodes"]), 2)
            self.assertEqual(result[0]["connectors"][0]["enabled"], "enabled")

    def test_decode_requires_hardware_frames_and_does_not_use_shell(self):
        calls = []
        def runner(argv, **kw):
            calls.append((argv, kw))
            return {"status": "ok", "output": "frame=12\nprogress=end"}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "video ; test.mp4"
            path.touch()
            result = gpu.decode_probe(path, "vaapi", "/dev/dri/renderD128", runner)
            self.assertEqual(result["status"], "passed")
            argv, kw = calls[0]
            self.assertIn(str(path.resolve()), argv)
            self.assertIn("format=vaapi", argv)
            self.assertEqual(argv[argv.index("-hwaccel_output_format") + 1], "vaapi")
            self.assertEqual(kw["timeout"], 20)
            self.assertNotIn("shell", kw)
            empty = lambda *a, **kw: {"status": "ok", "output": "frame=0\nprogress=end"}
            self.assertEqual(gpu.decode_probe(path, "cuda", "0", empty)["status"], "error")
            self.assertEqual(gpu.decode_probe(path, "cuda", "/dev/dri/card0", runner)["status"], "error")
            self.assertEqual(gpu.decode_probe(path, "vaapi", "bad; device", runner)["status"], "error")
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
