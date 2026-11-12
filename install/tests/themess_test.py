"""Themess package validation and native-store transaction tests."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / "src/scripts/themess"
MRROBOT = ROOT / "themess/MrRobot"
sys.path.insert(0, str(ENGINE))
import themess

CAPS = {
    "modules": list(themess.KINDS),
    "widgetTypes": {"time": ["lockscreen"], "weather": ["compact"], "music": ["full"],
                    "cpu": ["default"], "ram": ["default"], "notes": ["default"]},
    "widgetScreen": "DP-1",
    "wallpaperScreens": ["DP-1", "HDMI-A-1"],
    "barModules": ["left", "workspaces", "timedate", "tray", "sysmon", "kb", "wifi", "vol", "bat"],
    "barMenu": ["launcher", "settings"],
    "workspacesStyles": ["pills"],
    "timeStyles": ["classic"],
}


class ThemessTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="themess-test-")
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        self.folder = self.home / "test package"
        self.folder.mkdir()
        self.addCleanup(patch.stopall)
        patch("themess.Path.home", return_value=self.home).start()
        patch.dict(os.environ, {
            "HOME": str(self.home), "USERPROFILE": str(self.home),
            "QS_SETTINGS": "", "QS_STATE_DIR": "", "QS_CACHE_DIR": "",
            "QS_CACHE_WALLPAPER": "", "QS_STATE_THEMESS": "",
        }).start()
        if hasattr(os, "geteuid") and os.geteuid() == 0:
            patch("themess.os.geteuid", return_value=1000).start()
        self.stores = themess.Stores(CAPS)

    def package_file(self, filename, value):
        path = self.folder / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(themess.encode(value))
        return path

    def report(self, folder=None, preview=False):
        return themess.report(themess.scan(folder or self.folder, CAPS), self.stores, preview)[0]

    def apply(self, token, folder=None):
        return themess.mutate(argparse.Namespace(action="apply", folder=folder or self.folder, token=token),
                             self.stores)

    def restore(self):
        return themess.mutate(argparse.Namespace(action="restore"), self.stores)

    def set_store(self, path, value):
        themess.write_atomic(path, themess.encode(value))
        return path.read_bytes()

    def test_cli_scan_and_preview_use_fallback_and_do_not_write(self):
        self.package_file("dock.json", {"floating": True})
        (self.folder / "theme.py").write_text("raise RuntimeError('must not run')", encoding="utf-8")
        for action in ("scan", "preview"):
            response = subprocess.run([sys.executable, str(ENGINE / "themess.py"), action,
                                       "--folder", str(self.folder), "--caps", json.dumps(CAPS)],
                                      check=True, capture_output=True, text=True)
            report = json.loads(response.stdout)
            self.assertEqual(report["components"], [{"kind": "dock", "file": "dock.json"}])
            self.assertEqual(report["settings"], [{"setting": "dock.floating", "before": None, "after": True}])
            self.assertEqual(report["preview"], action == "preview")
        self.assertFalse(self.stores.settings.exists())
        self.assertFalse(self.stores.directory.exists())

    def test_manifest_takes_precedence_and_unknown_component_is_ignored(self):
        self.package_file("dock.json", {"floating": True})
        self.package_file("deep/dock.json", {"enabled": False})
        self.package_file("theme.json", {"version": 1, "name": "Package", "components": {
            "dock": "deep/dock.json", "extension": "whatever.qml",
        }})
        report = self.report()
        self.assertEqual(report["source"], "theme.json")
        self.assertEqual(report["settings"][0]["setting"], "dock.enabled")
        self.assertIn("unknown component", report["warnings"][0])

    def test_invalid_manifest_never_falls_back(self):
        self.package_file("theme.json", {"version": 2})
        self.package_file("dock.json", {"enabled": False})
        report = self.report()
        self.assertFalse(report["components"])
        self.assertIn("version 1", report["errors"][0])
        self.assertNotIn("token", report)

    def test_unavailable_canvas_is_reported_and_skipped(self):
        self.package_file("canvas.json", {"enabled": True})
        self.package_file("dock.json", {"enabled": True})
        caps = dict(CAPS, modules=["dock"])
        plan = themess.scan(self.folder, caps)
        self.assertEqual(plan.components, [{"kind": "dock", "file": "dock.json"}])
        self.assertIn("unavailable", plan.warnings[0])
        self.assertNotIn("canvas", plan.settings)

    def test_rejects_unsafe_paths_and_extensions(self):
        for filename in ("../outside.json", "/tmp/target.json", "C:/a.json", "sub\\a.json",
                         "sub//a.json", "./a.json", "script.py"):
            with self.subTest(filename=filename):
                self.package_file("theme.json", {"version": 1, "name": "Package", "components": {
                    "dock": filename,
                }})
                self.assertTrue(self.report()["errors"])

    def test_rejects_symlink_to_a_component(self):
        data = self.package_file("elsewhere.json", {"enabled": False})
        try:
            (self.folder / "dock.json").symlink_to(data)
        except OSError as error:
            self.skipTest(str(error))
        self.assertTrue(self.report()["errors"])

    def test_rejects_unknown_fields_types_and_duplicate_json_keys(self):
        invalid = (("launcher.json", {"terminalCommand": "unexpected"}),
                   ("dock.json", {"enabled": "false"}),
                   ("dock.json", {"enabled": False, "unknown": True}),
                   ("materials.json", {"elementOpacity": 105}))
        for filename, value in invalid:
            with self.subTest(value=value):
                path = self.package_file(filename, value)
                self.assertTrue(self.report()["errors"])
                path.unlink()
        (self.folder / "dock.json").write_text('{"enabled": true, "enabled": false}', encoding="utf-8")
        self.assertIn("duplicate", self.report()["errors"][0])

    def test_rejects_unknown_widget_variant_and_resource_path(self):
        widget = {"type": "time", "id": "clock", "x": 0, "y": 0, "w": 60, "h": 60}
        for extra in ({"variant": "missing"}, {"imagePath": "/etc/passwd"}, {"type": "unknown"}):
            self.package_file("widgets.json", [dict(widget, **extra)])
            self.assertTrue(self.report()["errors"])

    def test_requires_a_new_scan_after_the_package_or_settings_change(self):
        path = self.package_file("dock.json", {"enabled": False})
        initial = self.report()["token"]
        self.package_file("dock.json", {"enabled": True})
        with self.assertRaisesRegex(ValueError, "Scan again"):
            self.apply(initial)
        self.assertFalse(self.stores.settings.exists())
        self.assertTrue(path.is_file())
        initial = self.report()["token"]
        self.set_store(self.stores.settings, {"dock": {"position": "top"}})
        with self.assertRaisesRegex(ValueError, "Scan again"):
            self.apply(initial)

    def test_noop_keeps_restore_point(self):
        self.package_file("dock.json", {"enabled": False})
        self.apply(self.report()["token"])
        self.assertFalse(self.report()["changed"])
        self.apply(self.report()["token"])
        self.assertTrue(themess.status(themess.metadata(self.stores))["canRestore"])
        self.restore()
        self.assertFalse(self.stores.settings.exists())

    def test_write_failure_restores_files_and_does_not_commit_history(self):
        original = self.set_store(self.stores.settings, {"theme": {"matugen": True}})
        self.package_file("dock.json", {"enabled": False})
        self.package_file("widgets.json", [])
        layout = self.stores.widget_path("DP-1")
        real_write = themess.write_atomic

        def failing_write(path, data):
            if path == layout:
                raise OSError("simulated failure")
            real_write(path, data)

        with patch("themess.write_atomic", side_effect=failing_write):
            with self.assertRaisesRegex(OSError, "simulated failure"):
                self.apply(self.report()["token"])
        self.assertEqual(self.stores.settings.read_bytes(), original)
        self.assertFalse(layout.exists())
        self.assertEqual(themess.status(themess.metadata(self.stores)), {"canRestore": False, "canRestoreOriginal": False, "active": None, "history": []})

    def test_interrupted_apply_rolls_back_written_files_only(self):
        original = self.set_store(self.stores.settings, {"theme": {"matugen": True}})
        self.package_file("dock.json", {"enabled": False})
        self.package_file("widgets.json", [])
        layout = self.stores.widget_path("DP-1")
        real_write = themess.write_atomic

        def interrupted_write(path, data):
            if path == layout:
                raise KeyboardInterrupt
            real_write(path, data)

        with patch("themess.write_atomic", side_effect=interrupted_write):
            with self.assertRaises(KeyboardInterrupt):
                self.apply(self.report()["token"])
        self.assertNotEqual(self.stores.settings.read_bytes(), original)
        self.assertTrue(themess.status(themess.metadata(self.stores))["canRestore"])
        self.assertIn("Interrupted", self.restore()["message"])
        self.assertEqual(self.stores.settings.read_bytes(), original)
        self.assertFalse(layout.exists())

    def test_library_discovery_import_remove_and_reimport_preserve_original_files(self):
        library = self.home / ".local/share/serpantinum/themess"
        automatic = library / "New desktop"
        automatic.mkdir(parents=True)
        (automatic / "dock.json").write_bytes(themess.encode({"enabled": True}))
        self.package_file("theme.json", {"version": 1, "name": "External", "author": "Author",
                                         "description": "A compact panel.", "components": {"panels": "panels.json"}})
        contents = self.package_file("panels.json", {"height": 32}).read_bytes()

        def library_action(action, folder):
            return themess.mutate(argparse.Namespace(action=action, folder=str(folder)), self.stores)

        def packages():
            return {item["folder"]: item for item in themess.catalog(self.stores, themess.metadata(self.stores))["packages"]}

        with patch("themess.__file__", str(self.home / "app/src/scripts/themess/themess.py")):
            self.assertIn(str(automatic.resolve()), packages())
            self.assertNotIn(str(self.folder.resolve()), packages())
            self.assertEqual(library_action("import", self.folder)["selection"], str(self.folder.resolve()))
            imported = packages()[str(self.folder.resolve())]
            self.assertEqual(imported["author"], "Author")
            self.assertEqual(imported["description"], "A compact panel.")
            self.assertEqual(imported["appearance"]["bar"]["height"], 32)
            library_action("remove", automatic)
            library_action("remove", self.folder)
            self.assertEqual(packages(), {})
            self.assertEqual((self.folder / "panels.json").read_bytes(), contents)
            self.assertTrue((automatic / "dock.json").exists())
            library_action("import", automatic)
            self.assertIn(str(automatic.resolve()), packages())
            self.assertFalse(self.stores.settings.exists())

    def test_restore_previous_and_original_track_packages_across_new_store_instances(self):
        before = self.set_store(self.stores.settings, {"dock": {"enabled": True}})
        self.package_file("dock.json", {"enabled": False})
        self.apply(self.report()["token"])
        first = self.stores.settings.read_bytes()
        first_folder = str(self.folder.resolve())
        second = self.home / "Second"
        second.mkdir()
        (second / "widgets.json").write_bytes(themess.encode([]))
        self.apply(self.report(second)["token"], second)
        layout = self.stores.widget_path("DP-1")
        self.assertTrue(layout.exists())
        self.stores = themess.Stores(CAPS)
        state = themess.status(themess.metadata(self.stores))
        self.assertEqual(state["active"]["folder"], str(second.resolve()))
        self.assertTrue(state["canRestoreOriginal"])
        self.assertEqual(self.restore()["active"]["folder"], first_folder)
        self.assertEqual(self.stores.settings.read_bytes(), first)
        self.assertFalse(layout.exists())
        result = themess.mutate(argparse.Namespace(action="restore-original"), self.stores)
        self.assertIsNone(result["active"])
        self.assertFalse(result["canRestoreOriginal"])
        self.assertEqual(self.stores.settings.read_bytes(), before)

    def test_restore_original_uses_first_backup_of_each_store(self):
        before = self.set_store(self.stores.settings, {"dock": {"position": "bottom"}})
        self.package_file("dock.json", {"position": "top"})
        self.apply(self.report()["token"])
        self.package_file("dock.json", {"position": "left"})
        self.package_file("widgets.json", [])
        self.apply(self.report()["token"])
        result = themess.mutate(argparse.Namespace(action="restore-original"), self.stores)
        self.assertIsNone(result["active"])
        self.assertEqual(self.stores.settings.read_bytes(), before)
        self.assertFalse(self.stores.widget_path("DP-1").exists())

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg required")
    def test_mr_robot_applies_all_real_components_and_restores_exact_files(self):
        settings = {"general": {"performance": False}, "launcher": {"terminalCommand": "kitty -e"},
                    "theme": {"matugen": True, "apps": []}, "bar": {"time": {"showSeconds": True}}}
        original_settings = self.set_store(self.stores.settings, settings)
        layout = self.stores.widget_path("DP-1")
        original_layout = self.set_store(layout, [{"wId": "keep"}])
        other_layout = self.stores.widget_path("HDMI-A-1")
        original_other_layout = self.set_store(other_layout, [{"wId": "other"}])
        first, first_title, _ = self.stores.wallpaper_paths("DP-1")
        themess.write_atomic(first, b"/home/user/old.png")
        themess.write_atomic(first_title, b"old.png")
        second, _, _ = self.stores.wallpaper_paths("HDMI-A-1")
        report = self.report(MRROBOT, preview=True)
        self.assertEqual(report["errors"], [])
        self.assertEqual({item["kind"] for item in report["components"]}, themess.KINDS)
        self.assertTrue(report["image"].startswith("data:image/png;base64,"))
        thumbnail = themess.package_view(themess.scan(MRROBOT, CAPS, thumbnail=True), show_image=True)
        self.assertEqual(thumbnail["packageToken"], report["packageToken"])
        self.assertEqual(thumbnail["appearance"]["theme"]["elementOpacity"], 87)
        self.assertEqual(len(thumbnail["widgets"]), 6)
        self.assertEqual(report["widgetCount"], 6)
        self.assertEqual(report["widgetScreen"], "DP-1")
        self.assertFalse(second.exists())
        self.assertEqual(self.apply(report["token"], MRROBOT)["history"], [str(MRROBOT)])
        current = json.loads(self.stores.settings.read_bytes())
        self.assertEqual(current["theme"]["activePreset"], "Mr. Robot")
        self.assertEqual(current["theme"]["elementOpacity"], 87)
        self.assertEqual(current["bar"]["modules"]["left"], ["left", "workspaces"])
        self.assertEqual(current["wallpaperTransition"]["effects"]["fade"]["duration"], 600)
        self.assertEqual(current["canvas"]["friction"], 8)
        self.assertTrue(current["dock"]["autohide"])
        self.assertEqual(current["launcher"]["position"], "center")
        self.assertFalse(current["notifications"]["sound"])
        self.assertEqual(current["launcher"]["terminalCommand"], "kitty -e")
        self.assertEqual(current["general"], settings["general"])
        self.assertEqual(current["bar"]["time"]["showSeconds"], True)
        self.assertEqual(len(json.loads(layout.read_bytes())), 6)
        self.assertEqual(json.loads(layout.read_bytes())[0]["wType"], "time")
        self.assertEqual(other_layout.read_bytes(), original_other_layout)
        self.assertEqual(first.read_bytes(), second.read_bytes())
        self.assertEqual(Path(first.read_text(encoding="utf-8")).read_bytes(), (MRROBOT / "wallpapers/mr-robot.gif").read_bytes())
        self.assertEqual(first_title.read_bytes(), b"mr-robot.gif")
        self.restore()
        self.assertEqual(self.stores.settings.read_bytes(), original_settings)
        self.assertEqual(layout.read_bytes(), original_layout)
        self.assertEqual(first.read_bytes(), b"/home/user/old.png")
        self.assertEqual(first_title.read_bytes(), b"old.png")
        self.assertFalse(second.exists())

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg required")
    def test_rejects_truncated_gif_with_valid_header(self):
        (self.folder / "wallpaper.gif").write_bytes(b"GIF89a\0")
        self.assertIn("could not be decoded", self.report()["errors"][0])


if __name__ == "__main__":
    unittest.main()
