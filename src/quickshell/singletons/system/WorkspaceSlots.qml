pragma Singleton
import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "../../"

Item {
    id: root

    readonly property var settings: Config.rawSettings || ({})
    readonly property int count: {
        const configured = Number(settings.bar?.workspaceCount ?? settings.general?.workspaceCount ?? settings.workspaceCount ?? 8);
        return Number.isFinite(configured) ? Math.max(2, Math.min(10, Math.floor(configured))) : 8;
    }
    readonly property var monitorRanges: {
        let ranges = Object.create(null);
        const config = settings.bar?.workspaces;
        if (!config || config.perMonitorNumbering !== true) return ranges;
        for (const [output, range] of Object.entries(config.monitors || {})) {
            const first = Number(range?.first);
            const size = Number(range?.count);
            if (!output || /[\x00-\x1f\x7f]/.test(output) || !Number.isInteger(first) || first < 1
                    || !Number.isInteger(size) || size < 1 || size > 100 || first + size - 1 > 2147483647) continue;
            ranges[output] = { first: first, count: size };
        }
        return ranges;
    }
    readonly property string luaConfig: {
        const rows = Object.entries(monitorRanges).map(([name, range]) =>
            "[" + JSON.stringify(name) + "] = { first = " + range.first + ", count = " + range.count + " }");
        return "_G.serpantinumWorkspaceSlots = { count = " + count + ", monitors = { " + rows.join(", ") + " } }";
    }

    property bool pending: false

    function sync() {
        if (!Config.dataReady || Compositor.name !== "hyprland") return;
        pending = true;
        Qt.callLater(root.send);
    }

    function send() {
        if (!pending || worker.running) return;
        pending = false;
        worker.command = ["timeout", "5s", "hyprctl", "eval", luaConfig];
        worker.running = true;
    }

    onLuaConfigChanged: sync()
    Component.onCompleted: sync()

    Connections {
        target: Config
        function onDataReadyChanged() { root.sync(); }
    }

    Connections {
        target: Hyprland
        enabled: Compositor.name === "hyprland"
        function onRawEvent(event) {
            if (event && event.name === "configreloaded") root.sync();
        }
    }

    Process {
        id: worker
        onExited: Qt.callLater(root.send)
    }
}
