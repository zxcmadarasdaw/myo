pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// Process Explorer: open/close state, settings and the hotkey.
//
// Opened with `serpantinum msg toggle processes` (Super+Shift+P by default,
// see compositors/hyprland/config/keybinds.lua). The panel itself exists
// only while it is open (or animating closed), so it never holds keyboard
// focus or runs its sampler in the background.
//
// Settings (settings.json, section "processExplorer"):
//   hotkey    "SUPER + SHIFT + P"   (Hyprland key combo)
//   material  "standard" | "liquid" | "mica" | "neon"
//   interval  seconds between samples (0.5 .. 10)
ScreenToggleController {
    id: controller

    // true while the close animation still runs
    property bool lingering: false
    readonly property bool loaded: controller.isVisible || controller.lingering

    readonly property string defaultHotkey: "SUPER + SHIFT + P"
    readonly property var settings: (typeof Config !== "undefined" && Config.getSetting) ? (Config.getSetting("processExplorer", {}) || {}) : {}
    readonly property string hotkey: validHotkey(settings.hotkey) ? normalizeHotkey(settings.hotkey) : defaultHotkey
    readonly property string material: ["standard", "liquid", "mica", "neon"].indexOf(settings.material) !== -1 ? settings.material : "standard"
    readonly property real interval: {
        let v = Number(settings.interval);
        return isNaN(v) ? 2 : Math.max(0.5, Math.min(10, v));
    }

    // Letters, digits, underscores and "+" only: the combo ends up inside a
    // Lua string for `hyprctl eval`, so nothing that could close the string.
    function validHotkey(k) {
        if (typeof k !== "string") return false;
        let s = k.trim();
        return s.length > 0 && s.length <= 64 && /^[A-Za-z0-9_]+(\s*\+\s*[A-Za-z0-9_]+)*$/.test(s);
    }

    function normalizeHotkey(k) {
        const mods = ["super", "shift", "ctrl", "control", "alt", "mod4"];
        return String(k).trim().split("+").map(p => p.trim()).filter(p => p !== "")
            .map(p => mods.indexOf(p.toLowerCase()) !== -1 ? p.toUpperCase() : p).join(" + ");
    }

    function setSetting(key, value) {
        let cur = Object.assign({}, Config.getSetting("processExplorer", {}) || {});
        cur[key] = value;
        Config.setSetting("processExplorer", cur);
    }

    // ---- hotkey (Hyprland) -------------------------------------------------
    // New installs bind the default combo in keybinds.lua. Updates never
    // overwrite the user's compositor files, so at shell start the running
    // Hyprland is asked (`hyprctl binds -j`) whether anything already opens
    // the Process Explorer; if not, the configured combo is bound at runtime.
    // A different combo chosen in Settings is applied with `hyprctl eval`
    // whenever it changes. The user's Hyprland files are never edited.
    property string appliedHotkey: defaultHotkey
    property bool bindsChecked: false
    readonly property bool onHyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") !== ""

    function ensureBound() {
        if (!onHyprland || controller.bindsChecked || bindProbe.running) return;
        bindProbe.running = true;
    }

    // true when some bind in `hyprctl binds -j` output runs "msg toggle processes"
    function hasProcessesBind(json) {
        try {
            let list = JSON.parse(json);
            return Array.isArray(list) && list.some(b => b && String(b.arg || "").indexOf("msg toggle processes") !== -1);
        } catch (e) {
            return false;
        }
    }

    Process {
        id: bindProbe
        running: false
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                controller.bindsChecked = true;
                if (controller.hasProcessesBind(this.text)) {
                    controller.appliedHotkey = controller.defaultHotkey;   // keybinds.lua
                    controller.applyHotkey();
                } else if (controller.validHotkey(controller.hotkey)) {
                    Quickshell.execDetached(["hyprctl", "eval", controller.bindLua(controller.hotkey)]);
                    controller.appliedHotkey = controller.hotkey;
                }
            }
        }
    }

    function bindLua(combo) {
        return 'hl.bind("' + combo + '", hl.dsp.exec_cmd("serpantinum msg toggle processes"))';
    }

    function unbindLua(combo) {
        return 'pcall(function() if hl.unbind then hl.unbind("' + combo + '") end end)';
    }

    function applyHotkey() {
        if (!onHyprland) return;
        if (!controller.bindsChecked) { ensureBound(); return; }
        let want = controller.hotkey;
        if (want === controller.appliedHotkey) return;
        if (!validHotkey(want) || !validHotkey(controller.appliedHotkey)) return;
        let lua = unbindLua(controller.appliedHotkey) + "; " + bindLua(want);
        Quickshell.execDetached(["hyprctl", "eval", lua]);
        controller.appliedHotkey = want;
    }

    onHotkeyChanged: if (typeof Config !== "undefined" && Config.dataReady) applyHotkey()

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        ignoreUnknownSignals: true
        function onDataReadyChanged() { if (Config.dataReady) controller.applyHotkey(); }
        function onSettingsLoaded() { controller.applyHotkey(); }
    }
}
