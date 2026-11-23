"""Regression tests for the generated Hyprland configuration and failed reloads."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / "src/scripts/system/hypr_animations.py"
spec = importlib.util.spec_from_file_location("hypr_animations", SCRIPT)
animations = importlib.util.module_from_spec(spec)
spec.loader.exec_module(animations)


class ProfilesTest(unittest.TestCase):
    def test_all_preset_profiles_and_default_round_trip(self):
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / "serpantinum-animations.lua"
            self.assertEqual(animations.read_profile(path), (None, "default"))
            for name in (*animations.PRESETS, None):
                with self.subTest(preset=name):
                    profile = animations.validate(animations.preset(name) if name else None)
                    source, revision = animations.generate(profile)
                    animations.atomic_write(path, source)
                    self.assertEqual(animations.read_profile(path), (profile, revision))
                    if not name:
                        self.assertNotIn("hl.animation", source)

    def test_effects_and_literal_application_class(self):
        profile = animations.preset("classic")
        profile["effects"]["open"].update(style="slide", direction="left", duration=185)
        profile["effects"]["close"].update(style="fade", duration=300)
        window_class = 'org.myo+editor"[dev]'
        profile["rules"] = [dict(value=window_class, match="initial_class", style="off")]
        source, _ = animations.generate(animations.validate(profile))
        self.assertIn('leaf = "windowsIn", enabled = true, speed = 1.85', source)
        self.assertIn('style = "slide left"', source)
        self.assertIn('leaf = "windowsOut", enabled = true, speed = 3', source)
        self.assertIn('style = "popin 100%"', source)
        regex = json.dumps(r'^org\.myo\+editor"\[dev\]$')
        self.assertIn(f'initial_class = {regex} }}, no_anim = true', source)

    def test_invalid_and_manually_edited_settings_are_rejected(self):
        profile = animations.preset("classic")
        profile["effects"]["close"]["duration"] = True
        with self.assertRaises(ValueError):
            animations.validate(profile)
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / "serpantinum-animations.lua"
            source, _ = animations.generate(None)
            path.write_text(source + "-- user changes\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "Custom animation file was kept"):
                animations.read_profile(path)
            self.assertTrue(path.read_text(encoding="utf-8").endswith("-- user changes\n"))

    @unittest.skipUnless(hasattr(os, "O_NOFOLLOW"), "requires Linux flock")
    def test_failed_compositor_reload_restores_previous_profile(self):
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / "serpantinum-animations.lua"
            current, later = animations.preset("classic"), animations.preset("minimal")
            previous, previous_revision = animations.generate(current)
            _, next_revision = animations.generate(later)
            animations.atomic_write(path, previous)
            with patch.object(animations, "hyprctl", side_effect=("", "ok", "invalid curve", "ok")) as ctl:
                with patch.object(animations, "require_revision") as check:
                    with self.assertRaisesRegex(RuntimeError, "invalid curve"):
                        animations.apply(path, later)
                    self.assertEqual([call.args[0] for call in check.call_args_list], [previous_revision, next_revision])
                self.assertEqual(ctl.call_args.args, ("reload",))
            self.assertEqual(animations.read_profile(path), (current, previous_revision))

    @unittest.skipUnless(hasattr(os, "O_NOFOLLOW"), "requires Linux flock")
    def test_apply_then_reset_stays_persisted(self):
        with tempfile.TemporaryDirectory() as work:
            path = Path(work) / "serpantinum-animations.lua"
            profile = animations.preset("cinematic")
            with patch.object(animations, "hyprctl", side_effect=("", "ok", "") * 2):
                with patch.object(animations, "require_revision"):
                    animations.apply(path, profile)
                    self.assertEqual(animations.read_profile(path)[0], profile)
                    animations.apply(path, None)
                    self.assertIsNone(animations.read_profile(path)[0])


if __name__ == "__main__":
    unittest.main()
