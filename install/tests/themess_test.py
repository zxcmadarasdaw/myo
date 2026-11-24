"""Themess package validation and native-store transaction tests."""
import argparse
import contextlib
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
            "XDG_CONFIG_HOME": str(self.home / ".config"),
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

    def test_fusion_components_apply_and_restore_previous_widget_layout(self):
        path = self.stores.widget_path("DP-1")
        before = self.set_store(path, [{"wId": "mine", "wType": "notes", "wGroup": "mine_group"}])
        widgets = [{"id": "cpu", "type": "cpu", "x": -240, "y": 50, "w": 240, "h": 180},
                   {"id": "ram", "type": "ram", "x": 10, "y": 50, "w": 240, "h": 180}]
        appearance = {"mode": "horizontal", "style": "technical", "animation": "fade", "gap": 10}
        group = {"id": "dashboard", "members": ["cpu", "ram"], "appearance": appearance}
        self.package_file("widgets.json", {"widgets": widgets, "groups": [group]})
        preview = self.report(preview=True)
        self.assertEqual(preview["widgetsBefore"], 1)
        self.assertEqual(path.read_bytes(), before)
        self.apply(preview["token"])
        layout = json.loads(path.read_bytes())
        for index, widget in enumerate(layout):
            self.assertEqual(widget["wGroup"], "dashboard")
            self.assertEqual(widget["wFusionIndex"], index)
            self.assertEqual(widget["wX"], widgets[index]["x"])
            self.assertEqual(json.loads(widget["wFusion"]), appearance)
        response = subprocess.run([sys.executable, str(ENGINE / "themess.py"), "export-fusion",
                                   "--caps", json.dumps(CAPS)], check=True, capture_output=True, text=True)
        exported = json.loads(response.stdout)["widgetPackage"]
        self.assertEqual(exported, {"widgets": widgets, "groups": [group]})
        self.restore()
        self.assertEqual(path.read_bytes(), before)
        for members in (["cpu", "cpu"], ["cpu", "missing"]):
            self.package_file("widgets.json", {"widgets": widgets, "groups": [dict(group, members=members)]})
            self.assertIn("unknown, anchored, stretched or already grouped widget", self.report()["errors"][0])

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

    def test_vpn_appearance_is_data_only_and_keeps_user_presets(self):
        presets = [{"id": "p1", "name": "Mine", "style": {"active": "#00ff88"}}]
        self.set_store(self.stores.settings, {"vpnAppearance": {"theme": "graphite", "presets": presets}})
        self.package_file("vpn.json", {"lineStyle": "flow", "active": "#9fdcff", "glow": 0.6})
        report = self.report()
        self.assertFalse(report["errors"], report["errors"])
        self.apply(report["token"])
        stored = json.loads(self.stores.settings.read_text(encoding="utf-8"))["vpnAppearance"]
        self.assertEqual(stored["theme"], "custom")
        self.assertEqual(stored["custom"], {"lineStyle": "flow", "active": "#9fdcff", "glow": 0.6})
        self.assertEqual(stored["presets"], presets)          # the user's own themes are untouched
        for value in ({"theme": "graphite", "subscription": "https://example.com/sub"},
                      {"theme": "user:p1"}, {"presets": []}, {"link": "vless://x"},
                      {"custom": {"active": "red"}}, {"custom": {"lineWidth": 60}}):
            with self.subTest(value=value):
                self.package_file("vpn.json", value)
                self.assertTrue(self.report()["errors"])

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

    def test_fastfetch_appearance_preserves_local_media_and_audio(self):
        local = {"path": "/home/user/video.mp4", "enabled": True, "playAudio": False}
        self.set_store(self.stores.settings, {"fastfetchMedia": local})
        appearance = {"theme": "glass_noir", "layout": "floating", "width": 48}
        self.package_file("fastfetch.json", {"appearance": appearance})
        report = self.report()
        self.assertEqual(report["errors"], [])
        self.apply(report["token"])
        self.assertEqual(json.loads(self.stores.settings.read_bytes())["fastfetchMedia"],
                         {**local, "appearance": appearance})
        self.package_file("fastfetch.json", {"appearance": appearance, "path": "/tmp/foreign.mp4"})
        self.assertTrue(self.report()["errors"])

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg and ffprobe required")
    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "requires FFmpeg and FFprobe")
    def test_violet_abyss_catalog_apply_switch_restore_and_reload(self):
        violet = ROOT / "themess/VioletAbyss"
        caps = dict(CAPS, widgetSize={"w": 1920, "h": 1080},
                    widgetTypes=dict.fromkeys(("time", "weather", "calendar", "quickactions", "terminal", "music",
                                               "cpu", "gpu", "ram", "disk", "network", "temp"), ["atelier"]),
                    barModules=CAPS["barModules"] + ["focus", "media", "bt"])
        self.stores = themess.Stores(caps)
        original_widgets = self.set_store(self.stores.widget_path("DP-1"), [{"wId": "original"}])
        self.set_store(self.stores.settings, {"theme": {"matugen": True}, "general": {"keep": "before"},
                                             "lockscreen": {"fingerprintEnabled": False}})
        motion = themess.motion
        motion_path = self.stores.motion_path()
        classic = motion.generate(motion.preset("classic"))[0].encode()
        themess.write_atomic(motion_path, classic)
        for screen in caps["wallpaperScreens"]:
            themess.write_atomic(self.stores.wallpaper_paths(screen)[0], b"/previous.png")
        self.package_file("dock.json", {"floating": False})

        def scan(folder):
            plan = themess.scan(folder, caps)
            self.assertFalse(plan.errors, plan.errors)
            return themess.report(plan, self.stores)[0]

        catalog = themess.catalog(self.stores, themess.metadata(self.stores))
        card = next(item for item in catalog["packages"] if item["name"] == "Violet Abyss")
        self.assertTrue(card["image"].startswith("data:image/png;base64,"))
        self.assertEqual(card["packageToken"], scan(violet)["packageToken"])
        with patch.object(themess, "video_snapshot", side_effect=ValueError("video decoder unavailable")):
            fallback = themess.scan(violet, caps)
        self.assertFalse(fallback.errors, fallback.errors)
        self.assertEqual(fallback.image[1], ".png")
        self.assertEqual(fallback.media[0], ".png")
        self.assertEqual(len(fallback.warnings), 2)
        with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "qa"}), \
                patch.object(motion, "profile_lock", side_effect=lambda path: contextlib.nullcontext()), \
                patch.object(motion, "check_integration"), patch.object(motion, "hyprctl", return_value=""), \
                patch.object(motion, "reload_profile") as reload_profile:
            violet_info = scan(violet)
            self.assertEqual(violet_info["widgetCount"], 12)
            self.assertEqual(self.apply(violet_info["token"], violet)["active"]["name"], "Violet Abyss")
            current = json.loads(self.stores.settings.read_bytes())
            self.assertEqual(current["theme"]["colors"]["crust"], "#07050D")
            self.assertEqual(current["terminalStyle"]["backgroundOpacity"], 0.93)
            self.assertFalse(current["lockscreen"]["fingerprintEnabled"])
            for screen in caps["wallpaperScreens"]:
                wallpaper = Path(self.stores.wallpaper_paths(screen)[0].read_text(encoding="utf-8"))
                self.assertTrue(wallpaper.is_file())
                self.assertEqual(wallpaper.suffix, ".webm")
            layout = json.loads(self.stores.widget_path("DP-1").read_bytes())
            self.assertEqual(layout[0]["wWidth"], 408.75)
            self.assertEqual(motion.read_profile(motion_path)[0]["preset"], "violet-abyss")

            self.stores = themess.Stores(caps)
            self.assertEqual(themess.status(themess.metadata(self.stores))["active"]["name"], "Violet Abyss")
            current["general"]["keep"] = "updated while active"
            self.set_store(self.stores.settings, current)
            self.apply(scan(self.folder)["token"])
            current = json.loads(self.stores.settings.read_bytes())
            self.assertEqual(current, {"theme": {"matugen": True}, "dock": {"floating": False},
                                       "lockscreen": {"fingerprintEnabled": False},
                                       "general": {"keep": "updated while active"}})
            self.assertEqual(self.stores.widget_path("DP-1").read_bytes(), original_widgets)
            self.assertEqual(motion_path.read_bytes(), classic)
            for screen in caps["wallpaperScreens"]:
                self.assertEqual(self.stores.wallpaper_paths(screen)[0].read_bytes(), b"/previous.png")
            self.assertEqual(self.restore()["active"]["name"], "Violet Abyss")
            self.assertEqual(motion.read_profile(motion_path)[0]["preset"], "violet-abyss")
            self.apply(scan(self.folder)["token"])
            self.apply(scan(violet)["token"], violet)
            self.assertEqual(reload_profile.call_count, 5)

    def test_bundled_error_girl_themes_scan_clean_and_share_one_free_codec_video(self):
        # Mochi Night and ERROR//OVERDRIVE name their media as @shared/...; both must scan
        # without errors with every widget variant they use, and the shared clips must not be
        # H.264/HEVC: Fedora's ffmpeg-free (and so Qt Multimedia there) cannot decode them.
        caps = dict(CAPS, widgetTypes={kind: ["atelier"] for kind in (
            "time", "calendar", "weather", "terminal", "music", "visualizer", "cpu", "gpu", "ram", "disk",
            "network")}, barModules=CAPS["barModules"] + ["focus", "media", "bt"],
            barMenu=["launcher", "settings", "shuffle"], workspacesStyles=["pills", "numbers"],
            timeStyles=["classic", "badge"])
        media = set()
        for name in ("MochiNight", "ErrorOverdrive"):
            plan = themess.scan(str(ROOT / "themess" / name), caps)
            self.assertEqual(plan.errors, [], name)
            self.assertEqual(plan.warnings, [], name)
            components = json.loads((ROOT / "themess" / name / "theme.json").read_text(encoding="utf-8"))["components"]
            self.assertEqual({item["kind"] for item in plan.components}, set(components), name)
            self.assertTrue(plan.image, name)
            media |= {value for key, value in components.items() if key in themess.MEDIA_KINDS}
        self.assertTrue(all(value.startswith(themess.SHARED_PREFIX) for value in media), media)
        for value in media:
            path = ROOT / "themess/.shared" / value[len(themess.SHARED_PREFIX):]
            probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                    "stream=codec_name", "-of", "csv=p=0", str(path)],
                                   capture_output=True, text=True, check=True)
            self.assertIn(probe.stdout.strip(), {"vp8", "vp9", "av1"}, path.name)

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg required")
    def test_velvet_and_neuro_apply_from_installed_library_and_restore_camera(self):
        library = self.home / ".local/share/serpantinum/themess"
        source = ROOT / "themess"
        for folder in ("VelvetNoir", "NeuroChaos", ".shared/noir-chaos"):
            shutil.copytree(source / folder, library / folder)
        caps = dict(CAPS, widgetTypes={kind: ["atelier"] for kind in (
            "time", "calendar", "weather", "terminal", "music", "visualizer", "cpu", "gpu", "ram", "disk",
            "network", "battery", "temp", "notes")}, barModules=CAPS["barModules"] + ["focus", "media", "bt"],
            workspacesStyles=["pills", "numbers"], timeStyles=["classic", "badge"],
            widgetSize={"w": 1920, "h": 1080})
        self.stores = themess.Stores(caps)
        layout = self.stores.widget_path("DP-1")
        camera = layout.with_name("canvas.json")
        previous = self.set_store(camera, {"schema_version": 1, "camera": {"x": 1500, "y": -900, "zoom": 2},
                                           "screen": {"w": 1920, "h": 1080}})
        asset_paths = []
        for folder, count in (("VelvetNoir", 11), ("NeuroChaos", 14)):
            path = library / folder
            plan = themess.scan(path, caps)
            result, _ = themess.report(plan, self.stores, preview=True)
            self.assertEqual(result["errors"], [])
            self.assertEqual(result["warnings"], [])
            self.assertEqual(result["referenceSize"], {"w": 2560, "h": 1440})
            self.assertTrue(result["image"].startswith("data:image/png;base64,"))
            self.assertEqual(self.apply(result["token"], path)["active"]["name"], plan.name)
            self.assertEqual(json.loads(camera.read_bytes())["camera"], {"x": 0, "y": 0, "zoom": 1})
            widgets = json.loads(layout.read_bytes())
            self.assertEqual(len(widgets), count)
            terminal = next(widget for widget in widgets if widget["wType"] == "terminal")
            original = next(widget for widget in plan.widgets if widget["wType"] == "terminal")
            self.assertEqual(terminal["wWidth"], original["wWidth"] * 0.75)
            self.assertEqual(terminal["mode"], "fetchShell")
            boxes = []
            for widget in plan.widgets:
                x, y, w, h = (widget[key] for key in ("wX", "wY", "wWidth", "wHeight"))
                vertical, horizontal = widget["anchor"].split()
                top = 42 if folder == "NeuroChaos" else 34
                x = 2560 - x - w if horizontal == "right" else x
                y = 1440 - y - h if vertical == "bottom" else top + y
                self.assertTrue(0 <= y < y + h <= 1440 and (x + w <= 800 or x >= 1800))
                self.assertFalse(any(x < r and other_x < x + w and y < b and other_y < y + h
                                     for other_x, other_y, r, b in boxes))
                boxes.append((x, y, x + w, y + h))
            settings = json.loads(self.stores.settings.read_bytes())["fastfetchMedia"]
            clip, poster = (Path(settings[key]) for key in ("path", "posterPath"))
            self.assertEqual(clip.read_bytes(), (library / ".shared/noir-chaos/anime-fastfetch.webm").read_bytes())
            self.assertTrue(poster.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"))
            asset_paths.append((clip, poster))
        self.assertEqual(*asset_paths)
        self.assertEqual(self.restore()["active"]["name"], "VELVET//NOIR")
        restored = themess.mutate(argparse.Namespace(action="restore-original"), self.stores)
        self.assertEqual(restored["canvasFiles"], [camera.as_posix()])
        self.assertEqual(camera.read_bytes(), previous)
        self.assertFalse(layout.exists())

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
        manifest = json.loads((MRROBOT / "theme.json").read_text(encoding="utf-8"))
        self.assertEqual({item["kind"] for item in report["components"]}, set(manifest["components"]))
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

    def make_video(self, name, *codec_args, size="320x180"):
        path = self.folder / name
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i",
                        f"testsrc=size={size}:rate=10:duration=1", *codec_args, str(path)],
                       check=True, capture_output=True, timeout=60)
        return path

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg required")
    def test_video_wallpapers_are_validated_and_applied(self):
        encoders = subprocess.run(["ffmpeg", "-v", "quiet", "-encoders"], capture_output=True, text=True).stdout
        made = []
        if "libx264" in encoders:
            made.append(self.make_video("wallpaper.mp4", "-c:v", "libx264", "-pix_fmt", "yuv420p"))
        if "libvpx-vp9" in encoders:
            made.append(self.make_video("clip.webm", "-c:v", "libvpx-vp9", "-b:v", "200k"))
        if not made:
            self.skipTest("no H.264 or VP9 encoder")
        for video in made:
            with self.subTest(video=video.name):
                for other in made:
                    if other != video:
                        other.rename(other.with_name("unused-" + other.name))
                self.package_file("theme.json", {"version": 1, "name": "Video", "components": {
                    "wallpaper": video.name}})
                report = self.report(preview=True)
                self.assertEqual(report["errors"], [])
                self.assertTrue(report["image"].startswith("data:image/png;base64,"))
                self.assertEqual(report["components"], [{"kind": "wallpaper", "file": video.name}])
                for other in made:
                    leftover = other.with_name("unused-" + other.name)
                    if leftover.exists():
                        leftover.rename(other)

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg required")
    def test_video_wallpaper_rejects_wrong_content_codec_and_truncation(self):
        self.package_file("theme.json", {"version": 1, "name": "Video", "components": {
            "wallpaper": "wallpaper.mp4"}})
        (self.folder / "wallpaper.mp4").write_bytes(b"GIF89a" + bytes(64))
        self.assertIn("does not match its extension", self.report()["errors"][0])
        (self.folder / "wallpaper.mp4").write_bytes(bytes([0, 0, 0, 24]) + b"ftypisom" + bytes(32))
        self.assertIn("could not be decoded", self.report()["errors"][0])
        self.make_video("wallpaper.mp4", "-c:v", "mpeg4")
        self.assertIn("unsupported video codec", self.report()["errors"][0])


if __name__ == "__main__":
    unittest.main()
