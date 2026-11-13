"""Control protocol tests; a mock transport does NOT verify actual DSP or PipeWire."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("equalizer", ROOT/"src/quickshell/media/equalizer.py")
eqmod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(eqmod)


class MusicEffectsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.calls = []
        self.failure = None
        self.nodes = [{"info":{"props":{"node.name":"serpantinum_sink"}}}]
        def runner(args, **kwargs):
            self.calls.append(args)
            self.assertNotIn("shell", kwargs)
            self.assertGreater(kwargs["timeout"], 0)
            if self.failure:
                raise self.failure
            return subprocess.CompletedProcess(args, 0, json.dumps(self.nodes), "")
        self.eq = eqmod.Equalizer(Path(self.temp.name)/"state", Path(self.temp.name)/"run", runner)

    def test_first_read_is_inert(self):
        self.assertEqual(self.eq.read(), eqmod.DEFAULT)
        self.assertEqual(self.calls, [])
        self.assertFalse(self.eq.saved.exists())

    def test_existing_daemon_migration(self):
        self.eq.state_dir.mkdir()
        (self.eq.state_dir/"audio.state").write_text("set 5 4 2 -1 -2 -1 2 4 5 6 0.2 1 0 night 0 1")
        state = self.eq.read()
        self.assertEqual(state["preset"], "Rock")
        self.assertEqual(state["balance"], 0.2)
        self.assertTrue(state["dyneq"])
        self.assertEqual(self.calls, [])

    def test_legacy_pending_draft_is_not_reported_as_applied(self):
        self.eq.cache.parent.mkdir(parents=True)
        self.eq.cache.write_text(json.dumps(dict(eqmod.DEFAULT, b1=12, pending=True)))
        self.assertEqual(self.eq.read()["b1"], 0)
        self.eq.state_dir.mkdir()
        (self.eq.state_dir/"audio.state").write_text("set 2 0 0 0 0 0 0 0 0 0 0 0 0 off 0 0")
        self.assertEqual(self.eq.read()["b1"], 2)

    def test_every_preset_sends_real_ten_band_parameters(self):
        for name, gains in eqmod.PRESETS.items():
            state = self.eq.execute("preset", [name])
            self.assertEqual([float(x) for x in self.calls[-1][3:13]], gains)
            self.assertEqual(self.calls[-1][:3], ["serpantinum-audio", "ctl", "set"])
            self.assertFalse(state["pending"])

    def test_live_band_and_tones_preserve_other_controls(self):
        self.eq.execute("set_balance", ["0.4"])
        for tone, bands in (("bass", [1,2,3]), ("mid", [4,5,6,7]), ("treble", [8,9,10])):
            state = self.eq.execute("set_tone", [tone, "4"])
            for band in bands:
                self.assertEqual(state[f"b{band}"], 4)
            self.assertEqual(state["balance"], 0.4)
        state = self.eq.execute("set_band", ["3", "-5"])
        self.assertEqual(state["b3"], -5)
        self.assertEqual(state["b2"], 4)

    def test_failure_does_not_publish_or_persist_success(self):
        self.eq.execute("preset", ["Vocal"])
        before = self.eq.saved.read_bytes(), self.eq.cache.read_bytes()
        self.failure = subprocess.CalledProcessError(1, ["serpantinum-audio"])
        with self.assertRaises(subprocess.CalledProcessError):
            self.eq.execute("preset", ["Rock"])
        self.assertEqual(before, (self.eq.saved.read_bytes(), self.eq.cache.read_bytes()))

    def test_missing_engine_does_not_seed_success(self):
        self.failure = FileNotFoundError("serpantinum-audio")
        with self.assertRaises(FileNotFoundError):
            self.eq.execute("set_band", ["1", "3"])
        self.assertFalse(self.eq.saved.exists())

    def test_timeout_does_not_change_state(self):
        self.failure = subprocess.TimeoutExpired("serpantinum-audio", 4)
        with self.assertRaises(subprocess.TimeoutExpired):
            self.eq.execute("reset", [])
        self.assertEqual(self.eq.read(), eqmod.DEFAULT)

    def test_bypass_preserves_curve_and_neutralizes_all_effects(self):
        self.eq.execute("preset", ["Rock"])
        self.eq.execute("set_mono", ["true"])
        self.eq.execute("set_dyneq", ["true"])
        state = self.eq.execute("set_effects", ["false"])
        self.assertEqual([float(x) for x in self.calls[-1][3:13]], [0]*10)
        self.assertEqual(self.calls[-1][-6:], ["0", "0", "0", "off", "0", "0"])
        self.assertEqual(state["b1"], 5)
        state = self.eq.execute("set_effects", ["true"])
        self.assertEqual(float(self.calls[-1][3]), 5)
        self.assertTrue(state["mono"])

    def test_invalid_and_injected_parameters_never_reach_transport(self):
        for command, args in [("set_band",["1; touch /tmp/evil","1"]), ("set_band",["11","1"]),
                              ("set_band",["1","nan"]), ("set_band",["1","13"]),
                              ("preset",["$(touch /tmp/evil)"]), ("set_balance",["inf"]),
                              ("set_dynamics",["evil"]), ("set_mono",["1"])]:
            with self.subTest(command=command, args=args), self.assertRaises((ValueError, KeyError)):
                self.eq.execute(command,args)
        self.assertEqual(self.calls, [])

    def test_save_custom_preset_is_data_only_and_survives_restart(self):
        self.eq.execute("preset", ["Electronic"])
        name = "My 'preset'; $(no execution)"
        count = len(self.calls)
        self.eq.execute("save_preset", [name])
        self.assertEqual(count, len(self.calls))
        self.eq.execute("reset", [])
        new = eqmod.Equalizer(self.eq.state_dir, self.eq.run_dir, self.eq.runner)
        self.assertEqual(new.execute("preset", [name])["b1"], 5)
        self.assertEqual(new.read()["preset"], name)

    def test_state_survives_deleted_runtime_cache(self):
        self.eq.execute("preset", ["Cinema"])
        self.eq.cache.unlink()
        self.assertEqual(self.eq.read()["preset"], "Cinema")

    def test_missing_components_and_device_are_reported(self):
        with patch.object(eqmod.shutil, "which", return_value=None):
            self.assertFalse(self.eq.status()[0])
        with patch.object(eqmod.shutil, "which", return_value="/usr/bin/tool"):
            self.assertTrue(self.eq.status()[0])
            self.nodes = []
            self.assertFalse(self.eq.status()[0])

    def test_corrupt_state_is_reported_not_overwritten(self):
        self.eq.saved.parent.mkdir(parents=True)
        self.eq.saved.write_text("{broken")
        with self.assertRaises(ValueError):
            self.eq.execute("preset", ["Flat"])
        self.assertEqual(self.eq.saved.read_text(), "{broken")
        self.assertEqual(self.calls, [])

    def test_all_legacy_controls_keep_the_protocol(self):
        for command, args in [("set_mono",["true"]), ("set_swap",["true"]), ("set_dynamics",["night"]),
                              ("set_dyneq",["true"]), ("set_balance",["-0.5"]), ("apply",[])]:
            self.eq.execute(command,args)
        self.assertEqual(self.calls[-1][-6:], ["-0.5","1","1","night","0","1"])
        state = self.eq.execute("reset_audio",[])
        self.assertFalse(state["mono"])
        self.assertTrue(state["dyneq"])


if __name__ == "__main__":
    unittest.main()
