pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// Commands the user typed into a terminal widget's settings on this machine.
//
// A desktop terminal widget runs its start command (or Command Monitor
// command) on its own only when that exact command is listed here. A command
// that reaches a widget any other way — an imported Themess theme, a shared
// widget preset, a hand-edited layout.json — is not in the list, so the widget
// shows it and waits for the user to press "Run" (which then records it).
//
// File: $XDG_STATE_HOME/serpantinum/terminal/trusted.json
//   { "commands": ["fastfetch", "watch -n2 df -h"] }
QtObject {
    id: root

    property var commands: []
    property bool loaded: false

    function isTrusted(cmd) {
        let c = String(cmd || "").trim();
        if (c === "") return true;          // no command: plain interactive shell
        return root.commands.indexOf(c) !== -1;
    }

    function approve(cmd) {
        let c = String(cmd || "").trim();
        if (c === "" || root.commands.indexOf(c) !== -1) return;
        let list = root.commands.slice();
        list.push(c);
        while (list.length > 200) list.shift();
        root.commands = list;
        root.save();
    }

    function save() {
        trustFile.setText(JSON.stringify({ commands: root.commands }, null, 2) + "\n");
    }

    property FileView trustFile: FileView {
        path: Caching.getStateDir("terminal") + "/trusted.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                let raw = typeof text === "function" ? text() : text;
                let obj = JSON.parse(raw || "{}");
                root.commands = Array.isArray(obj.commands) ? obj.commands.filter(c => typeof c === "string") : [];
            } catch (e) {
                root.commands = [];
            }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }
}
