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
        enqueue("bind", "");
    }

    function enqueue(action, address) {
        if (!onHyprland) return;
        queue = queue.concat([[action, address || ""]]);
        startNext();
    }

    function startNext() {
        if (worker.running || queue.length === 0) return;
        let request = queue[0];
        queue = queue.slice(1);
        output = "";
        let argv = ["python3", Caching.serpantinumDir + "/scripts/system/window_actions.py", request[0]];
        if (request[1] !== "") argv.push(request[1]);
        worker.command = argv;
        worker.running = true;
    }

    function pin() { enqueue("pin", ""); }
    function minimize(address) { enqueue("minimize", address); }
    function restore(address) { enqueue("restore", address); }
    function focus(address) { enqueue("focus", address); }

    // Native CSD requests in 0.57.1 are ignored upstream. Foreign-toplevel
    // minimize requests DO emit this event; handle only their exact address.
    function handleEvent(name, data) {
        if (name === "configreloaded") { enqueue("bind", ""); return; }
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

    Process {
        id: worker
        running: false
        stdout: StdioCollector { onStreamFinished: controller.output = this.text }
        onExited: (code, status) => {
            try {
                let result = JSON.parse(controller.output.trim());
                controller.lastError = result.ok ? "" : result.error;
                if (result.conflicts && result.conflicts.length)
                    controller.lastError = "Shortcut already in use: " + result.conflicts.join(", ");
                if (controller.lastError) console.warn("[windows] " + controller.lastError);
                else console.info("[windows] " + result.action + " " + (result.address || ""));
            } catch (e) {
                controller.lastError = "Window action failed (exit " + code + "): " + controller.output.trim();
                console.warn("[windows] " + controller.lastError);
            }
            Qt.callLater(controller.startNext);
        }
    }

    IpcHandler {
        target: "windows"
        function pin(): void { controller.pin(); }
        function minimize(): void { controller.minimize(""); }
        function restore(): void { controller.restore(""); }
    }
}
