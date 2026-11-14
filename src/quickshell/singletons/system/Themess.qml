pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "../../widgets"
import "../../bar"

Item {
    id: root

    property string folder: ""
    property var result: ({})
    property var packages: []
    property var active: null
    property bool canRestoreOriginal: false
    readonly property string operation: task.action
    property bool canRestore: false
    property string message: ""
    property var errors: []
    property bool busy: false
    property bool widgetEditorOpen: false
    readonly property bool writingStores: busy && changesDesktop(task.action)
    signal storesChanged()

    function selectFolder(path) {
        if (busy || folder === path) return;
        folder = path;
        result = {};
        errors = [];
        message = "";
    }

    function localPath(url) {
        const value = String(url);
        if (!value.startsWith("file:///")) return "";
        const path = decodeURIComponent(value.slice(7));
        return /^\/[A-Za-z]:\//.test(path) ? path.slice(1) : path;
    }

    function changesDesktop(action) {
        return action === "apply" || action === "restore" || action === "restore-original";
    }

    function packageAt(path) {
        return packages.find(item => item.folder === path) || null;
    }

    function capabilities(screen) {
        const modules = ["palette", "materials", "panels", "dock", "launcher", "notifications", "vpn",
                         "fastfetch", "fastfetchMedia", "studio"];
        const outputs = Array.from(Quickshell.screens, item => item.name);
        const wallpaperOutputs = outputs.filter(name => !!Wallpaper.engines[name]);
        const widgetScreen = outputs.includes(screen) ? screen : (outputs[0] || "");
        const widgets = {};
        if (!Config.getSetting("general.performance", false) && widgetScreen) {
            modules.push("widgets");
            if (typeof CanvasState !== "undefined" && CanvasState.cameraFor(widgetScreen)) modules.push("canvas");
            for (const widget of WidgetRegistry.typeList()) {
                widgets[widget.id] = WidgetRegistry.variantList(widget.id).map(variant => variant.id);
            }
        }
        if (wallpaperOutputs.length) modules.push("wallpaper", "animations");
        const styles = id => BarModuleRegistry.variantList(id).map(variant => variant.id);
        return {
            modules: modules,
            widgetScreen: widgetScreen,
            wallpaperScreens: wallpaperOutputs,
            widgetTypes: widgets,
            barModules: BarModuleRegistry.moduleIds(),
            barMenu: BarModuleRegistry.menuItemIds,
            workspacesStyles: styles("workspaces"),
            timeStyles: styles("timedate")
        };
    }

    function run(action, screen, path, token, expectedPackage, keepMessage) {
        if (busy) return false;
        errors = [];
        if (!keepMessage) message = "";
        if ((changesDesktop(action) || expectedPackage) &&
                (!Config.dataReady || Config.isWriting || widgetEditorOpen)) {
            errors = [I18n.t("guide.themess.pending", "Close the widget editor and wait for settings to finish saving.")];
            return false;
        }
        task.action = action;
        task.screen = screen || "";
        task.expectedPackage = expectedPackage || "";
        task.command = ["python3", Caching.serpantinumDir + "/scripts/themess/themess.py", action,
                        "--folder", path || folder, "--token", token || "",
                        "--caps", JSON.stringify(capabilities(task.screen))];
        busy = true;
        startTimeout.restart();
        task.running = true;
        return true;
    }

    function requestApply(item, screen) {
        pendingApply = null;
        selectFolder(item.folder);
        run("scan", screen, item.folder, "", item.packageToken);
    }

    // Set when Apply would replace widgets that are on the screen now. Nothing is written
    // until confirmApply(); the replaced layout is kept for Restore Previous either way.
    property var pendingApply: null

    function confirmApply() {
        const pending = pendingApply;
        if (!pending || busy) return;
        pendingApply = null;
        run("apply", pending.screen, pending.folder, pending.token);
    }

    function cancelApply() {
        pendingApply = null;
        message = I18n.t("guide.themess.apply_cancelled", "Apply cancelled. Nothing was changed.");
    }

    function receive() {
        startTimeout.stop();
        const action = task.action;
        const screen = task.screen;
        if (changesDesktop(action)) {
            Config.reloadFromDisk();
            root.storesChanged();
        }
        let response;
        try {
            response = JSON.parse(output.text);
        } catch (error) {
            errors = [diagnostic.text.trim() || I18n.t("guide.themess.failed", "Themess could not start or returned an invalid response.")];
            busy = false;
            return;
        }
        if (response.packages !== undefined) {
            packages = response.packages;
            result = {};
        }
        if (response.active !== undefined) active = response.active;
        if (response.canRestore !== undefined) canRestore = response.canRestore;
        if (response.canRestoreOriginal !== undefined) canRestoreOriginal = response.canRestoreOriginal;
        if (response.components !== undefined) result = response;
        if (response.message) message = response.message;
        errors = response.errors || [];
        busy = false;
        if (errors.length) return;
        if (action === "scan" && task.expectedPackage) {
            if (task.expectedPackage !== response.packageToken) {
                errors = [I18n.t("guide.themess.changed", "Package or compatibility changed. Refresh the library and review it again.")];
                result = {};
                return;
            }
            if (response.widgetCount !== null && response.widgetCount !== undefined && response.widgetsBefore > 0) {
                pendingApply = {folder: response.folder, token: response.token, screen: screen, name: response.name,
                                widgetsBefore: response.widgetsBefore, widgetCount: response.widgetCount,
                                widgetScreen: response.widgetScreen};
                return;
            }
            run("apply", screen, response.folder, response.token);
        } else if (action === "import" || action === "remove") {
            folder = response.selection || "";
            result = {};
            run("catalog", screen, "", "", "", true);
        } else if (changesDesktop(action)) {
            result = {};
        }
    }

    Timer {
        id: startTimeout
        interval: 3000
        onTriggered: {
            root.errors = [I18n.t("guide.themess.failed", "Themess could not start or returned an invalid response.")];
            root.busy = false;
        }
    }

    Process {
        id: task
        property string action: ""
        property string screen: ""
        property string expectedPackage: ""
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: diagnostic }
        onExited: Qt.callLater(root.receive)
        onStarted: startTimeout.stop()
    }
}
