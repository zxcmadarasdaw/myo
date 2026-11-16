pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../"

Item {
    id: root
    visible: false

    readonly property bool enabledByUser: Config.dataReady && Config.getSetting("ai.privacy.actionsEnabled", true) === true
    readonly property bool busy: job !== null
    readonly property bool journalLoading: listId !== ""
    property var proposal: null
    property var job: null
    property var undoRecords: ({})
    property var records: []
    property string listId: ""
    property string feedback: ""
    property string feedbackConversation: ""
    property int sequence: 0

    signal navigateRequested(string target, string tab)

    onEnabledByUserChanged: if (!enabledByUser) dismiss("")

    function themeSnapshot() {
        const theme = Config.getSetting("theme", {}) || {};
        let snapshot = {};
        for (const key of ["activePreset", "matugen", "colors"])
            if (Object.prototype.hasOwnProperty.call(theme, key)) snapshot[key] = theme[key];
        return snapshot;
    }

    function workspaceSnapshot() {
        if (Compositor.name !== "hyprland") return null;
        const workspace = Hyprland.focusedWorkspace;
        const monitor = workspace?.monitor?.name;
        return workspace && workspace.id > 0 && monitor ? { id: workspace.id, monitor: monitor } : null;
    }

    function workspaceExists(target, monitor) {
        return (Hyprland.workspaces?.values || []).some(workspace => workspace.id === target && workspace.monitor?.name === monitor);
    }

    function appSnapshot(entry) {
        return entry && !entry.noDisplay ? { id: entry.id, name: entry.name, exec: entry.execString,
            directory: entry.workingDirectory, terminal: entry.runInTerminal } : null;
    }

    function appEntry(target) {
        const entries = (DesktopEntries.applications?.values || []).filter(entry => !entry.noDisplay && !!entry.id);
        const exact = entries.find(entry => entry.id === target);
        if (exact) return exact;
        const matches = entries.filter(entry => entry.name.toLowerCase() === target.toLowerCase());
        return matches.length === 1 ? matches[0] : null;
    }

    function prepare(action, conversationId) {
        if (!enabledByUser || busy || !conversationId || !action || typeof action.id !== "string") return;
        let target = action.target;
        let snapshot = null;
        let label = "";
        switch (action.id) {
        case "open_settings":
        case "open_wallpaper_hub":
        case "show_system_info":
            if (target !== undefined) return;
            break;
        case "set_theme":
            if (!["Dracula", "Mocha", "Nord", "Tokyo"].includes(target)) return;
            snapshot = themeSnapshot();
            label = target;
            break;
        case "switch_workspace":
            snapshot = workspaceSnapshot();
            if (!Number.isInteger(target) || target < 1 || target > 2147483647) return;
            if (!snapshot || !workspaceExists(target, snapshot.monitor)) {
                report(conversationId, "unavailable");
                return;
            }
            label = String(target);
            break;
        case "launch_app": {
            if (typeof target !== "string" || !target.trim() || target.length > 100) return;
            snapshot = appSnapshot(appEntry(target));
            if (!snapshot) {
                report(conversationId, "unavailable");
                return;
            }
            target = snapshot.id;
            label = snapshot.name + " (" + snapshot.id + ")";
            break;
        }
        default:
            return;
        }
        const validated = target === undefined ? { id: action.id } : { id: action.id, target: target };
        offer({ action: validated, label: label, before: snapshot, conversationId: conversationId });
    }

    function offer(item) {
        proposal = Object.assign(item, { token: ++sequence, expires: Date.now() + 120000 });
        feedback = "";
        expiry.restart();
    }

    function dismiss(conversationId) {
        if (proposal && (!conversationId || proposal.conversationId === conversationId)) {
            proposal = null;
            expiry.stop();
        }
    }

    function report(conversationId, code) {
        feedbackConversation = conversationId;
        feedback = code;
    }

    function validNow(item) {
        if (!enabledByUser || Date.now() >= item.expires || item.conversationId !== AiChat.activeId) return false;
        switch (item.action.id) {
        case "set_theme":
            return !Config.isWriting && Config.areEqual(themeSnapshot(), item.before);
        case "switch_workspace": {
            const current = workspaceSnapshot();
            const target = item.undo ? item.restore.id : item.action.target;
            return current && Config.areEqual(current, item.before) && workspaceExists(target, current.monitor);
        }
        case "launch_app":
            return Config.areEqual(appSnapshot(DesktopEntries.byId(item.action.target)), item.before);
        default:
            return true;
        }
    }

    function confirm(token) {
        const item = proposal;
        if (!item || item.token !== token || busy) return false;
        dismiss("");
        if (!validNow(item)) {
            report(item.conversationId, "stale");
            return false;
        }
        job = { item: item, phase: "begin", requestId: AiService.actionLog("begin",
            { action: item.action, undo: !!item.undo }) };
        report(item.conversationId, "running");
        return true;
    }

    function apply(entry, colors) {
        const item = job.item;
        job.entry = entry;
        if (!validNow(item)) {
            finish("stale");
            return;
        }
        switch (item.action.id) {
        case "set_theme": {
            const next = item.undo ? item.restore : { activePreset: item.action.target, matugen: false, colors: colors };
            if (Config.areEqual(item.before, next)) {
                finish(item.undo ? "undone" : "applied");
                return;
            }
            const theme = Config.getSetting("theme", {}) || {};
            for (const key of ["activePreset", "matugen", "colors"]) {
                if (Object.prototype.hasOwnProperty.call(next, key)) theme[key] = next[key];
                else delete theme[key];
            }
            job.phase = "theme";
            job.expected = next;
            verify.restart();
            Config.setSetting("theme", theme);
            break;
        }
        case "switch_workspace": {
            const target = item.undo ? item.restore.id : item.action.target;
            if (target === item.before.id) {
                finish(item.undo ? "undone" : "applied");
                return;
            }
            job.phase = "workspace";
            job.expected = { id: target, monitor: item.before.monitor };
            verify.restart();
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + target + " })");
            break;
        }
        case "launch_app":
            DesktopEntries.byId(item.action.target).execute();
            finish("requested");
            break;
        case "open_settings":
        case "open_wallpaper_hub":
            navigateRequested("guide", item.action.id === "open_settings" ? "general" : "wallpaper_search");
            finish("requested");
            break;
        case "show_system_info":
            navigateRequested("system", "");
            finish("requested");
            break;
        }
    }

    function finish(outcome) {
        verify.stop();
        const item = job.item;
        if (outcome === "applied" && job.expected) {
            undoRecords = Object.assign({}, undoRecords, { [job.entry.recordId]:
                { action: item.action, label: item.label, before: job.expected, restore: item.before } });
        } else if (outcome === "undone" && item.original) {
            const next = Object.assign({}, undoRecords);
            delete next[item.original];
            undoRecords = next;
        }
        const entry = Object.assign({}, job.entry, { outcome: outcome });
        records = [entry].concat(records).slice(0, 80);
        report(item.conversationId, outcome);
        job.phase = "finish";
        job.requestId = AiService.actionLog("finish", { recordId: entry.recordId, outcome: outcome });
    }

    function requestUndo(recordId, conversationId) {
        const saved = undoRecords[recordId];
        if (!enabledByUser || busy || !saved || !conversationId) return;
        const label = saved.action.id === "switch_workspace"
            ? saved.before.id + " → " + saved.restore.id
            : saved.before.activePreset + " → " + (saved.restore.activePreset || I18n.t("guide.ai.action_previous_palette"));
        offer(Object.assign({}, saved, { label: label, original: recordId, undo: true, conversationId: conversationId }));
    }

    function loadJournal() {
        if (!listId) listId = AiService.actionLog("list");
    }

    function receive(event) {
        if (event.event === "started") return;
        if (event.id === listId) {
            listId = "";
            if (event.event === "completed") records = event.entries;
            else report(AiChat.activeId, "log_error");
            return;
        }
        if (!job || job.requestId !== event.id) return;
        if (event.event !== "completed") {
            const code = job.phase === "finish" ? "outcome_unlogged"
                : (event.code === "action_unavailable" ? "unavailable" : "log_error");
            report(job.item.conversationId, code);
            job = null;
        } else if (job.phase === "begin") {
            try { apply(event.entry, event.colors); }
            catch (_) { finish("failed"); }
        } else if (job.phase === "finish") {
            job = null;
        }
    }

    Timer {
        id: expiry
        interval: 120000
        onTriggered: {
            if (root.proposal) root.report(root.proposal.conversationId, "stale");
            root.dismiss("");
        }
    }
    Timer {
        id: verify
        interval: 2200
        onTriggered: if (root.job && (root.job.phase === "workspace" || root.job.phase === "theme")) root.finish("failed")
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (root.job?.phase === "workspace" && Config.areEqual(root.workspaceSnapshot(), root.job.expected))
                root.finish(root.job.item.undo ? "undone" : "applied");
        }
    }
    Connections {
        target: Config
        function onSettingsWriteFinished(success) {
            if (root.job?.phase !== "theme") return;
            const matches = Config.areEqual(root.themeSnapshot(), root.job.expected);
            root.finish(success && matches ? (root.job.item.undo ? "undone" : "applied") : "failed");
            if (!success) Qt.callLater(Config.reloadFromDisk);
        }
    }
    Connections {
        target: AiService
        function onActionEvent(event) { root.receive(event); }
    }
}
