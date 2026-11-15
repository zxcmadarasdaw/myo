"""Native window modes and shortcut management with a fake hyprctl."""
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src/scripts/system"))
import window_actions as wa

ADDR = "0xabc"
MONITOR = {"id": 0, "name": "DP-1", "x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1,
           "transform": 0, "reserved": [0, 0, 0, 0]}
KEYBINDS = Path(__file__).resolve().parents[2] / "compositors/hyprland/config/keybinds.lua"


class FakeHyprctl:
    """Applies the dispatchers window_actions sends to one client, like Hyprland would."""

    def __init__(self, client, min_size=(0, 0)):
        self.client = {"address": ADDR, "mapped": True, "pid": 1, "initialClass": "firefox",
                       "stableId": "f1",
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
        elif method == "window.fullscreen":
            assert fields["mode"] == '"maximized"' and fields["action"] == '"set"'
            assert fields["layout_aware"] == "false"
            self.client["fullscreen"] = 1
            self.client["fullscreenClient"] = 1
        elif method == "window.pin":
            self.client["pinned"] = fields["action"] == '"on"'

    def methods(self):
        return [e[len("hl.dsp."):e.index("(")] for e in self.sent]


def actions(ctl, settings=None, state=None):
    state = {} if state is None else state
    return wa.WindowActions(ctl, state, lambda data: None, settings or {}), state


class FloatToggleTest(unittest.TestCase):
    def test_first_float_is_70_percent_centred_in_the_usable_area(self):
        ctl = FakeHyprctl({})
        result = actions(ctl)[0].float_toggle()
        self.assertEqual(result["action"], "floating")
        self.assertEqual(ctl.methods(), ["window.float", "window.resize", "window.move"])
        # bar (48) on top, dock (80) at the bottom, 16 px margin: 2528 x 1280 at (16, 64)
        x, y, w, h = result["geometry"]
        self.assertEqual((w, h), (round(2528 * .70), round(1280 * .70)))
        self.assertEqual((x, y), (16 + (2528 - w) // 2, 64 + (1280 - h) // 2))
        self.assertTrue(ctl.client["floating"])
        self.assertTrue(all('window = "stableid:f1"' in expr for expr in ctl.sent))

    def test_second_press_tiles_and_a_third_returns_to_the_users_geometry(self):
        ctl = FakeHyprctl({})
        act, state = actions(ctl)
        act.float_toggle()
        ctl.client["at"], ctl.client["size"] = [300, 200], [900, 700]   # user moved and resized it
        self.assertEqual(act.float_toggle()["action"], "tiled")
        self.assertFalse(ctl.client["floating"])
        self.assertEqual(state[wa.FLOAT_KEY][ADDR]["geometry"], [300, 200, 900, 700])
        ctl.sent.clear()
        self.assertEqual(act.float_toggle()["geometry"], [300, 200, 900, 700])
        self.assertEqual(state[wa.FLOAT_KEY][ADDR]["mode"], "floating")

    def test_maximized_float_keeps_monitor_and_workspace_then_restores_maximize(self):
        workspace = {"address": "web", "name": "web", "type": "normal"}
        ctl = FakeHyprctl({"workspace": workspace, "fullscreen": 1, "fullscreenClient": 1})
        act, state = actions(ctl)
        self.assertEqual(act.float_toggle()["action"], "floating")
        self.assertEqual(ctl.methods(), ["window.fullscreen_state", "window.float", "window.resize", "window.move"])
        self.assertFalse(ctl.client["pinned"])
        ctl.client["at"], ctl.client["size"] = [3, 5], [900, 700]
        self.assertEqual(act.float_toggle()["action"], "maximized")
        self.assertEqual(ctl.methods()[-2:], ["window.float", "window.fullscreen"])
        self.assertFalse(ctl.client["floating"])
        self.assertEqual(state[wa.FLOAT_KEY][ADDR]["workspace"], workspace)
        self.assertEqual(state[wa.FLOAT_KEY][ADDR]["monitor"], "DP-1")
        self.assertEqual(act.float_toggle()["geometry"], [3, 5, 900, 700])
        self.assertEqual(ctl.client["workspace"], workspace)

    def test_stale_address_record_is_not_used_by_a_new_window(self):
        ctl = FakeHyprctl({})
        act, state = actions(ctl)
        geometry = act.float_toggle()["geometry"]
        ctl.client["at"], ctl.client["size"] = [100, 200], [800, 600]
        act.float_toggle()
        ctl.client["stableId"] = "f2"
        ctl.client["title"] = "Same title"
        self.assertEqual(act.float_toggle()["geometry"], geometry)
        self.assertEqual(state[wa.FLOAT_KEY][ADDR]["identity"]["stableId"], "f2")

    def test_legacy_geometry_is_reused_and_migrated(self):
        ctl = FakeHyprctl({})
        geometry = [20, 65, 700, 500]
        act, state = actions(ctl, state={wa.FLOAT_KEY: {ADDR: geometry}})
        self.assertEqual(act.float_toggle()["geometry"], geometry)
        self.assertEqual(state[wa.FLOAT_KEY][ADDR]["identity"]["stableId"], "f1")

    def test_resize_failure_restores_the_previous_maximized_mode(self):
        class FailingHyprctl(FakeHyprctl):
            def dispatch(self, expression):
                if expression.startswith("hl.dsp.window.resize("):
                    raise wa.ActionError("resize failed")
                super().dispatch(expression)

        ctl = FailingHyprctl({"fullscreen": 1, "fullscreenClient": 1})
        act, state = actions(ctl)
        with self.assertRaisesRegex(wa.ActionError, "resize failed"):
            act.float_toggle()
        self.assertFalse(ctl.client["floating"])
        self.assertEqual(ctl.client["fullscreen"], 1)
        self.assertEqual(state, {})

    def test_fullscreen_window_leaves_fullscreen_then_floats(self):
        ctl = FakeHyprctl({"fullscreen": 2, "fullscreenClient": 2})
        act, _ = actions(ctl)
        self.assertEqual(act.float_toggle()["action"], "floating")
        self.assertEqual(ctl.methods()[:2], ["window.fullscreen_state", "window.float"])
        self.assertEqual((ctl.client["fullscreen"], ctl.client["floating"]), (0, True))
        self.assertEqual(act.float_toggle()["action"], "maximized")
        self.assertEqual(ctl.client["fullscreen"], 1)

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
        ctl = FakeHyprctl({"workspace": {"address": "serpantinum-minimized", "name": "serpantinum-minimized", "type": "special"}})
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
        self.assertIn(wa.bind_expression("SUPER + Z", "float", "Serpantinum window: float"), plan)
        self.assertFalse(any('"CTRL + Z"' in expression for expression in plan))
        self.assertTrue(all("ipc" not in expression for expression in plan))

    def test_old_ipc_binds_are_replaced(self):
        old = [{"modmask": 64, "key": "Z", "arg": "serpantinum ipc windows pin"},
               {"modmask": 65, "key": "Z", "arg": "serpantinum ipc windows minimize"},
               {"modmask": 68, "key": "Z", "arg": "serpantinum ipc windows restore"}]
        plan, conflicts = wa.bind_plan(old)
        self.assertEqual(conflicts, [])
        self.assertIn('hl.unbind("SUPER + Z")', plan)
        self.assertLess(plan.index('hl.unbind("SUPER + Z")'),
                        plan.index(wa.bind_expression("SUPER + Z", "float", "Serpantinum window: float")))
        self.assertNotIn('hl.unbind("SUPER + ALT + Z")', plan)

    def test_user_binds_are_never_stolen_and_current_binds_are_kept(self):
        mine = [{"modmask": 64, "key": "z", "arg": "my-own-thing"},
                {"modmask": 72, "key": "Z", "arg": "serpantinum window pin --notify"}]
        plan, conflicts = wa.bind_plan(mine)
        self.assertEqual(conflicts, ["SUPER + Z"])
        self.assertNotIn('hl.unbind("SUPER + Z")', plan)
        self.assertFalse(any('"SUPER + ALT + Z"' in e for e in plan))

    def test_hyprland_057_reference_ids_are_recognized_by_description(self):
        binds = [{"modmask": 64, "key": "Z", "arg": "31", "description": "Serpantinum window: float"}]
        plan, conflicts = wa.bind_plan(binds)
        self.assertEqual(conflicts, [])
        self.assertFalse(any('"SUPER + Z"' in expr for expr in plan))


class FloatShortcutTest(unittest.TestCase):
    class BindIPC:
        def __init__(self, binds=()):
            self.binds = list(binds)
            self.eval = []

        def query(self, name):
            assert name == "binds"
            return self.binds

        def execute(self, verb, expression):
            assert verb == "eval"
            self.eval.append(expression)

    def test_ctrl_z_is_created_only_on_opt_in_and_rebind_is_idempotent(self):
        ctl = self.BindIPC()
        self.assertEqual(wa.apply_float_shortcut(ctl, ""), "")
        self.assertEqual(ctl.eval, [])
        self.assertEqual(wa.apply_float_shortcut(ctl, "Ctrl+Z"), "CTRL + Z")
        self.assertIn(wa.bind_expression("CTRL + Z", "float", wa.EXTRA_FLOAT_BIND), ctl.eval[0])
        ctl.binds.append({"key": "Z", "modmask": 4, "description": wa.EXTRA_FLOAT_BIND})
        self.assertEqual(wa.apply_float_shortcut(ctl, "CTRL + Z"), "CTRL + Z")
        self.assertEqual(len(ctl.eval), 1)

    def test_conflicts_leave_the_existing_binding_intact(self):
        ctl = self.BindIPC([{"key": "Z", "modmask": 4, "description": wa.EXTRA_FLOAT_BIND},
                           {"key": "P", "modmask": 64, "description": "User shortcut"}])
        with self.assertRaisesRegex(wa.ActionError, "already in use"):
            wa.apply_float_shortcut(ctl, "Super+P")
        self.assertEqual(ctl.eval, [])

    def test_disable_removes_only_the_optional_binding_handle(self):
        ctl = self.BindIPC([{"key": "Z", "modmask": 4, "description": wa.EXTRA_FLOAT_BIND},
                           {"key": "Z", "modmask": 4, "description": "User shortcut"}])
        self.assertEqual(wa.apply_float_shortcut(ctl, ""), "")
        self.assertIn("previous:remove()", ctl.eval[0])
        self.assertIn("local nextBind = nil", ctl.eval[0])
        self.assertNotIn("hl.unbind", ctl.eval[0])

    def test_invalid_combo_cannot_generate_lua(self):
        ctl = self.BindIPC()
        with self.assertRaises(wa.ActionError):
            wa.apply_float_shortcut(ctl, 'Ctrl+Z"); print("extra")')
        self.assertEqual(ctl.eval, [])


class KeybindsFileTest(unittest.TestCase):
    def test_shipped_keybinds_match_the_runtime_plan(self):
        text = KEYBINDS.read_text(encoding="utf-8")
        for combo, action in wa.BINDINGS.items():
            key = 'mainMod .. " + ' + " + ".join(combo.split(" + ")[1:])
            self.assertIn(key + '", hl.dsp.exec_cmd("serpantinum window ' + action + ' --notify"), '
                          '{ description = "Serpantinum window: ' + action + '" })', text)
        self.assertNotIn("serpantinum ipc windows", text)
        self.assertIn('mode = "fullscreen", action = "toggle"', text)
        main = (KEYBINDS.parents[1] / "hyprland.lua").read_text(encoding="utf-8")
        self.assertIn('require("config/keybinds")', main)

    def test_each_mouse_button_uses_one_native_interactive_bind(self):
        lines = KEYBINDS.read_text(encoding="utf-8").splitlines()
        for button, dispatcher in ((272, "drag"), (273, "resize")):
            with self.subTest(button=button):
                binds = [line.strip() for line in lines
                         if line.lstrip().startswith("hl.bind(") and f"mouse:{button}" in line]
                self.assertEqual(binds, [
                    f'hl.bind(mainMod .. " + mouse:{button}", hl.dsp.window.{dispatcher}(), {{ mouse = true }})'
                ])


if __name__ == "__main__":
    unittest.main()
