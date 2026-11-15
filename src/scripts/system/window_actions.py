#!/usr/bin/env python3
"""Addressed Hyprland window actions. No shell interpolation or close/kill fallback."""
import argparse
import contextlib
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys

SPECIAL = "special:serpantinum-minimized"
# Super+Z is plain Tiled <-> Floating; pinning across workspaces moved to Super+Alt+Z.
# The commands call this script directly ("serpantinum window ..."), not through the
# Quickshell IPC, so the keys keep working while the shell is busy or restarting.
BINDINGS = {"SUPER + Z": "float", "SUPER + ALT + Z": "pin",
            "SUPER + SHIFT + Z": "minimize", "SUPER + CTRL + Z": "restore"}
MODMASK = {"SUPER": 64, "SHIFT": 1, "CTRL": 4, "ALT": 8}
LEGACY_COMMAND = "serpantinum ipc windows "   # binds written by older releases
FLOAT_KEY = "_floating"                      # remembered floating geometry per window


class ActionError(RuntimeError):
    pass


def address(value):
    value = str(value or "").removeprefix("address:").removeprefix("0x")
    if not re.fullmatch(r"[0-9a-fA-F]{1,16}", value) or int(value, 16) == 0:
        raise ActionError("Invalid window address")
    return "0x" + value.lower()


def lua_string(value):
    # JSON's ASCII escaping is not Lua's \u syntax; preserve Unicode instead.
    return json.dumps(str(value), ensure_ascii=False)


class Hyprctl:
    def run(self, *args):
        try:
            result = subprocess.run(["hyprctl", *args], text=True, capture_output=True, timeout=8)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ActionError(str(exc)) from exc
        if result.returncode:
            raise ActionError((result.stderr or result.stdout).strip() or "hyprctl failed")
        return result.stdout.strip()

    def query(self, name):
        try:
            return json.loads(self.run(name, "-j"))
        except ValueError as exc:
            raise ActionError("Invalid hyprctl JSON: " + name) from exc

    def dispatch(self, expression):
        result = self.run("dispatch", expression)
        if result.lower() != "ok":
            raise ActionError(result or "Empty dispatcher response")


def number(value, default, low, high):
    try:
        n = float(value)
    except (TypeError, ValueError):
        n = default
    if not math.isfinite(n):
        n = default
    return max(low, min(high, n))


def pin_options(settings):
    raw = settings.get("windowActions", {})
    raw = raw if isinstance(raw, dict) else {}
    corner = raw.get("corner", "top-right")
    if corner not in ("top-left", "top-right", "bottom-left", "bottom-right"):
        corner = "top-right"
    return {"corner": corner, "widthFraction": number(raw.get("widthFraction"), .32, .15, .8),
            "heightFraction": number(raw.get("heightFraction"), .32, .15, .8),
            "margin": round(number(raw.get("margin"), 16, 0, 200))}


def usable_rect(monitor, settings, margin):
    scale = number(monitor.get("scale"), 1, .25, 8)
    width, height = monitor["width"] / scale, monitor["height"] / scale
    if int(monitor.get("transform", 0)) % 2:
        width, height = height, width
    left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
    # Also leave room for the project's non-exclusive/autohiding bar and dock.
    pads = {"left": left, "top": top, "right": right, "bottom": bottom}
    ui = number(settings.get("general", {}).get("uiScale"), 1, .5, 3)
    for key, default_side, default_size in (("bar", "top", 48), ("dock", "bottom", 80)):
        cfg = settings.get(key, {})
        if not isinstance(cfg, dict) or cfg.get("enabled") is False:
            continue
        side = cfg.get("position", default_side)
        if side in pads:
            pads[side] = max(pads[side], default_size * ui)
    x = monitor["x"] + pads["left"] + margin
    y = monitor["y"] + pads["top"] + margin
    w = width - pads["left"] - pads["right"] - 2 * margin
    h = height - pads["top"] - pads["bottom"] - 2 * margin
    if w < 1 or h < 1:
        raise ActionError("No usable monitor area")
    return round(x), round(y), math.floor(w), math.floor(h)


def widget_rects(layers, monitor):
    """Layer coordinates in hyprctl are monitor-local logical coordinates."""
    result = []
    entry = layers.get(monitor["name"], {})
    for rows in entry.get("levels", {}).values():
        for row in rows:
            ns = row.get("namespace", "")
            if ((ns.startswith("qs-widget-") and not ns.startswith("qs-widget-redactor-"))
                    or ns.startswith("qs-music-studio-") or ns == "qs-canvas-minimap"):
                if row.get("w", 0) > 0 and row.get("h", 0) > 0:
                    result.append((monitor["x"] + row["x"], monitor["y"] + row["y"], row["w"], row["h"]))
    return result


def place(area, size, corner, obstacles):
    x, y, aw, ah = area
    w, h = map(round, size)
    if w < 1 or h < 1 or w > aw or h > ah:
        raise ActionError("Window does not fit the usable area")
    preferred = (x + aw - w if corner.endswith("right") else x,
                 y + ah - h if corner.startswith("bottom") else y)
    xs, ys = {x, x + aw - w}, {y, y + ah - h}
    for ox, oy, ow, oh in obstacles:
        xs.update((ox - w - 8, ox + ow + 8))
        ys.update((oy - h - 8, oy + oh + 8))
    candidates = sorted(((px, py) for px in xs for py in ys),
                        key=lambda p: (p[0] - preferred[0]) ** 2 + (p[1] - preferred[1]) ** 2)
    for px, py in candidates:
        if not (x <= px <= x + aw - w and y <= py <= y + ah - h):
            continue
        if all(px + w <= ox or ox + ow <= px or py + h <= oy or oy + oh <= py
               for ox, oy, ow, oh in obstacles):
            return round(px), round(py), w, h
    raise ActionError("No room to pin without covering desktop widgets; reduce the configured size")


def float_fraction(settings):
    raw = settings.get("windowActions", {})
    raw = raw if isinstance(raw, dict) else {}
    return number(raw.get("floatFraction"), .75, .4, 1)


def bind_plan(binds):
    """Same binds -j / eval mechanism as ProcessExplorerController; do not steal keys.

    A key still bound to an older Serpantinum window command (Super+Z used to pin) is
    rebound; a key the user bound to anything else is reported as a conflict."""
    expressions, conflicts = [], []
    for combo, action in BINDINGS.items():
        command = "serpantinum window " + action + " --notify"
        mask = sum(MODMASK[part.strip()] for part in combo.split("+")[:-1])
        if any(command == b.get("arg") for b in binds):
            continue
        taken = [b for b in binds if str(b.get("key", "")).lower() == "z" and b.get("modmask") == mask
                 and not b.get("submap")]
        if any(not str(b.get("arg", "")).startswith(LEGACY_COMMAND) for b in taken):
            conflicts.append(combo)
            continue
        if taken:
            expressions.append("hl.unbind(" + lua_string(combo) + ")")
        expressions.append("hl.bind(" + lua_string(combo) + ", hl.dsp.exec_cmd(" + lua_string(command) + "))")
    return expressions, conflicts


class WindowActions:
    def __init__(self, ctl, state, save, settings):
        self.ctl, self.state, self.save, self.settings = ctl, state, save, settings

    def clients(self):
        return {address(c["address"]): c for c in self.ctl.query("clients") if c.get("mapped", True)}

    def window(self, requested=None):
        key = address(requested or self.ctl.query("activewindow").get("address"))
        win = self.clients().get(key)
        if not win:
            raise ActionError("Window no longer exists")
        return key, win

    def dispatch(self, method, key, **args):
        fields = ["window = " + lua_string("address:" + key)]
        for name, value in args.items():
            val = ("true" if value else "false") if isinstance(value, bool) else (
                str(value) if isinstance(value, (int, float)) else lua_string(value))
            fields.append(name + " = " + val)
        self.ctl.dispatch("hl.dsp." + method + "({ " + ", ".join(fields) + " })")

    def focus(self, key):
        self.dispatch("focus", key)

    def minimize(self, requested=None):
        key, win = self.window(requested)
        if win.get("workspace", {}).get("name") == SPECIAL:
            return {"action": "already-minimized", "address": key}
        workspace = win.get("workspace", {})
        if workspace.get("id", 0) <= 0:
            raise ActionError("Move this window to a regular workspace before minimizing")
        record = {"pid": win.get("pid"), "initialClass": win.get("initialClass"),
                  "workspace": str(workspace["id"]), "pinned": bool(win.get("pinned"))}
        self.state.pop(key, None)
        self.state[key] = record  # insertion order = most recently minimized
        self.save(self.state)  # save before moving; survive shell restart
        try:
            if record["pinned"]:
                self.dispatch("window.pin", key, action="off")
            self.dispatch("window.move", key, workspace=SPECIAL, follow=False)
        except ActionError:
            # Leave recovery metadata if a timed-out move actually succeeded.
            if record["pinned"]:
                self.dispatch("window.pin", key, action="on")
            raise
        return {"action": "minimized", "address": key}

    def restore(self, requested=None):
        clients = self.clients()
        hidden = [k for k, c in clients.items() if c.get("workspace", {}).get("name") == SPECIAL]
        if requested:
            key = address(requested)
            if key not in clients:
                raise ActionError("Window no longer exists")
        else:
            ordered = [k for k in self.state if k in hidden]
            key = (ordered or hidden or [None])[-1]
            if key is None:
                return {"action": "nothing-to-restore"}
        win = clients[key]
        if key in hidden:
            record = self.state.get(key, {})
            if record.get("pid") != win.get("pid") or record.get("initialClass") != win.get("initialClass"):
                record = {}
            # Restore to the user's current regular workspace, not a hidden one.
            current = self.ctl.query("activeworkspace")
            ws = str(current.get("id", 0)) if current.get("id", 0) > 0 else record.get("workspace", "1")
            self.dispatch("window.move", key, workspace=ws, follow=False)
            if record.get("pinned"):
                self.dispatch("window.pin", key, action="on")
            self.state.pop(key, None)
            self.save(self.state)
        self.focus(key)
        return {"action": "restored" if key in hidden else "focused", "address": key}

    def monitor_of(self, win):
        monitor = next((m for m in self.ctl.query("monitors") if m["id"] == win.get("monitor")), None)
        if monitor is None:
            raise ActionError("Window monitor is unavailable")
        return monitor

    def float_toggle(self):
        """Super+Z: Tiled <-> Floating with Hyprland's own float dispatcher.

        Fullscreen is left first. A window that floats for the first time gets a
        comfortable size (75 % of the usable area) centred on its monitor; later it
        comes back where the user left it. Nothing else about the window changes."""
        key, win = self.window()
        if win.get("workspace", {}).get("id", 0) <= 0:
            raise ActionError("Restore the window from its special workspace first")
        clients = self.clients()
        saved = self.state.get(FLOAT_KEY)
        saved = {k: v for k, v in saved.items() if k in clients} if isinstance(saved, dict) else {}
        fullscreen = bool(win.get("fullscreen") or win.get("fullscreenClient"))

        def remember():
            self.state[FLOAT_KEY] = saved
            self.save(self.state)

        if win.get("floating") and not fullscreen:
            saved[key] = [*win["at"], *win["size"]]
            if win.get("pinned"):
                self.dispatch("window.pin", key, action="off")
            self.dispatch("window.float", key, action="off")
            remember()
            return {"action": "tiled", "address": key}
        if fullscreen:
            self.dispatch("window.fullscreen_state", key, internal=0, client=0, action="set")
            if win.get("floating"):          # a floating window in fullscreen: back to its float
                return {"action": "floating", "address": key}

        area = usable_rect(self.monitor_of(win), self.settings, 16)
        ax, ay, aw, ah = area
        geometry = saved.get(key)
        if not (isinstance(geometry, list) and len(geometry) == 4
                and ax <= geometry[0] + geometry[2] / 2 <= ax + aw
                and ay <= geometry[1] + geometry[3] / 2 <= ay + ah):
            fraction = float_fraction(self.settings)
            w, h = round(aw * fraction), round(ah * fraction)
            geometry = [ax + (aw - w) // 2, ay + (ah - h) // 2, w, h]
        x, y, w, h = (round(v) for v in geometry)
        w, h = min(w, aw), min(h, ah)
        self.dispatch("window.float", key, action="on")
        self.dispatch("window.resize", key, x=w, y=h, relative=False)
        # Clients may refuse sizes below their minimum: place what they actually took.
        actual = self.clients().get(key)
        if actual is None:
            raise ActionError("Window closed while floating")
        w, h = actual.get("size", [w, h])
        if key not in saved:
            x, y = ax + (aw - w) // 2, ay + (ah - h) // 2
        x = max(ax, min(x, ax + aw - w))
        y = max(ay, min(y, ay + ah - h))
        self.dispatch("window.move", key, x=round(x), y=round(y), relative=False)
        saved.pop(key, None)
        remember()
        return {"action": "floating", "address": key, "geometry": [round(x), round(y), w, h]}

    def pin(self):
        key, win = self.window()
        if win.get("pinned"):
            self.dispatch("window.pin", key, action="off")
            self.dispatch("window.float", key, action="off")
            return {"action": "tiled", "address": key}
        if win.get("workspace", {}).get("id", 0) <= 0:
            raise ActionError("Restore the window from its special workspace before pinning")
        monitors = self.ctl.query("monitors")
        monitor = next((m for m in monitors if m["id"] == win.get("monitor")), None)
        if monitor is None:
            raise ActionError("Window monitor is unavailable")
        cfg = pin_options(self.settings)
        area = usable_rect(monitor, self.settings, cfg["margin"])
        obstacles = widget_rects(self.ctl.query("layers"), monitor)
        size = (round(area[2] * cfg["widthFraction"]), round(area[3] * cfg["heightFraction"]))
        x, y, w, h = place(area, size, cfg["corner"], obstacles)
        try:
            if win.get("fullscreen") or win.get("fullscreenClient"):
                self.dispatch("window.fullscreen_state", key, internal=0, client=0, action="set")
            self.dispatch("window.float", key, action="on")
            self.dispatch("window.resize", key, x=w, y=h, relative=False)
            # Respect client minimum sizes when selecting the final position.
            actual = self.clients().get(key)
            if actual is None:
                raise ActionError("Window closed while pinning")
            x, y, w, h = place(area, actual.get("size", size), cfg["corner"], obstacles)
            self.dispatch("window.move", key, x=x, y=y, relative=False)
            self.dispatch("window.pin", key, action="on")
        except ActionError:
            self.dispatch("window.pin", key, action="off")
            if win.get("floating"):
                self.dispatch("window.resize", key, x=win["size"][0], y=win["size"][1], relative=False)
                self.dispatch("window.move", key, x=win["at"][0], y=win["at"][1], relative=False)
            else:
                self.dispatch("window.float", key, action="off")
            if win.get("fullscreen") or win.get("fullscreenClient"):
                self.dispatch("window.fullscreen_state", key, internal=win.get("fullscreen", 0),
                              client=win.get("fullscreenClient", 0), action="set")
            raise
        return {"action": "pinned", "address": key, "geometry": [x, y, w, h]}


def read_json(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default
    except (OSError, ValueError) as exc:
        raise ActionError("Cannot read " + str(path) + ": " + str(exc)) from exc


@contextlib.contextmanager
def locked_state():
    import fcntl  # Linux only; tests inject a store and transport.
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    if not signature or not runtime:
        raise ActionError("A running Hyprland session is required")
    folder = Path(runtime) / "serpantinum"
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = folder / ("window-actions-" + hashlib.sha256(signature.encode()).hexdigest()[:16] + ".json")
    with path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = read_json(path, {})
        if not isinstance(state, dict):
            raise ActionError("Invalid window action state")

        def save(data):
            tmp = path.with_suffix(".tmp")
            tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
            tmp.replace(path)
        yield state, save


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("float", "pin", "minimize", "restore", "focus", "bind"))
    parser.add_argument("address", nargs="?")
    parser.add_argument("--notify", action="store_true",
                        help="report a failure as a desktop notification (key bindings have no terminal)")
    args = parser.parse_args()
    code, payload = run(args)
    print(json.dumps(payload, ensure_ascii=False))
    if code and args.notify:
        with contextlib.suppress(OSError, subprocess.TimeoutExpired):
            subprocess.run(["notify-send", "-a", "Serpantinum", "-u", "low", "Window action failed",
                            payload.get("error", "")], timeout=5, capture_output=True)
    return code


def run(args):
    try:
        if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
            raise ActionError("A running Hyprland session is required")
        ctl = Hyprctl()
        if args.action == "bind":
            plan, conflicts = bind_plan(ctl.query("binds"))
            for expression in plan:
                ctl.run("eval", expression)
            result = {"action": "bound", "added": len(plan), "conflicts": conflicts}
        else:
            config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "serpantinum/settings.json"
            settings = read_json(config, {})
            with locked_state() as (state, save):
                actions = WindowActions(ctl, state, save, settings)
                if args.action == "float":
                    result = actions.float_toggle()
                elif args.action == "pin":
                    result = actions.pin()
                elif args.action == "minimize":
                    result = actions.minimize(args.address)
                else:
                    result = actions.restore(args.address)
        return 0, {"ok": True, **result}
    except (ActionError, OSError, ValueError) as exc:
        return 1, {"ok": False, "error": str(exc)}


if __name__ == "__main__":
    sys.exit(main())
