// Adapted from Serpantinum 2cce8546. Copyright 2026 Illia Miroshnichenko and contributors.
// AGPL-3.0-or-later. UI dispatch uses the validated current action syntax.
pragma Singleton
import QtQuick
import Quickshell
import "../../"

CompositorStateBase {
    id: root

    property var countByOutput: ({})
    property int workspaceCount: 0
    property var occupiedByOutput: ({})
    property string focusedOutput: ""
    property int workspaceSubscribers: 0

    watching: Compositor.name === "umbriel" && workspaceSubscribers > 0

    function subscribe() {
        workspaceSubscribers++;
    }

    function unsubscribe() {
        workspaceSubscribers = Math.max(0, workspaceSubscribers - 1);
    }

    function isOccupied(outputName, index) {
        let perOutput = (outputName && occupiedByOutput) ? occupiedByOutput[outputName] : null;
        if (perOutput) return Boolean(perOutput[index]);
        return Boolean(occupiedMap[index]);
    }

    function countFor(outputName) {
        let count = (outputName && countByOutput) ? countByOutput[outputName] : undefined;
        return count !== undefined ? count : workspaceCount;
    }

    function dispatch(action, args) {
        Quickshell.execDetached(["umbriel", "msg", action].concat(args || []));
    }

    onCoreState: state => {
        let ws = state.workspaces || {};
        root.applyWorkspaces(ws);
        root.assign("occupiedByOutput", ws.occupiedByOutput || {});
        root.assign("countByOutput", ws.countByOutput || {});
        if (ws.workspaceCount !== undefined && root.workspaceCount !== ws.workspaceCount) root.workspaceCount = ws.workspaceCount;
        let focused = ws.focusedOutput || "";
        if (root.focusedOutput !== focused) root.focusedOutput = focused;
    }
}
