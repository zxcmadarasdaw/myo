"""Super+Z Tiled/Floating and the runtime key bindings of window_actions.py, with a fake hyprctl."""
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src/scripts/system"))
import window_actions as wa

ADDR = "0xabc"
MONITOR = {"id": 0, "name": "DP-1", "x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1,
           "transform": 0, "reserved": [0, 0, 0, 0]}


class FakeHyprctl:
    """Applies the dispatchers window_actions sends to one client, like Hyprland would."""

    def __init__(self, client, min_size=(0, 0)):
        self.client = {"address": ADDR, "mapped": True, "pid": 1, "initialClass": "firefox",
                       "workspace": {"id": 1, "name": "1"}, "monitor": 0, "floating": False,
                       "pinned": False, "fullscreen": 0, "fullscreenClient": 0,
                       "at": [6, 54], "size": [2548, 1380], **client}
        self.min_size = min_size
        self.sent = []

    def query(self, name):
        return {"activewindow": self.client, "clients": [self.client], "monitors": [MONITOR],
                "layers": {}, "activeworkspace": {"id": 1}}[name]

    def dispatch(self, expression):
        self.sent.append(expression)
        fields = dict(re.findall(r"(\w+) = (\"[^\"]*\"|[\w.]+)", expression))
        method = expression[len("hl.dsp."):expression.index("(")]
        if method == "window.float":
            self.client["floating"] = fields["action"] == '"on"'
        elif method == "window.resize":
            self.client["size"] = [max(int(fields["x"]), self.min_size[0]), max(int(fields["y"]), self.min_size[1])]
        elif method == "window.move" and "x" in fields:
            self.client["at"] = [int(fields["x"]), int(fields["y"])]
        elif method == "window.fullscreen_state":
            self.client["fullscreen"] = int(fields["internal"])
            self.client["fullscreenClient"] = int(fields["client"])
        elif method == "window.pin":
            self.client["pinned"] = fields["action"] == '"on"'

    def methods(self):
        return [e[len("hl.dsp."):e.index("(")] for e in self.sent]


def actions(ctl, settings=None, state=None):
    state = {} if state is None else state
    return wa.WindowActions(ctl, state, lambda data: None, settings or {}), state


class FloatToggleTest(unittest.TestCase):
    def test_first_float_is_75_percent_centred_in_the_usable_area(self):
        ctl = FakeHyprctl({})
        result = actions(ctl)[0].float_toggle()
        self.assertEqual(result["action"], "floating")
        self.assertEqual(ctl.methods(), ["window.float", "window.resize", "window.move"])
        # bar (48) on top, dock (80) at the bottom, 16 px margin: 2528 x 1280 at (16, 64)
        x, y, w, h = result["geometry"]
        self.assertEqual((w, h), (round(2528 * .75), round(1280 * .75)))
        self.assertEqual((x, y), (16 + (2528 - w) // 2, 64 + (1280 - h) // 2))
        self.assertTrue(ctl.client["floating"])

    def test_second_press_tiles_and_a_third_returns_to_the_users_geometry(self):
        ctl = FakeHyprctl({})
        act, state = actions(ctl)
        act.float_toggle()
        ctl.client["at"], ctl.client["size"] = [300, 200], [900, 700]   # user moved and resized it
        self.assertEqual(act.float_toggle()["action"], "tiled")
        self.assertFalse(ctl.client["floating"])
        self.assertEqual(state[wa.FLOAT_KEY][ADDR], [300, 200, 900, 700])
        ctl.sent.clear()
        self.assertEqual(act.float_toggle()["geometry"], [300, 200, 900, 700])
        self.assertNotIn(ADDR, state[wa.FLOAT_KEY])

    def test_fullscreen_window_leaves_fullscreen_then_floats(self):
        ctl = FakeHyprctl({"fullscreen": 2, "fullscreenClient": 2})
        self.assertEqual(actions(ctl)[0].float_toggle()["action"], "floating")
        self.assertEqual(ctl.methods()[:2], ["window.fullscreen_state", "window.float"])
        self.assertEqual((ctl.client["fullscreen"], ctl.client["floating"]), (0, True))

    def test_floating_fullscreen_window_only_leaves_fullscreen(self):
        ctl = FakeHyprctl({"floating": True, "fullscreen": 2})
        self.assertEqual(actions(ctl)[0].float_toggle()["action"], "floating")
        self.assertEqual(ctl.methods(), ["window.fullscreen_state"])
        self.assertTrue(ctl.client["floating"])

    def test_pinned_float_is_unpinned_when_tiled(self):
        ctl = FakeHyprctl({"floating": True, "pinned": True})
        self.assertEqual(actions(ctl)[0].float_toggle()["action"], "tiled")
        self.assertEqual(ctl.methods(), ["window.pin", "window.float"])

    def test_client_minimum_size_stays_on_screen(self):
        ctl = FakeHyprctl({}, min_size=(2600, 300))
        x, y, w, h = actions(ctl)[0].float_toggle()["geometry"]
        self.assertEqual(w, 2600)
        self.assertEqual(x, 16)                      # cannot centre: aligned to the area

    def test_hidden_window_is_refused(self):
        ctl = FakeHyprctl({"workspace": {"id": -98, "name": wa.SPECIAL}})
        with self.assertRaises(wa.ActionError):
            actions(ctl)[0].float_toggle()

    def test_float_state_does_not_disturb_minimize_restore(self):
        ctl = FakeHyprctl({})
        act, state = actions(ctl)
        act.float_toggle()
        act.float_toggle()                          # geometry remembered under FLOAT_KEY
        self.assertEqual(act.restore()["action"], "nothing-to-restore")   # the float record is not a minimized window


class BindPlanTest(unittest.TestCase):
    def test_fresh_session_binds_all_window_keys_directly(self):
        plan, conflicts = wa.bind_plan([])
        self.assertEqual(conflicts, [])
        self.assertEqual(len(plan), 4)
        self.assertIn('hl.bind("SUPER + Z", hl.dsp.exec_cmd("serpantinum window float --notify"))', plan)
        self.assertTrue(all("ipc" not in expression for expression in plan))

    def test_old_ipc_binds_are_replaced(self):
        old = [{"modmask": 64, "key": "Z", "arg": "serpantinum ipc windows pin"},
               {"modmask": 65, "key": "Z", "arg": "serpantinum ipc windows minimize"},
               {"modmask": 68, "key": "Z", "arg": "serpantinum ipc windows restore"}]
        plan, conflicts = wa.bind_plan(old)
        self.assertEqual(conflicts, [])
        self.assertIn('hl.unbind("SUPER + Z")', plan)
        self.assertLess(plan.index('hl.unbind("SUPER + Z")'),
                        plan.index('hl.bind("SUPER + Z", hl.dsp.exec_cmd("serpantinum window float --notify"))'))
        self.assertNotIn('hl.unbind("SUPER + ALT + Z")', plan)

    def test_user_binds_are_never_stolen_and_current_binds_are_kept(self):
        mine = [{"modmask": 64, "key": "z", "arg": "my-own-thing"},
                {"modmask": 72, "key": "Z", "arg": "serpantinum window pin --notify"}]
        plan, conflicts = wa.bind_plan(mine)
        self.assertEqual(conflicts, ["SUPER + Z"])
        self.assertNotIn('hl.unbind("SUPER + Z")', plan)
        self.assertFalse(any('"SUPER + ALT + Z"' in e for e in plan))


class KeybindsFileTest(unittest.TestCase):
    def test_shipped_keybinds_match_the_runtime_plan(self):
        root = Path(__file__).resolve().parents[2]
        text = (root / "compositors/hyprland/config/keybinds.lua").read_text(encoding="utf-8")
        for combo, action in wa.BINDINGS.items():
            key = 'mainMod .. " + ' + " + ".join(combo.split(" + ")[1:])
            self.assertIn(key + '", hl.dsp.exec_cmd("serpantinum window ' + action + ' --notify"))', text)
        self.assertNotIn("serpantinum ipc windows", text)
        self.assertIn('mode = "fullscreen", action = "toggle"', text)
        self.assertIn('mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true }', text)
        self.assertIn('mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true }', text)
        main = (root / "compositors/hyprland/hyprland.lua").read_text(encoding="utf-8")
        self.assertIn('require("config/keybinds")', main)


if __name__ == "__main__":
    unittest.main()
