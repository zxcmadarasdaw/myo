pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../"

Item {
    id: controller
    readonly property bool onHyprland: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "") !== ""
    readonly property var settings: Config.getSetting("windowActions", {}) || ({})
    readonly property string extraFloatShortcut: typeof settings.extraFloatShortcut === "string" ? settings.extraFloatShortcut : ""
    property bool shortcutPending: false
    property string lastError: ""
    property var queue: []
    property bool initialized: false
    property string output: ""

    function setSetting(key, value) {
        let next = Object.assign({}, settings);
        next[key] = value;
        Config.setSetting("windowActions", next);
    }

    function initialize() {
        if (initialized || !onHyprland) return;
        initialized = true;
        if (Config.dataReady) enqueue("bind", "");
    }

    function enqueue(action, address) {
        if (!onHyprland) return;
        if (action === "bind" && (!Config.dataReady || queue.some(request => request[0] === "bind"))) return;
        queue = queue.concat([[action, address || ""]]);
        startNext();
    }

    function configureFloatShortcut(value) {
        if (!onHyprland || !Config.dataReady || shortcutPending) return;
        shortcutPending = true;
        enqueue("shortcut", value);
    }

    function startNext() {
        if (worker.running || queue.length === 0) return;
        let request = queue[0];
        queue = queue.slice(1);
        output = "";
        let argv = ["python3", Caching.serpantinumDir + "/scripts/system/window_actions.py", request[0]];
        if (request[0] === "bind") argv.push(extraFloatShortcut);
        else if (request[0] === "shortcut") argv.push("--", request[1]);
        else if (request[1] !== "") argv.push(request[1]);
        worker.action = request[0];
        worker.command = argv;
        worker.running = true;
    }

    function pin() { enqueue("pin", ""); }
    function minimize(address) { enqueue("minimize", address); }
    function restore(address) { enqueue("restore", address); }
    function focus(address) { enqueue("focus", address); }

    // Hyprland's workspace fullscreen flag also includes maximized windows.
    function hasExclusiveFullscreen(workspace) {
        let windows = workspace && workspace.toplevels ? workspace.toplevels.values : null;
        return Boolean(windows && windows.some(window => {
            let mode = window.lastIpcObject ? window.lastIpcObject.fullscreen : 0;
            return mode === true || (Number(mode) & 2) !== 0;
        }));
    }

    function refreshFullscreenState() { Hyprland.refreshToplevels(); }

    // Native CSD requests in 0.57.1 are ignored upstream. Foreign-toplevel
    // minimize requests DO emit this event; handle only their exact address.
    function handleEvent(name, data) {
        if (name === "configreloaded") { enqueue("bind", ""); return; }
        if (name === "fullscreen") { Qt.callLater(controller.refreshFullscreenState); return; }
        if (name !== "minimized") return;
        let match = /^(?:0x)?([0-9a-fA-F]{1,16}),([01])$/.exec(String(data));
        if (!match) return;
        if (match[2] === "1") minimize("0x" + match[1]);
        else restore("0x" + match[1]);
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event) controller.handleEvent(event.name, event.data);
        }
    }

    Connections {
        target: Config
        function onDataReadyChanged() {
            if (controller.initialized && Config.dataReady) controller.enqueue("bind", "");
        }
    }

    Process {
        id: worker
        property string action
        running: false
        stdout: StdioCollector { onStreamFinished: controller.output = this.text }
        onExited: (code, status) => {
            try {
                let result = JSON.parse(controller.output.trim());
                controller.lastError = result.ok ? "" : result.error;
                if (result.ok && result.action === "shortcut")
                    controller.setSetting("extraFloatShortcut", result.shortcut);
                if (result.conflicts && result.conflicts.length)
                    controller.lastError = "Shortcut already in use: " + result.conflicts.join(", ");
                if (controller.lastError) console.warn("[windows] " + controller.lastError);
                else console.info("[windows] " + result.action + " " + (result.address || ""));
            } catch (e) {
                controller.lastError = "Window action failed (exit " + code + "): " + controller.output.trim();
                console.warn("[windows] " + controller.lastError);
            }
            if (action === "shortcut") controller.shortcutPending = false;
            Qt.callLater(controller.startNext);
        }
    }

    IpcHandler {
        target: "windows"
        function toggleFloating(): void { controller.enqueue("float", ""); }
        function pin(): void { controller.pin(); }
        function minimize(): void { controller.minimize(""); }
        function restore(): void { controller.restore(""); }
    }
}
