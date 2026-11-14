import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../"
import "../reusables"
import "faces"
import "canvas"
import "canvas/CanvasMath.js" as CM

Scope {
    id: root

    property bool isActive: false
    onIsActiveChanged: {
        Themess.widgetEditorOpen = isActive;
        syncEditMonitor();
    }
    // Own the edit lease here, not in an asynchronous layout-file callback.
    property string editingMonitor: ""
    function syncEditMonitor() {
        let win = redactorWindowLoader.item;
        let next = root.isActive && win ? win.safeMonitorName : "";
        if (next === editingMonitor) return;
        if (editingMonitor !== "") WidgetSync.setRedactMode(editingMonitor, false);
        editingMonitor = next;
        if (next !== "") WidgetSync.setRedactMode(next, true);
        console.info("[input] editor monitor=" + next + " active=" + root.isActive);
    }
    property string targetMonitorName: ""
    property string targetSelectedWidgetId: ""
    readonly property var activeWidgetsModel: (redactorWindowLoader.item && redactorWindowLoader.item.activeWidgetsModel) ? redactorWindowLoader.item.activeWidgetsModel : null

    function open(mon, widgetId) {
        if (Themess.writingStores) return;
        root.targetMonitorName = (mon && typeof mon === "string") ? mon.trim() : "";
        root.targetSelectedWidgetId = (widgetId && typeof widgetId === "string") ? widgetId.trim() : "";

        if (redactorWindowLoader.item) {
            let win = redactorWindowLoader.item;
            if (root.targetMonitorName !== "" && win.monitorName !== root.targetMonitorName) {
                win.monitorName = root.targetMonitorName;
            }
            if (win.redactorMode) {
                win.redactorMode.selectedId = root.targetSelectedWidgetId;
            }
        }

        root.isActive = true;

        if (Caching.runDir) {
            Quickshell.execDetached(["bash", "-c", "rm -f '" + Caching.runDir + "/redactor_selected_widget' '" + Caching.runDir + "/redactor_target_monitor'"]);
        }
    }

    function close() {
        if (!root.isActive && editingMonitor === "" && targetMonitorName === "" && targetSelectedWidgetId === "") return;
        // Release the original monitor before clearing targetMonitorName;
        // that property participates in the window's monitor binding.
        root.isActive = false;
        syncEditMonitor();
        if (redactorWindowLoader.item && redactorWindowLoader.item.redactorMode) {
            redactorWindowLoader.item.redactorMode.selectedId = "";
        }
        root.targetSelectedWidgetId = "";
        root.targetMonitorName = "";

        if (Caching.runDir) {
            Quickshell.execDetached(["bash", "-c", "rm -f '" + Caching.runDir + "/redactor_selected_widget' '" + Caching.runDir + "/redactor_target_monitor'"]);
        }
    }

    function toggle(mon, widgetId) {
        if (root.isActive) {
            root.close();
        } else {
            root.open(mon, widgetId);
        }
    }

    IpcHandler {
        target: "redactor"

        function activate(): void {
            root.open("", "");
        }

        function open(mon: string, widgetId: string): void {
            root.open(mon, widgetId);
        }

        function toggle(): void {
            root.toggle("", "");
        }

        function close(): void {
            root.close();
        }
    }

    IpcHandler {
        target: "widget-redactor"

        function activate(): void {
            root.open("", "");
        }

        function open(mon: string, widgetId: string): void {
            root.open(mon, widgetId);
        }

        function toggle(): void {
            root.toggle("", "");
        }

        function close(): void {
            root.close();
        }
    }

    Loader {
        id: redactorWindowLoader
        active: root.isActive
        onLoaded: root.syncEditMonitor()

        sourceComponent: Component {
            PanelWindow {
                id: redactorWindow
                color: "transparent"

                property alias redactorMode: redactorMode
                property alias activeWidgetsModel: redactorMode.activeWidgetsModel

                property string monitorName: {
                    if (root.targetMonitorName && root.targetMonitorName !== "") {
                        return root.targetMonitorName;
                    }
                    let envMon = Quickshell.env("QS_WIDGET_MONITOR");
                    if (envMon && envMon.trim() !== "") return envMon.trim();
                    return (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
                }

                property var targetScreen: {
                    let scr = Quickshell.screens.find(s => s.name === redactorWindow.monitorName);
                    return scr || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
                }
                readonly property string safeMonitorName: (monitorName || (targetScreen ? targetScreen.name : "default")).replace(/[^a-zA-Z0-9_-]/g, "_")
                onSafeMonitorNameChanged: root.syncEditMonitor()
                screen: redactorWindow.targetScreen

                WlrLayershell.namespace: "qs-widget-redactor-" + redactorWindow.safeMonitorName
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: root.isActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

                exclusionMode: ExclusionMode.Ignore
                visible: root.isActive

                anchors.top: true
                anchors.left: true
                anchors.right: true
                anchors.bottom: true

                margins.left: 0
                margins.top: 0

                function s(val) { return Scaler.s(val); }

                function exitRedactor() {
                    root.close();
                }

                Shortcut {
                    sequence: "Escape"
                    onActivated: {
                        if (toolbar.dismiss()) return;
                        if (canvasPanel.dismiss()) return;
                        redactorMode.selectedId = "";
                        redactorWindow.exitRedactor();
                    }
                }

                Shortcut {
                    sequence: "Ctrl+Z"
                    onActivated: redactorMode.undo()
                }

                Shortcut {
                    sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]
                    onActivated: redactorMode.redo()
                }

                // ---- infinite canvas ----
                Shortcut {
                    sequence: "Home"
                    enabled: redactorMode.canvasOn && !canvasPanel.inputActive
                    onActivated: redactorMode.cam.home()
                }

                Shortcut {
                    sequence: "Shift+Home"
                    enabled: redactorMode.canvasOn && !canvasPanel.inputActive
                    onActivated: redactorMode.fitAll()
                }

                Shortcut {
                    sequence: "Ctrl+0"
                    enabled: redactorMode.canvasOn
                    onActivated: redactorMode.cam.resetZoom()
                }

                Shortcut {
                    sequences: ["Ctrl+=", "Ctrl++"]
                    enabled: redactorMode.canvasOn
                    onActivated: redactorMode.cam.zoomBy(redactorMode.canvasCfg.zoomStep)
                }

                Shortcut {
                    sequence: "Ctrl+-"
                    enabled: redactorMode.canvasOn
                    onActivated: redactorMode.cam.zoomBy(1 / redactorMode.canvasCfg.zoomStep)
                }

                Shortcut {
                    sequence: "Ctrl+F"
                    onActivated: canvasPanel.focusSearch()
                }

                Shortcut {
                    sequence: "Ctrl+A"
                    enabled: !canvasPanel.inputActive
                    onActivated: redactorMode.selectAll()
                }

                Shortcut {
                    sequence: "Ctrl+G"
                    onActivated: redactorMode.groupSelection()
                }

                Shortcut {
                    sequence: "Ctrl+Shift+G"
                    onActivated: redactorMode.ungroupSelection()
                }

                Shortcut {
                    sequence: "Delete"
                    enabled: redactorMode.canNudge
                    onActivated: redactorMode.removeSelection()
                }

                Shortcut {
                    sequence: "Left"
                    enabled: redactorMode.canPanKeys
                    onActivated: redactorMode.cam.panBy(redactorMode.panKeyStep, 0)
                }

                Shortcut {
                    sequence: "Right"
                    enabled: redactorMode.canPanKeys
                    onActivated: redactorMode.cam.panBy(-redactorMode.panKeyStep, 0)
                }

                Shortcut {
                    sequence: "Up"
                    enabled: redactorMode.canPanKeys
                    onActivated: redactorMode.cam.panBy(0, redactorMode.panKeyStep)
                }

                Shortcut {
                    sequence: "Down"
                    enabled: redactorMode.canPanKeys
                    onActivated: redactorMode.cam.panBy(0, -redactorMode.panKeyStep)
                }

                Shortcut {
                    sequence: "Left"
                    enabled: redactorMode.canNudge
                    onActivated: redactorMode.nudgeSelected(-1, 0, false)
                }

                Shortcut {
                    sequence: "Right"
                    enabled: redactorMode.canNudge
                    onActivated: redactorMode.nudgeSelected(1, 0, false)
                }

                Shortcut {
                    sequence: "Up"
                    enabled: redactorMode.canNudge
                    onActivated: redactorMode.nudgeSelected(0, -1, false)
                }

                Shortcut {
                    sequence: "Down"
                    enabled: redactorMode.canNudge
                    onActivated: redactorMode.nudgeSelected(0, 1, false)
                }

                Shortcut {
                    sequence: "Shift+Left"
                    enabled: redactorMode.canNudge
                    onActivated: redactorMode.nudgeSelected(-1, 0, true)
                }

                Shortcut {
                    sequence: "Shift+Right"
                    enabled: redactorMode.canNudge
                    onActivated: redactorMode.nudgeSelected(1, 0, true)
                }

                Shortcut {
                    sequence: "Shift+Up"
                    enabled: redactorMode.canNudge
                    onActivated: redactorMode.nudgeSelected(0, -1, true)
                }

                Shortcut {
                    sequence: "Shift+Down"
                    enabled: redactorMode.canNudge
                    onActivated: redactorMode.nudgeSelected(0, 1, true)
                }

                Item {
                    id: redactorMode
                    anchors.fill: parent

                    ListModel {
                        id: activeWidgetsModel
                        dynamicRoles: true
                        onCountChanged: redactorMode.updateToolbarObscured()
                    }

                    property alias activeWidgetsModel: activeWidgetsModel

                    property string selectedId: root.targetSelectedWidgetId
                    property bool gridEnabled: false
                    property var guideLines: []
                    property var measureLines: []

                    // ---- infinite canvas ----
                    // Widget coordinates in the model are world coordinates. workspaceArea is
                    // moved and scaled by the camera, so everything inside it keeps working in
                    // world units; only clamping to the screen edges depends on canvasOn.
                    readonly property var cam: CanvasState.cameraFor(redactorWindow.safeMonitorName)
                    readonly property bool canvasOn: cam !== null && cam.active
                    readonly property real viewX: cam ? cam.viewX : 0
                    readonly property real viewY: cam ? cam.viewY : 0
                    readonly property real viewZoom: cam ? cam.viewZoom : 1
                    readonly property real viewW: width / viewZoom
                    readonly property real viewH: height / viewZoom
                    readonly property var canvasCfg: CanvasState.effective(redactorWindow.safeMonitorName)
                    readonly property real gridStep: canvasOn ? canvasCfg.gridSize : s(20)
                    readonly property bool snapGuidesEnabled: !canvasOn || canvasCfg.snapToGuides
                    // "No guide line" marker. World coordinates can be negative, so -1 no longer works.
                    readonly property real noLine: -1e12
                    readonly property real panKeyStep: s(80)
                    readonly property bool canPanKeys: canvasOn && selectedId === "" && !toolbar.panelOpen && !canvasPanel.inputActive && !(imagePickerLoader.item && imagePickerLoader.item.visible)

                    // Selection: selectedId is the primary widget (it owns the handles and the
                    // settings chrome), multiIds are the other selected widgets.
                    property var multiIds: []
                    property bool keepMulti: false
                    readonly property var selectionIdList: selectedId === "" ? [] : [String(selectedId)].concat(multiIds)
                    // Widgets that move together with the dragged one; they must not act as snap targets.
                    property var dragExcluded: ({})
                    // Rubber band in screen coordinates, null when idle.
                    property var marquee: null
                    // Plain copy of the model for the minimap, search and group logic.
                    property var canvasWidgets: []
                    readonly property bool selectionGrouped: {
                        let ids = selectionIdList;
                        for (let i = 0; i < canvasWidgets.length; i++) {
                            if (canvasWidgets[i].wGroup && ids.indexOf(String(canvasWidgets[i].wId)) >= 0) return true;
                        }
                        return false;
                    }

                    onViewXChanged: queueUpdateToolbarObscured()
                    onViewYChanged: queueUpdateToolbarObscured()
                    onViewZoomChanged: queueUpdateToolbarObscured()

                    readonly property real snapThreshold: s(12) / viewZoom
                    readonly property bool showDistances: !(typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings.widgets && Config.rawSettings.widgets.showDistances === false)
                    property string nudgeTargetId: ""
                    readonly property bool canNudge: selectedId !== "" && !toolbar.panelOpen && !canvasPanel.inputActive && !(imagePickerLoader.item && imagePickerLoader.item.visible)
                    property bool toolbarObscured: false
                    property bool isReady: false
                    property bool isInitializing: true
                    property int topZ: 1

                    readonly property var selectedWidget: {
                        if (!selectedId) return null;
                        for (let i = 0; i < widgetRepeater.count; i++) {
                            let p = widgetRepeater.itemAt(i);
                            if (p && String(p.wId) === String(selectedId)) {
                                return (p.preview && p.preview.item) ? p.preview.item : p;
                            }
                        }
                        return null;
                    }

                    readonly property var currentWidget: selectedWidget
                    readonly property var activeWidget: selectedWidget

                    onSelectedIdChanged: {
                        // Selecting a widget selects its whole group; setSelection() sets
                        // keepMulti while it manages multiIds itself.
                        if (!keepMulti) multiIds = selectedId === "" ? [] : groupMates(selectedId);
                        updateToolbarObscured();
                    }
                    onWidthChanged: updateToolbarObscured()
                    onHeightChanged: updateToolbarObscured()

                    Connections {
                        target: root
                        function onTargetSelectedWidgetIdChanged() {
                            redactorMode.selectedId = root.targetSelectedWidgetId;
                        }
                    }

                    property real safeMinX: 0
                    property real safeMinY: 0
                    property real safeWidth: redactorMode.width
                    property real safeHeight: redactorMode.height

                    Connections {
                        target: WidgetSync
                        ignoreUnknownSignals: true

                        function onPresetApplied(monitor, widgetsList) {
                            if (String(monitor).replace(/[^a-zA-Z0-9_-]/g, "_") !== redactorWindow.safeMonitorName) return;
                            redactorMode.loadLayoutFromText(JSON.stringify(widgetsList));
                        }

                        function onPositionChanged(monitor, widgetId, x, y) {
                            if (monitor !== redactorWindow.safeMonitorName) return;
                            let target = String(widgetId).trim();
                            for (let i = 0; i < activeWidgetsModel.count; i++) {
                                let item = activeWidgetsModel.get(i);
                                if (String(item.wId).trim() === target) {
                                    activeWidgetsModel.setProperty(i, "wX", x);
                                    activeWidgetsModel.setProperty(i, "wY", y);
                                    redactorMode.queueUpdateToolbarObscured();
                                    break;
                                }
                            }
                        }

                        function onPropertyChanged(monitor, widgetId, propName, val) {
                            if (monitor && monitor !== redactorWindow.safeMonitorName) return;
                            let target = String(widgetId).trim();
                            for (let i = 0; i < activeWidgetsModel.count; i++) {
                                let item = activeWidgetsModel.get(i);
                                if (String(item.wId).trim() === target) {
                                    activeWidgetsModel.setProperty(i, propName, val);
                                    let proxy = widgetRepeater.itemAt(i);
                                    if (proxy && proxy.preview && proxy.preview.item) {
                                        try {
                                            if (proxy.preview.item[propName] !== undefined) {
                                                proxy.preview.item[propName] = val;
                                            }
                                        } catch (e) {}
                                    }
                                    break;
                                }
                            }
                        }
                    }

                    Timer {
                        id: toolbarCheckTimer
                        interval: 100
                        repeat: false
                        onTriggered: redactorMode.updateToolbarObscured()
                    }

                    function queueUpdateToolbarObscured() {
                        toolbarCheckTimer.restart();
                    }

                    function removeWidget(widgetId) {
                        let rmId = String(widgetId);
                        if (!rmId) return;
                        if (redactorMode.multiIds.indexOf(rmId) >= 0) {
                            redactorMode.multiIds = redactorMode.multiIds.filter(id => id !== rmId);
                        }
                        if (redactorMode.selectedId === rmId) {
                            redactorMode.selectedId = "";
                            root.targetSelectedWidgetId = "";
                        }
                        WidgetSync.removeWidget(redactorWindow.safeMonitorName, rmId);
                        if (activeWidgetsModel) {
                            for (let i = activeWidgetsModel.count - 1; i >= 0; i--) {
                                if (String(activeWidgetsModel.get(i).wId) === rmId) {
                                    activeWidgetsModel.remove(i, 1);
                                }
                            }
                            if (activeWidgetsModel.count === 0) {
                                redactorMode.selectedId = "";
                                root.targetSelectedWidgetId = "";
                            }
                        }
                        redactorMode.updateToolbarObscured();
                    }

                    function removeAllWidgets() {
                        redactorMode.selectedId = "";
                        root.targetSelectedWidgetId = "";
                        activeWidgetsModel.clear();
                        WidgetSync.clearWidgets(redactorWindow.safeMonitorName);
                        redactorMode.updateToolbarObscured();
                    }

                    function updateToolbarObscured() {
                        if (!activeWidgetsModel || activeWidgetsModel.count === 0) {
                            toolbarObscured = false;
                            return;
                        }

                        let margin = s(50);
                        let tbW = toolbar.width;
                        let tbH = toolbar.height;
                        let tbX = (redactorMode.width - tbW) / 2;
                        let tbY = toolbar.y;

                        let zX1 = tbX - margin;
                        let zX2 = tbX + tbW + margin;
                        let zY1 = tbY - margin;
                        let zY2 = redactorMode.height;

                        let obscured = false;
                        let repCount = widgetRepeater.count;

                        if (repCount > 0) {
                            for (let i = 0; i < repCount; i++) {
                                let proxy = widgetRepeater.itemAt(i);
                                if (!proxy) continue;

                                let isSel = (redactorMode.selectedId === proxy.wId);
                                let gap = isSel ? s(20) : 0;
                                let chromeH = isSel ? s(90) : 0;

                                let pz = redactorMode.viewZoom;
                                let psx = (proxy.x - redactorMode.viewX) * pz;
                                let psy = (proxy.y - redactorMode.viewY) * pz;
                                let wX1 = psx - gap;
                                let wY1 = psy - gap;
                                let wX2 = psx + proxy.width * pz + gap;
                                let wY2 = psy + proxy.height * pz + gap + chromeH;

                                if (wX1 < zX2 && wX2 > zX1 && wY1 < zY2 && wY2 > zY1) {
                                    obscured = true;
                                    break;
                                }
                            }
                        } else {
                            for (let i = 0; i < activeWidgetsModel.count; i++) {
                                let item = activeWidgetsModel.get(i);
                                if (!item) continue;
                                let rot = (item.wRotation !== undefined && !isNaN(item.wRotation)) ? Math.abs(Math.round(item.wRotation)) : 0;
                                let bw = (rot % 180 === 0) ? item.wWidth : item.wHeight;
                                let bh = (rot % 180 === 0) ? item.wHeight : item.wWidth;
                                let isSel = (redactorMode.selectedId === item.wId);
                                let gap = isSel ? s(20) : 0;
                                let chromeH = isSel ? s(90) : 0;

                                let iz = redactorMode.viewZoom;
                                let isx = (item.wX - redactorMode.viewX) * iz;
                                let isy = (item.wY - redactorMode.viewY) * iz;
                                let wX1 = isx - gap;
                                let wY1 = isy - gap;
                                let wX2 = isx + bw * iz + gap;
                                let wY2 = isy + bh * iz + gap + chromeH;

                                if (wX1 < zX2 && wX2 > zX1 && wY1 < zY2 && wY2 > zY1) {
                                    obscured = true;
                                    break;
                                }
                            }
                        }
                        toolbarObscured = obscured;
                    }

                    function getConstraints(loaderItem) {
                        if (!loaderItem) return null;
                        return {
                            minW: loaderItem.minWidth !== undefined ? loaderItem.minWidth : 10,
                            minH: loaderItem.minHeight !== undefined ? loaderItem.minHeight : 10,
                            maxW: loaderItem.maxWidth !== undefined ? loaderItem.maxWidth : 9999,
                            maxH: loaderItem.maxHeight !== undefined ? loaderItem.maxHeight : 9999,
                            minA: loaderItem.minAspect !== undefined ? loaderItem.minAspect : 0,
                            maxA: loaderItem.maxAspect !== undefined ? loaderItem.maxAspect : 9999
                        };
                    }

                    function clampResize(loaderItem, rawW, rawH, dx, dy, isCorner) {
                        let c = getConstraints(loaderItem);
                        if (!c) return { w: rawW, h: rawH };

                        let w = Math.max(c.minW, Math.min(c.maxW, rawW));
                        let h = Math.max(c.minH, Math.min(c.maxH, rawH));

                        let hasMinA = c.minA !== undefined && c.minA > 0;
                        let hasMaxA = c.maxA !== undefined && c.maxA > 0 && c.maxA < 9999;

                        if (!isCorner) {
                            if (dx !== 0) {
                                let effMinW = Math.max(c.minW, hasMinA ? h * c.minA : c.minW);
                                let effMaxW = Math.min(c.maxW, hasMaxA ? h * c.maxA : c.maxW);
                                if (effMinW <= effMaxW) {
                                    w = Math.max(effMinW, Math.min(effMaxW, w));
                                } else {
                                    w = Math.max(c.minW, Math.min(c.maxW, w));
                                }
                            } else {
                                let effMinH = Math.max(c.minH, hasMaxA ? w / c.maxA : c.minH);
                                let effMaxH = Math.min(c.maxH, hasMinA ? w / c.minA : c.maxH);
                                if (effMinH <= effMaxH) {
                                    h = Math.max(effMinH, Math.min(effMaxH, h));
                                } else {
                                    h = Math.max(c.minH, Math.min(c.maxH, h));
                                }
                            }
                            return { w: w, h: h };
                        }

                        let ratio = w / h;
                        if (hasMinA && ratio < c.minA) {
                            let mA = c.minA;
                            let hProj = (w * mA + h) / (mA * mA + 1);
                            let hMin = Math.max(c.minH, c.minW / mA);
                            let hMax = Math.min(c.maxH, c.maxW / mA);
                            h = Math.max(hMin, Math.min(hMax, hProj));
                            w = h * mA;
                        } else if (hasMaxA && ratio > c.maxA) {
                            let mA = c.maxA;
                            let hProj = (w * mA + h) / (mA * mA + 1);
                            let hMin = Math.max(c.minH, c.minW / mA);
                            let hMax = Math.min(c.maxH, c.maxW / mA);
                            h = Math.max(hMin, Math.min(hMax, hProj));
                            w = h * mA;
                        }

                        w = Math.max(c.minW, Math.min(c.maxW, w));
                        h = Math.max(c.minH, Math.min(c.maxH, h));

                        return { w: w, h: h };
                    }

                    function axisKeys(axis) {
                        // min / max: the visible part of the world along the axis. With the home
                        // camera this is 0 .. screen size, i.e. the classic behaviour.
                        return axis === "x"
                            ? { horizontal: true, lo: "l", hi: "r", clo: "t", chi: "b", extent: viewW, crossExtent: viewH, min: viewX, max: viewX + viewW, cmin: viewY, cmax: viewY + viewH }
                            : { horizontal: false, lo: "t", hi: "b", clo: "l", chi: "r", extent: viewH, crossExtent: viewW, min: viewY, max: viewY + viewH, cmin: viewX, cmax: viewX + viewW };
                    }

                    function boxOf(item) {
                        return { l: item.x, t: item.y, r: item.x + item.width, b: item.y + item.height };
                    }

                    function otherBoxes(excluded) {
                        let out = [];
                        for (let i = 0; i < widgetRepeater.count; i++) {
                            let p = widgetRepeater.itemAt(i);
                            if (p && p !== excluded && !dragExcluded[String(p.wId)]) out.push(boxOf(p));
                        }
                        return out;
                    }

                    function shiftBox(box, k, lo) {
                        let out = { l: box.l, t: box.t, r: box.r, b: box.b };
                        out[k.hi] = lo + box[k.hi] - box[k.lo];
                        out[k.lo] = lo;
                        return out;
                    }

                    function crossOverlap(a, b, k) {
                        return a[k.clo] < b[k.chi] - 0.5 && a[k.chi] > b[k.clo] + 0.5;
                    }

                    function neighbor(box, others, k, side) {
                        let best = null;
                        for (let i = 0; i < others.length; i++) {
                            let o = others[i];
                            if (!crossOverlap(box, o, k)) continue;
                            let gap = side < 0 ? box[k.lo] - o[k.hi] : o[k.lo] - box[k.hi];
                            if (gap > -0.5 && (!best || gap < best.gap)) best = { box: o, gap: Math.max(0, gap) };
                        }
                        return best;
                    }

                    function gapSegment(box, others, k, side) {
                        let n = neighbor(box, others, k, side);
                        if (n) {
                            return {
                                from: side < 0 ? n.box[k.hi] : box[k.hi],
                                to: side < 0 ? box[k.lo] : n.box[k.lo],
                                cross: (Math.max(box[k.clo], n.box[k.clo]) + Math.min(box[k.chi], n.box[k.chi])) / 2,
                                edge: false
                            };
                        }
                        return {
                            from: side < 0 ? k.min : box[k.hi],
                            to: side < 0 ? box[k.lo] : k.max,
                            cross: (box[k.clo] + box[k.chi]) / 2,
                            edge: true
                        };
                    }

                    function measureShape(k, seg) {
                        let length = seg.to - seg.from;
                        return {
                            horizontal: k.horizontal,
                            x: k.horizontal ? seg.from : seg.cross,
                            y: k.horizontal ? seg.cross : seg.from,
                            length: length,
                            value: Math.round(length)
                        };
                    }

                    function alignmentLines(k, others) {
                        let lines = [k.min, k.min + k.extent / 3, k.min + k.extent / 2, k.min + k.extent * 2 / 3, k.max];
                        for (let i = 0; i < others.length; i++) {
                            let o = others[i];
                            lines.push(o[k.lo], (o[k.lo] + o[k.hi]) / 2, o[k.hi]);
                        }
                        return lines;
                    }

                    function snapAxis(box, others, k) {
                        let raw = box[k.lo];
                        let size = box[k.hi] - raw;
                        let best = { lo: raw, diff: snapThreshold, line: noLine, refs: [] };

                        let lines = alignmentLines(k, others);
                        let points = [0, size / 2, size];
                        for (let i = 0; i < lines.length; i++) {
                            for (let j = 0; j < points.length; j++) {
                                let lo = lines[i] - points[j];
                                let diff = Math.abs(lo - raw);
                                if (diff < best.diff) best = { lo: lo, diff: diff, line: lines[i], refs: [] };
                            }
                        }

                        let offerSpacing = (lo, accept) => {
                            let diff = Math.abs(lo - raw);
                            if (diff >= best.diff) return;
                            let refs = accept(shiftBox(box, k, lo));
                            if (refs) best = { lo: lo, diff: diff, line: noLine, refs: refs };
                        };
                        let isGap = (n, o, value) => n !== null && n.box === o && Math.abs(n.gap - value) < 0.5;

                        let gaps = [];
                        let margins = [];
                        for (let i = 0; i < others.length; i++) {
                            let o = others[i];
                            let next = neighbor(o, others, k, 1);
                            if (next && next.gap >= 1) gaps.push(gapSegment(o, others, k, 1));
                            if (!next) margins.push(gapSegment(o, others, k, 1));
                            if (!neighbor(o, others, k, -1)) margins.push(gapSegment(o, others, k, -1));
                        }

                        for (let i = 0; i < gaps.length; i++) {
                            let g = gaps[i];
                            let value = g.to - g.from;
                            for (let j = 0; j < others.length; j++) {
                                let o = others[j];
                                if (!crossOverlap(box, o, k)) continue;
                                offerSpacing(o[k.hi] + value, b => isGap(neighbor(b, others, k, -1), o, value) ? [measureShape(k, g)] : null);
                                offerSpacing(o[k.lo] - value - size, b => isGap(neighbor(b, others, k, 1), o, value) ? [measureShape(k, g)] : null);
                            }
                        }

                        for (let i = 0; i < margins.length; i++) {
                            let m = margins[i];
                            let value = m.to - m.from;
                            if (value < 1) continue;
                            offerSpacing(k.min + value, b => neighbor(b, others, k, -1) ? null : [measureShape(k, m), measureShape(k, gapSegment(b, others, k, -1))]);
                            offerSpacing(k.max - value - size, b => neighbor(b, others, k, 1) ? null : [measureShape(k, m), measureShape(k, gapSegment(b, others, k, 1))]);
                        }

                        let before = neighbor(box, others, k, -1);
                        let after = neighbor(box, others, k, 1);
                        if (before && after) {
                            offerSpacing((before.box[k.hi] + after.box[k.lo] - size) / 2, b => {
                                let nb = neighbor(b, others, k, -1);
                                let na = neighbor(b, others, k, 1);
                                return (nb && na && nb.box === before.box && na.box === after.box) ? [] : null;
                            });
                        }

                        return best;
                    }

                    function calculateSnap(draggedItem, rawX, rawY, bypass) {
                        let w = draggedItem.width;
                        let h = draggedItem.height;
                        let res = { x: rawX, y: rawY, lines: { x: noLine, y: noLine }, refs: [] };

                        if (gridEnabled) {
                            let gridStep = redactorMode.gridStep;
                            res.x = Math.round(rawX / gridStep) * gridStep;
                            res.y = Math.round(rawY / gridStep) * gridStep;
                        } else if (!bypass && snapGuidesEnabled) {
                            let others = otherBoxes(draggedItem);
                            let kx = axisKeys("x");
                            let ky = axisKeys("y");
                            let box = { l: rawX, t: rawY, r: rawX + w, b: rawY + h };
                            let sx = snapAxis(box, others, kx);
                            box = shiftBox(box, kx, sx.lo);
                            let sy = snapAxis(box, others, ky);
                            box = shiftBox(box, ky, sy.lo);
                            res.x = box.l;
                            res.y = box.t;
                            res.lines = { x: sx.line, y: sy.line };
                            res.refs = sx.refs.concat(sy.refs);
                        }

                        res.x = clampX(res.x, w);
                        res.y = clampY(res.y, h);
                        res.box = { l: res.x, t: res.y, r: res.x + w, b: res.y + h };

                        return res;
                    }

                    function snapEdges(item, box, sides) {
                        let others = otherBoxes(item);
                        let out = { x: null, y: null };
                        let axes = ["x", "y"];
                        for (let a = 0; a < axes.length; a++) {
                            let side = sides[axes[a]];
                            if (!side) continue;
                            let k = axisKeys(axes[a]);
                            let edge = side < 0 ? box[k.lo] : box[k.hi];
                            let lines = alignmentLines(k, others);
                            let bestDiff = snapThreshold;
                            for (let i = 0; i < lines.length; i++) {
                                let diff = Math.abs(lines[i] - edge);
                                if (diff < bestDiff) {
                                    bestDiff = diff;
                                    out[axes[a]] = { line: lines[i], diff: diff };
                                }
                            }
                        }
                        return out;
                    }

                    function guideSegment(box, others, k, line) {
                        let onLine = b => Math.abs(b[k.lo] - line) < 0.5 || Math.abs((b[k.lo] + b[k.hi]) / 2 - line) < 0.5 || Math.abs(b[k.hi] - line) < 0.5;
                        if (!onLine(box)) return null;

                        let from = box[k.clo];
                        let to = box[k.chi];
                        let linked = false;
                        for (let i = 0; i < others.length; i++) {
                            if (!onLine(others[i])) continue;
                            from = Math.min(from, others[i][k.clo]);
                            to = Math.max(to, others[i][k.chi]);
                            linked = true;
                        }
                        if (!linked) {
                            from = k.cmin;
                            to = k.cmax;
                        }

                        let t = s(1) / viewZoom;
                        return k.horizontal
                            ? { x: line - t / 2, y: from, w: t, h: to - from }
                            : { x: from, y: line - t / 2, w: to - from, h: t };
                    }

                    function presentOverlay(item, box, snap) {
                        let others = otherBoxes(item);
                        let guides = [];
                        let measures = snap ? snap.refs.slice() : [];
                        let axes = ["x", "y"];
                        for (let a = 0; a < axes.length; a++) {
                            let k = axisKeys(axes[a]);
                            let line = snap ? snap.lines[axes[a]] : noLine;
                            if (line !== noLine) {
                                let guide = guideSegment(box, others, k, line);
                                if (guide) guides.push(guide);
                            }
                            for (let side = -1; side <= 1; side += 2) {
                                let seg = gapSegment(box, others, k, side);
                                if (!seg.edge && seg.to - seg.from >= 1) measures.push(measureShape(k, seg));
                            }
                        }
                        guideLines = guides;
                        measureLines = showDistances ? measures : [];
                    }

                    function clearOverlay() {
                        if (guideLines.length > 0) guideLines = [];
                        if (measureLines.length > 0) measureLines = [];
                    }

                    function proxyFor(widgetId) {
                        for (let i = 0; i < widgetRepeater.count; i++) {
                            let p = widgetRepeater.itemAt(i);
                            if (p && String(p.wId) === String(widgetId)) return p;
                        }
                        return null;
                    }

                    Timer {
                        id: nudgeTimer
                        interval: 600
                        repeat: false
                        onTriggered: redactorMode.finishNudge()
                    }

                    function finishNudge() {
                        nudgeTimer.stop();
                        let proxy = proxyFor(nudgeTargetId);
                        nudgeTargetId = "";
                        if (proxy) proxy.finalizeSync();
                        else clearOverlay();
                        for (let i = 0; i < multiIds.length; i++) {
                            let mate = proxyFor(multiIds[i]);
                            if (mate) mate.finalizeSync();
                        }
                    }

                    function nudgeSelected(dx, dy, large) {
                        let proxy = proxyFor(selectedId);
                        if (!proxy) return;
                        if (nudgeTargetId !== "" && nudgeTargetId !== String(proxy.wId)) finishNudge();

                        let x = proxy.x;
                        let y = proxy.y;
                        let step = large ? 10 : 1;
                        if (gridEnabled) {
                            let gridStep = redactorMode.gridStep;
                            step = gridStep * (large ? 5 : 1);
                            x = Math.round(x / gridStep) * gridStep;
                            y = Math.round(y / gridStep) * gridStep;
                        }
                        let oldX = proxy.x;
                        let oldY = proxy.y;
                        x = clampX(x + dx * step, proxy.width);
                        y = clampY(y + dy * step, proxy.height);

                        activeWidgetsModel.setProperty(proxy.wIndex, "wX", x);
                        activeWidgetsModel.setProperty(proxy.wIndex, "wY", y);
                        proxy.triggerSync();
                        shiftCompanions(x - oldX, y - oldY);
                        presentOverlay(proxy, { l: x, t: y, r: x + proxy.width, b: y + proxy.height }, null);
                        nudgeTargetId = String(proxy.wId);
                        nudgeTimer.restart();
                    }

                    function snapBoxToGrid(loaderItem, x, y, w, h) {
                        let gridStep = redactorMode.gridStep;
                        let L = Math.round(x / gridStep) * gridStep;
                        let T = Math.round(y / gridStep) * gridStep;
                        let R = Math.round((x + w) / gridStep) * gridStep;
                        let B = Math.round((y + h) / gridStep) * gridStep;

                        if (!canvasOn) {
                            L = Math.max(0, Math.min(safeWidth, L));
                            T = Math.max(0, Math.min(safeHeight, T));
                            R = Math.max(0, Math.min(safeWidth, R));
                            B = Math.max(0, Math.min(safeHeight, B));
                        }

                        if (R <= L) R = L + gridStep;
                        if (B <= T) B = T + gridStep;

                        let snappedW = R - L;
                        let snappedH = B - T;

                        let clamped = clampResize(loaderItem, snappedW, snappedH, 0, 0, true);

                        let finalX = L;
                        let finalY = T;
                        finalX = clampX(finalX, clamped.w);
                        finalY = clampY(finalY, clamped.h);

                        return { x: finalX, y: finalY, w: clamped.w, h: clamped.h };
                    }

                    function calculateResize(loaderItem, startX, startY, startW, startH, dx, dy, edges, isCorner, rot) {
                        let rawW = startW;
                        let rawH = startH;

                        if (edges.left) rawW = startW - dx;
                        else if (edges.right) rawW = startW + dx;

                        if (edges.top) rawH = startH - dy;
                        else if (edges.bottom) rawH = startH + dy;

                        let gridStep = redactorMode.gridStep;
                        if (gridEnabled) {
                            if (edges.left || edges.right) rawW = Math.round(rawW / gridStep) * gridStep;
                            if (edges.top || edges.bottom) rawH = Math.round(rawH / gridStep) * gridStep;
                        }

                        let normRot = ((Math.round(rot || 0) % 360) + 360) % 360;
                        let isRot90 = (normRot % 180 !== 0);
                        let maxAllowedW = canvasOn ? 20000 : (isRot90 ? safeHeight : safeWidth);
                        let maxAllowedH = canvasOn ? 20000 : (isRot90 ? safeWidth : safeHeight);

                        rawW = Math.max(10, Math.min(maxAllowedW, rawW));
                        rawH = Math.max(10, Math.min(maxAllowedH, rawH));

                        let clamped = clampResize(loaderItem, rawW, rawH, dx, dy, isCorner);
                        let finalW = Math.max(10, Math.min(maxAllowedW, clamped.w));
                        let finalH = Math.max(10, Math.min(maxAllowedH, clamped.h));

                        return { x: startX, y: startY, w: finalW, h: finalH };
                    }

                    function snapAllWidgetsToGrid() {
                        for (let i = 0; i < widgetRepeater.count; i++) {
                            let proxy = widgetRepeater.itemAt(i);
                            if (!proxy || !proxy.preview || proxy.preview.status !== Loader.Ready) continue;

                            let row = activeWidgetsModel.get(i);
                            if (!row) continue;
                            let res = snapBoxToGrid(proxy.preview.item, row.wX, row.wY, row.wWidth, row.wHeight);

                            if (res.x !== row.wX || res.y !== row.wY || res.w !== row.wWidth || res.h !== row.wHeight) {
                                activeWidgetsModel.setProperty(i, "wX", res.x);
                                activeWidgetsModel.setProperty(i, "wY", res.y);
                                activeWidgetsModel.setProperty(i, "wWidth", res.w);
                                activeWidgetsModel.setProperty(i, "wHeight", res.h);
                                proxy.finalizeSync();
                            }
                        }
                    }

                    function openImagePicker(targetIdx, targetId, curImg, isRound) {
                        imagePickerLoader.active = true;
                        let trigger = () => {
                            if (imagePickerLoader.item) {
                                imagePickerLoader.item.targetWidgetIndex = targetIdx;
                                imagePickerLoader.item.targetWidgetId = String(targetId);
                                imagePickerLoader.item.openPicker(curImg, isRound);
                            }
                        };
                        if (imagePickerLoader.status === Loader.Ready) {
                            trigger();
                        } else {
                            let conn = function() {
                                if (imagePickerLoader.status === Loader.Ready) {
                                    imagePickerLoader.statusChanged.disconnect(conn);
                                    trigger();
                                }
                            };
                            imagePickerLoader.statusChanged.connect(conn);
                        }
                    }

                    function addWidget(typeKey) {
                        let t = WidgetRegistry.types[typeKey];
                        if (!t) return;
                        if (t.requiresFilePicker) {
                            openImagePicker(-1, "", "", false);
                            return;
                        }
                        let def = WidgetRegistry.defaultSize(typeKey);
                        let defW = def.w;
                        let defH = def.h;
                        let spawnX = redactorMode.spawnX(defW);
                        let spawnY = redactorMode.spawnY(defH);
                        let newId = "w_" + Date.now() + "_" + Math.floor(Math.random() * 1000);

                        if (redactorMode.gridEnabled) {
                            let snapped = redactorMode.snapBoxToGrid(null, spawnX, spawnY, defW, defH);
                            spawnX = snapped.x;
                            spawnY = snapped.y;
                            defW = snapped.w;
                            defH = snapped.h;
                        }

                        let defVariant = WidgetRegistry.defaultVariant(typeKey);

                        activeWidgetsModel.append({
                            "wType": typeKey,
                            "wVariant": defVariant,
                            "wX": spawnX,
                            "wY": spawnY,
                            "wWidth": defW,
                            "wHeight": defH,
                            "wOpacity": 1.0,
                            "wRotation": 0,
                            "wImagePath": "",
                            "wId": newId
                        });

                        redactorMode.topZ += 1;
                        redactorMode.selectedId = newId;
                        root.targetSelectedWidgetId = newId;
                        WidgetSync.addWidget(redactorWindow.safeMonitorName, newId, typeKey, spawnX, spawnY, defW, defH, 1.0, "", 0, defVariant);
                        WidgetSync.bringToFront(redactorWindow.safeMonitorName, newId);
                        redactorMode.updateToolbarObscured();
                    }

                    function setWidgetProperty(propName, val, targetId) {
                        let tid = targetId || redactorMode.selectedId;
                        if (!tid) return;
                        for (let i = 0; i < activeWidgetsModel.count; i++) {
                            let row = activeWidgetsModel.get(i);
                            if (String(row.wId) === String(tid)) {
                                activeWidgetsModel.setProperty(i, propName, val);
                                let proxy = widgetRepeater.itemAt(i);
                                if (proxy) {
                                    if (proxy.preview && proxy.preview.item) {
                                        try {
                                            if (proxy.preview.item[propName] !== undefined) {
                                                proxy.preview.item[propName] = val;
                                            }
                                        } catch (e) {}
                                    }
                                    if (typeof WidgetSync !== "undefined") {
                                        if (typeof WidgetSync.setProperty === "function") {
                                            WidgetSync.setProperty(redactorWindow.safeMonitorName, String(tid), propName, val);
                                        } else if (typeof WidgetSync.setWidgetProperty === "function") {
                                            WidgetSync.setWidgetProperty(redactorWindow.safeMonitorName, String(tid), propName, val);
                                        } else if (typeof WidgetSync.setCustomProperty === "function") {
                                            WidgetSync.setCustomProperty(redactorWindow.safeMonitorName, String(tid), propName, val);
                                        }
                                    }
                                    proxy.finalizeSync();
                                }
                                break;
                            }
                        }
                    }

                    function updateWidgetProperty(target, propName, val) {
                        let tid = (target && (target.wId || target.id)) ? (target.wId || target.id) : redactorMode.selectedId;
                        setWidgetProperty(propName, val, tid);
                    }

                    // ---- infinite canvas: helpers ----

                    // Positions are unbounded on the canvas and kept on screen without it.
                    function clampX(x, w) {
                        return canvasOn ? x : Math.max(0, Math.min(Math.max(0, safeWidth - w), x));
                    }

                    function clampY(y, h) {
                        return canvasOn ? y : Math.max(0, Math.min(Math.max(0, safeHeight - h), y));
                    }

                    // New widgets appear in the middle of what the user is looking at.
                    function spawnX(w) {
                        return canvasOn ? viewX + (viewW - w) / 2 : Math.max(0, (safeWidth - s(w)) / 2);
                    }

                    function spawnY(h) {
                        return canvasOn ? viewY + (viewH - h) / 2 : Math.max(0, (safeHeight - s(h)) / 2);
                    }

                    function rowIndex(widgetId) {
                        let target = String(widgetId);
                        for (let i = 0; i < activeWidgetsModel.count; i++) {
                            if (String(activeWidgetsModel.get(i).wId) === target) return i;
                        }
                        return -1;
                    }

                    function modelRows() {
                        return JSON.parse(snapshotModel());
                    }

                    function refreshCanvasWidgets() {
                        canvasWidgets = modelRows();
                    }

                    Timer {
                        id: canvasListTimer
                        interval: 60
                        onTriggered: redactorMode.refreshCanvasWidgets()
                    }

                    Connections {
                        target: activeWidgetsModel
                        function onDataChanged() { canvasListTimer.restart(); }
                        function onCountChanged() { canvasListTimer.restart(); }
                    }

                    // ---- selection ----

                    function groupMates(widgetId) {
                        let idx = rowIndex(widgetId);
                        if (idx < 0) return [];
                        let group = activeWidgetsModel.get(idx).wGroup;
                        if (!group) return [];
                        let out = [];
                        for (let i = 0; i < activeWidgetsModel.count; i++) {
                            let row = activeWidgetsModel.get(i);
                            if (i !== idx && String(row.wGroup || "") === String(group)) out.push(String(row.wId));
                        }
                        return out;
                    }

                    function setSelection(primary, others) {
                        keepMulti = true;
                        multiIds = others;
                        selectedId = primary;
                        root.targetSelectedWidgetId = primary;
                        keepMulti = false;
                        updateToolbarObscured();
                    }

                    function clearSelection() {
                        setSelection("", []);
                    }

                    // Plain press on a widget: it becomes the primary one. A widget that is
                    // already part of the selection keeps the rest selected, so a group can be
                    // dragged by any of its members.
                    function pressSelect(widgetId) {
                        let id = String(widgetId);
                        if (id === String(selectedId)) return;
                        if (multiIds.indexOf(id) >= 0) {
                            let rest = multiIds.filter(x => x !== id);
                            if (selectedId !== "") rest.push(String(selectedId));
                            setSelection(id, rest);
                        } else {
                            setSelection(id, groupMates(id));
                        }
                    }

                    // Shift+click: add or remove a widget (with its group) from the selection.
                    function toggleInSelection(widgetId) {
                        let id = String(widgetId);
                        if (selectedId === "") {
                            pressSelect(id);
                            return;
                        }
                        let unit = [id].concat(groupMates(id));
                        if (unit.indexOf(String(selectedId)) >= 0) {
                            let rest = multiIds.filter(x => unit.indexOf(x) < 0);
                            if (rest.length === 0) clearSelection();
                            else setSelection(rest[0], rest.slice(1));
                            return;
                        }
                        if (multiIds.indexOf(id) >= 0) {
                            setSelection(String(selectedId), multiIds.filter(x => unit.indexOf(x) < 0));
                        } else {
                            let next = multiIds.slice();
                            for (let i = 0; i < unit.length; i++) {
                                if (next.indexOf(unit[i]) < 0) next.push(unit[i]);
                            }
                            setSelection(String(selectedId), next);
                        }
                    }

                    function selectIds(ids) {
                        if (!ids || ids.length === 0) {
                            clearSelection();
                            return;
                        }
                        let primary = (selectedId !== "" && ids.indexOf(String(selectedId)) >= 0) ? String(selectedId) : ids[0];
                        setSelection(primary, ids.filter(x => x !== primary));
                    }

                    function selectAll() {
                        let ids = [];
                        for (let i = 0; i < activeWidgetsModel.count; i++) ids.push(String(activeWidgetsModel.get(i).wId));
                        selectIds(ids);
                    }

                    // rect is in world coordinates.
                    function selectInRect(rect) {
                        let rows = modelRows();
                        selectIds(CM.expandSelection(rows, CM.widgetsInRect(rows, rect)));
                    }

                    function selectionRecords() {
                        let ids = selectionIdList;
                        return modelRows().filter(r => ids.indexOf(String(r.wId)) >= 0);
                    }

                    // ---- moving several widgets ----

                    // Start positions of everything that follows the dragged widget.
                    function companionStarts() {
                        let out = [];
                        let excluded = {};
                        for (let i = 0; i < multiIds.length; i++) {
                            let idx = rowIndex(multiIds[i]);
                            if (idx < 0) continue;
                            let row = activeWidgetsModel.get(idx);
                            out.push({ id: multiIds[i], x: row.wX, y: row.wY });
                            excluded[multiIds[i]] = true;
                        }
                        dragExcluded = excluded;
                        return out;
                    }

                    function moveCompanions(list, dx, dy) {
                        for (let i = 0; i < list.length; i++) {
                            let idx = rowIndex(list[i].id);
                            if (idx < 0) continue;
                            activeWidgetsModel.setProperty(idx, "wX", list[i].x + dx);
                            activeWidgetsModel.setProperty(idx, "wY", list[i].y + dy);
                            let p = proxyFor(list[i].id);
                            if (p) p.triggerSync();
                        }
                    }

                    function finishCompanions(list) {
                        for (let i = 0; i < list.length; i++) {
                            let p = proxyFor(list[i].id);
                            if (p) p.finalizeSync();
                        }
                        dragExcluded = ({});
                    }

                    function shiftCompanions(dx, dy) {
                        if (dx === 0 && dy === 0) return;
                        for (let i = 0; i < multiIds.length; i++) {
                            let idx = rowIndex(multiIds[i]);
                            if (idx < 0) continue;
                            let row = activeWidgetsModel.get(idx);
                            activeWidgetsModel.setProperty(idx, "wX", row.wX + dx);
                            activeWidgetsModel.setProperty(idx, "wY", row.wY + dy);
                            let p = proxyFor(multiIds[i]);
                            if (p) p.triggerSync();
                        }
                    }

                    // ---- groups ----

                    function groupSelection() {
                        let ids = selectionIdList.slice();
                        if (ids.length < 2) return;
                        let group = CM.newId("g", null);
                        for (let i = 0; i < ids.length; i++) setWidgetProperty("wGroup", group, ids[i]);
                        refreshCanvasWidgets();
                    }

                    function ungroupSelection() {
                        let ids = selectionIdList.slice();
                        for (let i = 0; i < ids.length; i++) {
                            let idx = rowIndex(ids[i]);
                            if (idx >= 0 && activeWidgetsModel.get(idx).wGroup) setWidgetProperty("wGroup", "", ids[i]);
                        }
                        refreshCanvasWidgets();
                    }

                    function removeSelection() {
                        let ids = selectionIdList.slice();
                        for (let i = 0; i < ids.length; i++) removeWidget(ids[i]);
                    }

                    // ---- compositions ----

                    // Saves the selection, or the whole layout when nothing is selected.
                    function saveSelectionAsComposition(name) {
                        let records = selectionRecords();
                        if (records.length === 0) records = modelRows();
                        return CanvasState.saveComposition(name, records);
                    }

                    function insertComposition(compositionId) {
                        let mon = redactorWindow.safeMonitorName;
                        let list = CanvasState.instantiate(mon, compositionId);
                        let ids = [];
                        for (let i = 0; i < list.length; i++) {
                            let w = list[i];
                            if (!WidgetRegistry.types[w.wType]) continue;
                            let entry = Object.assign({}, w);
                            if (!entry.wGroup) delete entry.wGroup;
                            if (!entry.wVariant) entry.wVariant = WidgetRegistry.defaultVariant(w.wType);
                            activeWidgetsModel.append(entry);
                            redactorMode.topZ += 1;
                            WidgetSync.addWidget(mon, entry.wId, entry.wType, entry.wX, entry.wY, entry.wWidth, entry.wHeight, entry.wOpacity, entry.wImagePath, entry.wRotation, entry.wVariant);
                            let keys = customKeys(entry);
                            for (let j = 0; j < keys.length; j++) WidgetSync.setProperty(mon, entry.wId, keys[j], entry[keys[j]]);
                            ids.push(entry.wId);
                        }
                        if (ids.length > 0) setSelection(ids[0], ids.slice(1));
                        refreshCanvasWidgets();
                        return ids.length;
                    }

                    // ---- camera ----

                    function focusWidget(widgetId) {
                        let p = proxyFor(widgetId);
                        if (!p) return;
                        pressSelect(widgetId);
                        if (canvasOn) cam.focusBox({ x: p.x, y: p.y, w: p.width, h: p.height });
                    }

                    function fitAll() {
                        if (canvasOn) cam.fitBounds(CM.boundsOf(modelRows()));
                    }

                    property var historyStack: []
                    property int historyIndex: -1

                    function snapshotModel() {
                        let out = [];
                        for (let i = 0; i < activeWidgetsModel.count; i++) {
                            let row = activeWidgetsModel.get(i);
                            let o = {};
                            for (let k in row) {
                                if (!k || typeof k !== "string" || k === "objectName" || k.endsWith("Changed") || k.startsWith("on") || typeof row[k] === "function" || row[k] === undefined) continue;
                                o[k] = row[k];
                            }
                            out.push(o);
                        }
                        return JSON.stringify(out);
                    }

                    function resetHistory() {
                        redactorMode.historyStack = [redactorMode.snapshotModel()];
                        redactorMode.historyIndex = 0;
                    }

                    function commitHistory() {
                        if (redactorMode.isInitializing || !redactorMode.isReady || redactorMode.historyIndex < 0) return;
                        let snap = redactorMode.snapshotModel();
                        if (redactorMode.historyStack[redactorMode.historyIndex] === snap) return;
                        let stack = redactorMode.historyStack.slice(0, redactorMode.historyIndex + 1);
                        stack.push(snap);
                        if (stack.length > 100) stack.shift();
                        redactorMode.historyStack = stack;
                        redactorMode.historyIndex = stack.length - 1;
                    }

                    function stepHistory(delta) {
                        if (redactorMode.isInitializing || redactorMode.historyIndex < 0) return;
                        redactorMode.saveConfig();
                        redactorMode.commitHistory();
                        let target = redactorMode.historyIndex + delta;
                        if (target < 0 || target >= redactorMode.historyStack.length) return;
                        redactorMode.historyIndex = target;
                        redactorMode.restoreSnapshot(redactorMode.historyStack[target]);
                    }

                    function undo() {
                        redactorMode.stepHistory(-1);
                    }

                    function redo() {
                        redactorMode.stepHistory(1);
                    }

                    function customKeys(entry) {
                        return Object.keys(entry).filter(k => !WidgetRegistry.standardKeys.includes(k));
                    }

                    function restoreSnapshot(text) {
                        let target = JSON.parse(text);
                        let current = JSON.parse(redactorMode.snapshotModel());
                        let mon = redactorWindow.safeMonitorName;
                        let currentById = {};
                        let targetById = {};
                        for (let i = 0; i < current.length; i++) currentById[String(current[i].wId)] = current[i];
                        for (let i = 0; i < target.length; i++) targetById[String(target[i].wId)] = target[i];

                        redactorMode.isInitializing = true;

                        for (let id in currentById) {
                            if (!targetById[id]) WidgetSync.removeWidget(mon, id);
                        }

                        for (let i = 0; i < target.length; i++) {
                            let e = target[i];
                            let id = String(e.wId);
                            let old = currentById[id];
                            if (!old) {
                                WidgetSync.addWidget(mon, id, e.wType, e.wX, e.wY, e.wWidth, e.wHeight, e.wOpacity, e.wImagePath || "", e.wRotation, e.wVariant);
                                let keys = redactorMode.customKeys(e);
                                for (let j = 0; j < keys.length; j++) WidgetSync.setProperty(mon, id, keys[j], e[keys[j]]);
                                continue;
                            }
                            if (old.wX !== e.wX || old.wY !== e.wY || old.wWidth !== e.wWidth || old.wHeight !== e.wHeight || old.wOpacity !== e.wOpacity || old.wRotation !== e.wRotation) {
                                WidgetSync.setGeometry(mon, id, e.wX, e.wY, e.wWidth, e.wHeight, e.wOpacity, e.wRotation);
                            }
                            if (old.wVariant !== e.wVariant) WidgetSync.setVariant(mon, id, e.wVariant);
                            if ((old.wImagePath || "") !== (e.wImagePath || "")) WidgetSync.setImagePath(mon, id, e.wImagePath || "");
                            let keys = redactorMode.customKeys(e);
                            for (let j = 0; j < keys.length; j++) {
                                if (JSON.stringify(old[keys[j]]) !== JSON.stringify(e[keys[j]])) WidgetSync.setProperty(mon, id, keys[j], e[keys[j]]);
                            }
                        }

                        if (redactorMode.selectedId !== "" && !targetById[redactorMode.selectedId]) {
                            redactorMode.selectedId = "";
                            root.targetSelectedWidgetId = "";
                        }

                        activeWidgetsModel.clear();
                        for (let i = 0; i < target.length; i++) activeWidgetsModel.append(target[i]);
                        redactorMode.updateToolbarObscured();
                        initTimer.restart();
                    }

                    Timer {
                        id: historyTimer
                        interval: 400
                        repeat: false
                        onTriggered: redactorMode.commitHistory()
                    }

                    Connections {
                        target: activeWidgetsModel
                        function onCountChanged() { historyTimer.restart(); }
                    }

                    function saveConfig() {
                        for (let i = 0; i < widgetRepeater.count; i++) {
                            let proxy = widgetRepeater.itemAt(i);
                            if (proxy) proxy.finalizeSync();
                        }
                    }

                    function save() {
                        saveConfig();
                    }

                    function handleAdditionalAction(action, itemIndex, itemId, proxy, extraArg) {
                        if (action === "pickImage") {
                            let row = (itemIndex >= 0 && itemIndex < activeWidgetsModel.count) ? activeWidgetsModel.get(itemIndex) : null;
                            let curImg = row ? (row.wImagePath || "") : "";
                            openImagePicker(itemIndex, itemId, curImg, proxy.wVariant === "round");
                        } else if (action === "stretchWidth") {
                            let item = (itemIndex >= 0 && itemIndex < activeWidgetsModel.count) ? activeWidgetsModel.get(itemIndex) : null;
                            if (!item) return;

                            let rot = Math.abs(Math.round(proxy.wRotation || 0)) % 360;
                            if (rot % 180 === 0) {
                                activeWidgetsModel.setProperty(itemIndex, "wX", redactorMode.viewX);
                                activeWidgetsModel.setProperty(itemIndex, "wWidth", redactorMode.viewW);
                            } else {
                                activeWidgetsModel.setProperty(itemIndex, "wY", redactorMode.viewY);
                                activeWidgetsModel.setProperty(itemIndex, "wWidth", redactorMode.viewH);
                            }
                            proxy.finalizeSync();
                        } else if (extraArg !== undefined) {
                            setWidgetProperty(action, extraArg, itemId);
                        }
                    }

                    function resolveThemeColor(colorName) {
                        if (colorName === "mauve") return ThemeBackend.mauve;
                        if (colorName === "surface0") return ThemeBackend.surface0;
                        if (colorName === "surface1") return ThemeBackend.surface1;
                        if (colorName === "crust") return ThemeBackend.crust;
                        if (colorName === "base") return ThemeBackend.base;
                        if (colorName === "red") return ThemeBackend.red;
                        return ThemeBackend.text;
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.55)
                    }

                    // Empty space: click clears the selection, drag moves the camera,
                    // Shift+drag draws a rubber band, the wheel zooms (or pans, see settings).
                    MouseArea {
                        id: canvasInput
                        anchors.fill: parent
                        z: -1
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

                        property real pressX: 0
                        property real pressY: 0
                        property real lastX: 0
                        property real lastY: 0
                        property bool moved: false
                        property string mode: ""

                        function finish(apply) {
                            if (mode === "pan" && moved && redactorMode.cam) {
                                redactorMode.cam.dragEnd();
                            } else if (mode === "marquee") {
                                let m = redactorMode.marquee;
                                redactorMode.marquee = null;
                                if (apply && moved && m) {
                                    let z = redactorMode.viewZoom;
                                    redactorMode.selectInRect({ x: redactorMode.viewX + m.x / z, y: redactorMode.viewY + m.y / z, w: m.w / z, h: m.h / z });
                                }
                            }
                            mode = "";
                        }

                        onPressed: mouse => {
                            pressX = mouse.x;
                            pressY = mouse.y;
                            lastX = mouse.x;
                            lastY = mouse.y;
                            moved = false;
                            if (mouse.button === Qt.LeftButton && (mouse.modifiers & Qt.ShiftModifier)) mode = "marquee";
                            else if (redactorMode.canvasOn && (mouse.button === Qt.MiddleButton || redactorMode.canvasCfg.dragToPan)) mode = "pan";
                            else mode = "";
                        }

                        onPositionChanged: mouse => {
                            if (!pressed) return;
                            if (!moved) {
                                if (Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) < 5) return;
                                moved = true;
                                if (mode === "pan") redactorMode.cam.dragStart();
                            }
                            if (mode === "pan") redactorMode.cam.dragMove(mouse.x - lastX, mouse.y - lastY);
                            else if (mode === "marquee") redactorMode.marquee = CM.normalizeRect(pressX, pressY, mouse.x, mouse.y);
                            lastX = mouse.x;
                            lastY = mouse.y;
                        }

                        onReleased: mouse => {
                            let wasClick = !moved && mouse.button === Qt.LeftButton;
                            finish(true);
                            if (wasClick) redactorMode.clearSelection();
                        }

                        onCanceled: finish(false)

                        onWheel: wheel => {
                            let used = redactorMode.cam && redactorMode.cam.handleWheel(
                                wheel.x, wheel.y, wheel.angleDelta.x, wheel.angleDelta.y, wheel.pixelDelta.x, wheel.pixelDelta.y,
                                (wheel.modifiers & Qt.ControlModifier) !== 0, (wheel.modifiers & Qt.ShiftModifier) !== 0);
                            wheel.accepted = !!used;
                        }
                    }

                    Item {
                        id: snapOverlay
                        // Guides are computed in world coordinates, so the overlay shares the
                        // camera transform of workspaceArea.
                        x: workspaceArea.x
                        y: workspaceArea.y
                        width: parent.width
                        height: parent.height
                        scale: redactorMode.viewZoom
                        transformOrigin: Item.TopLeft
                        z: 100000

                        readonly property real lineWidth: s(1) / redactorMode.viewZoom
                        readonly property real capLength: s(7) / redactorMode.viewZoom

                        Repeater {
                            model: redactorMode.guideLines
                            delegate: Rectangle {
                                x: modelData.x
                                y: modelData.y
                                width: modelData.w
                                height: modelData.h
                                color: ThemeBackend.mauve
                            }
                        }

                        Repeater {
                            model: redactorMode.measureLines
                            delegate: Item {
                                id: measure
                                readonly property bool horizontal: modelData.horizontal
                                readonly property bool labelFits: horizontal
                                    ? modelData.length >= measureLabel.width / redactorMode.viewZoom + snapOverlay.capLength * 2
                                    : modelData.length >= measureLabel.height / redactorMode.viewZoom + snapOverlay.capLength * 2

                                x: modelData.x
                                y: modelData.y
                                width: horizontal ? modelData.length : 0
                                height: horizontal ? 0 : modelData.length

                                Rectangle {
                                    x: measure.horizontal ? 0 : -width / 2
                                    y: measure.horizontal ? -height / 2 : 0
                                    width: measure.horizontal ? measure.width : snapOverlay.lineWidth
                                    height: measure.horizontal ? snapOverlay.lineWidth : measure.height
                                    color: ThemeBackend.mauve
                                }

                                Repeater {
                                    model: 2
                                    delegate: Rectangle {
                                        width: measure.horizontal ? snapOverlay.lineWidth : snapOverlay.capLength
                                        height: measure.horizontal ? snapOverlay.capLength : snapOverlay.lineWidth
                                        x: measure.horizontal ? index * measure.width - width / 2 : -width / 2
                                        y: measure.horizontal ? -height / 2 : index * measure.height - height / 2
                                        color: ThemeBackend.mauve
                                    }
                                }

                                Rectangle {
                                    id: measureLabel
                                    // Labels keep their on-screen size at any zoom.
                                    scale: 1 / redactorMode.viewZoom
                                    width: measureText.implicitWidth + s(12)
                                    height: s(20)
                                    radius: Math.min(ThemeBackend.borderRadius, height / 2)
                                    color: ThemeBackend.mauve
                                    x: measure.horizontal
                                        ? (measure.width - width) / 2
                                        : (measure.labelFits ? -width / 2 : s(6))
                                    y: measure.horizontal
                                        ? (measure.labelFits ? -height / 2 : -height - s(6))
                                        : (measure.height - height) / 2

                                    Text {
                                        id: measureText
                                        anchors.centerIn: parent
                                        text: modelData.value
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: s(11)
                                        font.bold: true
                                        color: ThemeBackend.crust
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: workspaceArea
                        // The world. screen = (world - camera) * zoom; with the home camera this
                        // item sits at 0,0 with scale 1 exactly like before.
                        x: -redactorMode.viewX * redactorMode.viewZoom
                        y: -redactorMode.viewY * redactorMode.viewZoom
                        width: parent.width
                        height: parent.height
                        scale: redactorMode.viewZoom
                        transformOrigin: Item.TopLeft

                        Loader {
                            id: gridLoader
                            // Covers the visible part of the world, aligned to the grid so the
                            // lines stay put while the camera moves.
                            readonly property real cell: CM.displayGridStep(redactorMode.gridStep, redactorMode.viewZoom, 10)
                            x: Math.floor(redactorMode.viewX / cell) * cell
                            y: Math.floor(redactorMode.viewY / cell) * cell
                            width: redactorMode.viewW + cell
                            height: redactorMode.viewH + cell
                            active: redactorMode.gridEnabled
                            sourceComponent: ShaderEffect {
                                id: gridShader
                                anchors.fill: parent
                                property vector2d itemSize: Qt.vector2d(width, height)
                                property real stepSize: gridLoader.cell
                                property real lineWidth: 1.0 / redactorMode.viewZoom
                                property color lineColor: Qt.rgba(ThemeBackend.text.r, ThemeBackend.text.g, ThemeBackend.text.b, 0.1)

                                onStatusChanged: { if (String(fragmentShader) !== "") GpuCompatibility.observeShader(String(fragmentShader), status, log); }
                                fragmentShader: GpuCompatibility.shadersAllowed ? ("file://" + Caching.serpantinumDir + "/assets/shaders/ui/grid_pattern.frag.qsb") : ""
                            }
                        }

                        Repeater {
                            id: widgetRepeater
                            model: redactorMode.activeWidgetsModel
                            delegate: Item {
                                id: widgetProxy
                                property real wRotation: (model.wRotation !== undefined && !isNaN(model.wRotation)) ? model.wRotation : 0

                                x: model.wX
                                y: model.wY
                                width: (Math.abs(Math.round(widgetProxy.wRotation || 0)) % 180 === 0) ? model.wWidth : model.wHeight
                                height: (Math.abs(Math.round(widgetProxy.wRotation || 0)) % 180 === 0) ? model.wHeight : model.wWidth

                                property int currentZ: index
                                z: (widgetProxy.isSelected ? 50000 : 0) + currentZ
                                opacity: (redactorMode.selectedId === "" || widgetProxy.isSelected || widgetProxy.isMultiSelected) ? 1.0 : 0.6
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                Component.onCompleted: {
                                    if (!redactorMode.isInitializing) {
                                        redactorMode.topZ += 1;
                                        widgetProxy.currentZ = redactorMode.topZ;
                                    }
                                }

                                Component.onDestruction: {
                                    preview.active = false;
                                    preview.source = "";
                                }

                                function bringToFront() {
                                    redactorMode.topZ += 1;
                                    widgetProxy.currentZ = redactorMode.topZ;
                                    WidgetSync.bringToFront(redactorWindow.safeMonitorName, String(widgetProxy.wId));
                                }

                                // Handles and outlines live inside the zoomed world; hs() sizes them so
                                // they keep their on-screen size at any zoom.
                                function hs(val) { return s(val) / redactorMode.viewZoom; }
                                readonly property real inv: 1 / redactorMode.viewZoom
                                // Screen-space box of this proxy (for placing the settings chrome).
                                readonly property real scrX: (x - redactorMode.viewX) * redactorMode.viewZoom
                                readonly property real scrY: (y - redactorMode.viewY) * redactorMode.viewZoom
                                readonly property real scrW: width * redactorMode.viewZoom
                                readonly property real scrH: height * redactorMode.viewZoom
                                readonly property bool isMultiSelected: redactorMode.multiIds.indexOf(String(wId)) >= 0

                                property real selectionGap: hs(8)

                                property alias preview: preview
                                property string wType: model.wType || ""
                                property string wVariant: model.wVariant || ""
                                property string wImagePath: model.wImagePath || ""
                                property string wId: model.wId || ""
                                property real wOpacity: model.wOpacity !== undefined ? model.wOpacity : 1.0
                                property int wIndex: index

                                property bool isSelected: redactorMode.selectedId === widgetProxy.wId
                                property bool hasUnsyncedChanges: false

                                property var savedAspects: ({})

                                Connections {
                                    target: baseSelectMa
                                    function onPressedChanged() {
                                        if (!baseSelectMa.pressed) {
                                            bottomChrome.posMode = bottomChrome.calculatedPosMode;
                                        }
                                    }
                                }

                                function applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, mouseArea, edges, isCorner) {
                                    let localPos = mouseArea.mapToItem(workspaceArea, mouse.x, mouse.y);
                                    let dx = localPos.x - startMouseX;
                                    let dy = localPos.y - startMouseY;

                                    let rot = widgetProxy.wRotation || 0;
                                    let rad = rot * Math.PI / 180.0;
                                    let cos = Math.cos(rad);
                                    let sin = Math.sin(rad);

                                    let ldx = dx * cos + dy * sin;
                                    let ldy = -dx * sin + dy * cos;

                                    let passLdx = isCorner ? ldx : (edges.left || edges.right ? ldx : 0);
                                    let passLdy = isCorner ? ldy : (edges.top || edges.bottom ? ldy : 0);

                                    let rot90 = Math.abs(Math.round(rot)) % 180 !== 0;
                                    let startCX = startWidgetX + (rot90 ? startHeight : startWidth) / 2.0;
                                    let startCY = startWidgetY + (rot90 ? startWidth : startHeight) / 2.0;

                                    let pxFixed = edges.left ? startWidth / 2.0 : (edges.right ? -startWidth / 2.0 : 0);
                                    let pyFixed = edges.top ? startHeight / 2.0 : (edges.bottom ? -startHeight / 2.0 : 0);
                                    let fixedX = startCX + pxFixed * cos - pyFixed * sin;
                                    let fixedY = startCY + pxFixed * sin + pyFixed * cos;

                                    let place = (w, h) => {
                                        let pxNew = edges.left ? w / 2.0 : (edges.right ? -w / 2.0 : 0);
                                        let pyNew = edges.top ? h / 2.0 : (edges.bottom ? -h / 2.0 : 0);
                                        let bw = rot90 ? h : w;
                                        let bh = rot90 ? w : h;
                                        let x = fixedX - (pxNew * cos - pyNew * sin) - bw / 2.0;
                                        let y = fixedY - (pxNew * sin + pyNew * cos) - bh / 2.0;
                                        x = redactorMode.clampX(x, bw);
                                        y = redactorMode.clampY(y, bh);
                                        return { l: x, t: y, r: x + bw, b: y + bh };
                                    };

                                    let res = redactorMode.calculateResize(preview.item, startWidgetX, startWidgetY, startWidth, startHeight, passLdx, passLdy, edges, isCorner, rot);
                                    let box = place(res.w, res.h);
                                    let lines = { x: redactorMode.noLine, y: redactorMode.noLine };
                                    let free = !redactorMode.gridEnabled && (mouse.modifiers & Qt.ControlModifier) === 0;

                                    if (free) {
                                        let sides = { x: 0, y: 0 };
                                        let addSide = (nx, ny) => {
                                            sides.x += Math.round(nx * cos - ny * sin);
                                            sides.y += Math.round(nx * sin + ny * cos);
                                        };
                                        if (edges.left) addSide(-1, 0);
                                        if (edges.right) addSide(1, 0);
                                        if (edges.top) addSide(0, -1);
                                        if (edges.bottom) addSide(0, 1);

                                        let hit = redactorMode.snapEdges(widgetProxy, box, sides);
                                        let aspect = selectionUI.isAspectLocked ? preview.item.minAspect : 0;
                                        if (aspect > 0 && hit.x && hit.y) {
                                            if (hit.x.diff <= hit.y.diff) hit.y = null;
                                            else hit.x = null;
                                        }

                                        if (hit.x || hit.y) {
                                            let w = res.w;
                                            let h = res.h;
                                            if (hit.x) {
                                                let bw = sides.x < 0 ? box.r - hit.x.line : hit.x.line - box.l;
                                                if (rot90) h = bw;
                                                else w = bw;
                                            }
                                            if (hit.y) {
                                                let bh = sides.y < 0 ? box.b - hit.y.line : hit.y.line - box.t;
                                                if (rot90) w = bh;
                                                else h = bh;
                                            }
                                            if (aspect > 0) {
                                                if ((hit.x !== null) !== rot90) h = w / aspect;
                                                else w = h * aspect;
                                            }

                                            let sdx = edges.left ? startWidth - w : (edges.right ? w - startWidth : 0);
                                            let sdy = edges.top ? startHeight - h : (edges.bottom ? h - startHeight : 0);
                                            let snappedRes = redactorMode.calculateResize(preview.item, startWidgetX, startWidgetY, startWidth, startHeight, sdx, sdy, edges, isCorner, rot);
                                            let snappedBox = place(snappedRes.w, snappedRes.h);

                                            let landsX = !hit.x || Math.abs((sides.x < 0 ? snappedBox.l : snappedBox.r) - hit.x.line) < 0.5;
                                            let landsY = !hit.y || Math.abs((sides.y < 0 ? snappedBox.t : snappedBox.b) - hit.y.line) < 0.5;
                                            if (landsX && landsY) {
                                                res = snappedRes;
                                                box = snappedBox;
                                                lines = { x: hit.x ? hit.x.line : redactorMode.noLine, y: hit.y ? hit.y.line : redactorMode.noLine };
                                            }
                                        }
                                    }

                                    let boxW = box.r - box.l;
                                    let boxH = box.b - box.t;
                                    let newX = box.l;
                                    let newY = box.t;

                                    if (redactorMode.gridEnabled) {
                                        let gridStep = redactorMode.gridStep;
                                        newX = redactorMode.clampX(Math.round(newX / gridStep) * gridStep, boxW);
                                        newY = redactorMode.clampY(Math.round(newY / gridStep) * gridStep, boxH);
                                    }

                                    model.wWidth = res.w;
                                    model.wHeight = res.h;
                                    model.wX = newX;
                                    model.wY = newY;

                                    redactorMode.presentOverlay(widgetProxy, { l: newX, t: newY, r: newX + boxW, b: newY + boxH }, { lines: lines, refs: [] });
                                    widgetProxy.triggerSync();
                                }

                                function rotateWidget() {
                                    let currentRot = Math.abs(Math.round(widgetProxy.wRotation || 0)) % 360;
                                    let nextRot = currentRot + 90;

                                    let curBW = (currentRot % 180 === 0) ? model.wWidth : model.wHeight;
                                    let curBH = (currentRot % 180 === 0) ? model.wHeight : model.wWidth;

                                    let centerX = model.wX + curBW / 2.0;
                                    let centerY = model.wY + curBH / 2.0;

                                    let unscaledBW = (nextRot % 180 === 0) ? model.wWidth : model.wHeight;
                                    let unscaledBH = (nextRot % 180 === 0) ? model.wHeight : model.wWidth;

                                    let limitX = redactorMode.safeWidth;
                                    let limitY = redactorMode.safeHeight;

                                    if (toolbar && toolbar.visible && toolbar.opacity > 0.1 && toolbar.y > centerY) {
                                        limitY = toolbar.y;
                                    }

                                    // On the canvas there are no screen edges to shrink against.
                                    let maxBW = redactorMode.canvasOn ? 1e9 : Math.max(20, 2.0 * Math.min(centerX, limitX - centerX));
                                    let maxBH = redactorMode.canvasOn ? 1e9 : Math.max(20, 2.0 * Math.min(centerY, limitY - centerY));

                                    let scaleX = (maxBW > 0 && unscaledBW > maxBW) ? (maxBW / unscaledBW) : 1.0;
                                    let scaleY = (maxBH > 0 && unscaledBH > maxBH) ? (maxBH / unscaledBH) : 1.0;
                                    let scale = Math.min(scaleX, scaleY);

                                    let targetW = model.wWidth;
                                    let targetH = model.wHeight;

                                    if (scale < 1.0) {
                                        targetW = model.wWidth * scale;
                                        targetH = model.wHeight * scale;
                                    }

                                    let clamped = redactorMode.clampResize(preview.item, targetW, targetH, 0, 0, true);
                                    let finalW = clamped.w;
                                    let finalH = clamped.h;

                                    let nextBW = (nextRot % 180 === 0) ? finalW : finalH;
                                    let nextBH = (nextRot % 180 === 0) ? finalH : finalW;

                                    let newX = centerX - nextBW / 2.0;
                                    let newY = centerY - nextBH / 2.0;

                                    newX = redactorMode.clampX(newX, nextBW);
                                    newY = redactorMode.clampY(newY, nextBH);

                                    if (redactorMode.gridEnabled) {
                                        let gridStep = redactorMode.gridStep;
                                        newX = redactorMode.clampX(Math.round(newX / gridStep) * gridStep, nextBW);
                                        newY = redactorMode.clampY(Math.round(newY / gridStep) * gridStep, nextBH);
                                    }

                                    model.wWidth = finalW;
                                    model.wHeight = finalH;
                                    model.wRotation = nextRot;
                                    model.wX = newX;
                                    model.wY = newY;

                                    WidgetSync.setRotation(redactorWindow.safeMonitorName, String(widgetProxy.wId), nextRot);
                                    finalizeSync();
                                }

                                function getDefaultSize(loaderItem) {
                                    let defSize = WidgetRegistry.defaultSize(widgetProxy.wType);
                                    let defW = defSize.w;
                                    let defH = defSize.h;
                                    if (loaderItem && loaderItem.minAspect !== undefined && loaderItem.maxAspect !== undefined && loaderItem.minAspect === loaderItem.maxAspect && loaderItem.minAspect > 0) {
                                        let aspect = loaderItem.minAspect;
                                        if (aspect === 1.0) {
                                            defW = 180;
                                            defH = 180;
                                        } else {
                                            defH = 120;
                                            defW = Math.round(defH * aspect);
                                        }
                                    }
                                    return { w: defW, h: defH };
                                }

                                function applyVariant(variantId) {
                                    if (widgetProxy.wVariant === variantId) return;

                                    let currentAspect = model.wWidth / model.wHeight;
                                    savedAspects[widgetProxy.wVariant] = currentAspect;

                                    let targetAspect = savedAspects[variantId];

                                    model.wVariant = variantId;

                                    if (targetAspect) {
                                        let area = model.wWidth * model.wHeight;
                                        let newH = Math.max(10, Math.sqrt(area / targetAspect));
                                        let newW = Math.max(10, newH * targetAspect);
                                        model.wWidth = newW;
                                        model.wHeight = newH;
                                    }

                                    WidgetSync.setVariant(redactorWindow.safeMonitorName, String(widgetProxy.wId), variantId);
                                    finalizeSync();
                                }

                                function resetWidgetSize() {
                                    let currentRot = Math.abs(Math.round(widgetProxy.wRotation || 0)) % 360;
                                    let curBW = (currentRot % 180 === 0) ? model.wWidth : model.wHeight;
                                    let curBH = (currentRot % 180 === 0) ? model.wHeight : model.wWidth;
                                    let cx = model.wX + curBW / 2.0;
                                    let cy = model.wY + curBH / 2.0;

                                    let def = getDefaultSize(preview.item);
                                    let clamped = redactorMode.clampResize(preview.item, def.w, def.h, 0, 0, true);
                                    let finalW = clamped.w;
                                    let finalH = clamped.h;

                                    let newX = cx - finalW / 2.0;
                                    let newY = cy - finalH / 2.0;

                                    newX = redactorMode.clampX(newX, finalW);
                                    newY = redactorMode.clampY(newY, finalH);

                                    if (redactorMode.gridEnabled) {
                                        let snapped = redactorMode.snapBoxToGrid(preview.item, newX, newY, finalW, finalH);
                                        newX = snapped.x;
                                        newY = snapped.y;
                                        finalW = snapped.w;
                                        finalH = snapped.h;
                                    }

                                    model.wOpacity = 1.0;
                                    model.wRotation = 0;
                                    model.wWidth = finalW;
                                    model.wHeight = finalH;
                                    model.wX = newX;
                                    model.wY = newY;

                                    WidgetSync.setRotation(redactorWindow.safeMonitorName, String(widgetProxy.wId), 0);
                                    finalizeSync();
                                }

                                Timer {
                                    id: syncTimer
                                    interval: 100
                                    running: false
                                    repeat: true
                                    onTriggered: {
                                        if (!widgetProxy.hasUnsyncedChanges) {
                                            running = false;
                                            return;
                                        }
                                        widgetProxy.hasUnsyncedChanges = false;
                                        let curOp = widgetProxy.wOpacity;
                                        let curRot = widgetProxy.wRotation;
                                        WidgetSync.setGeometry(redactorWindow.safeMonitorName, String(widgetProxy.wId), model.wX, model.wY, model.wWidth, model.wHeight, curOp, curRot);
                                    }
                                }

                                function triggerSync() {
                                    if (redactorMode.isInitializing) return;
                                    redactorMode.queueUpdateToolbarObscured();
                                    widgetProxy.hasUnsyncedChanges = true;
                                    if (!syncTimer.running) {
                                        syncTimer.restart();
                                    }
                                }

                                function finalizeSync() {
                                    redactorMode.clearOverlay();
                                    toolbarCheckTimer.stop();
                                    syncTimer.stop();
                                    widgetProxy.hasUnsyncedChanges = false;
                                    let curOp = widgetProxy.wOpacity;
                                    let curRot = widgetProxy.wRotation;
                                    WidgetSync.setGeometry(redactorWindow.safeMonitorName, String(widgetProxy.wId), model.wX, model.wY, model.wWidth, model.wHeight, curOp, curRot);
                                    WidgetSync.setOpacity(redactorWindow.safeMonitorName, String(widgetProxy.wId), curOp);
                                    WidgetSync.setRotation(redactorWindow.safeMonitorName, String(widgetProxy.wId), curRot);
                                    WidgetSync.bringToFront(redactorWindow.safeMonitorName, String(widgetProxy.wId));
                                    redactorMode.updateToolbarObscured();
                                    redactorMode.commitHistory();
                                }

                                MouseArea {
                                    id: baseSelectMa
                                    z: 0
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                                    property real startDragX
                                    property real startDragY
                                    property real startWidgetX
                                    property real startWidgetY
                                    // Shift+click only edits the selection, it never starts a drag.
                                    property bool dragArmed: false
                                    property var companions: []

                                    function endDrag() {
                                        if (!dragArmed) return;
                                        dragArmed = false;
                                        widgetProxy.finalizeSync();
                                        redactorMode.finishCompanions(companions);
                                        companions = [];
                                    }

                                    onPressed: (mouse) => {
                                        if (mouse.modifiers & Qt.ShiftModifier) {
                                            dragArmed = false;
                                            redactorMode.toggleInSelection(widgetProxy.wId);
                                            return;
                                        }
                                        redactorMode.pressSelect(widgetProxy.wId);
                                        widgetProxy.bringToFront();
                                        let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                        startDragX = localPos.x;
                                        startDragY = localPos.y;
                                        startWidgetX = widgetProxy.x;
                                        startWidgetY = widgetProxy.y;
                                        companions = redactorMode.companionStarts();
                                        dragArmed = true;
                                    }

                                    onPositionChanged: (mouse) => {
                                        if (pressed && dragArmed) {
                                            let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                            let dx = localPos.x - startDragX;
                                            let dy = localPos.y - startDragY;

                                            let rawX = startWidgetX + dx;
                                            let rawY = startWidgetY + dy;

                                            let snapInfo = redactorMode.calculateSnap(widgetProxy, rawX, rawY, (mouse.modifiers & Qt.ControlModifier) !== 0);

                                            model.wX = snapInfo.x;
                                            model.wY = snapInfo.y;

                                            redactorMode.presentOverlay(widgetProxy, snapInfo.box, snapInfo);

                                            widgetProxy.triggerSync();
                                            redactorMode.moveCompanions(companions, snapInfo.x - startWidgetX, snapInfo.y - startWidgetY);
                                        }
                                    }

                                    onReleased: endDrag()

                                    onCanceled: endDrag()
                                }

                                Item {
                                    id: rotatableContainer
                                    z: 1
                                    width: model.wWidth
                                    height: model.wHeight
                                    anchors.centerIn: parent
                                    rotation: widgetProxy.wRotation

                                    Loader {
                                        id: preview
                                        property string wImagePath: widgetProxy.wImagePath
                                        property string imagePath: widgetProxy.wImagePath
                                        property string path: widgetProxy.wImagePath
                                        anchors.fill: parent
                                        opacity: widgetProxy.isSelected ? Math.max(0.35, widgetProxy.wOpacity) : widgetProxy.wOpacity
                                        source: WidgetRegistry.faceFile(widgetProxy.wType, widgetProxy.wVariant)
                                        onLoaded: {
                                            if (item) {
                                                try {
                                                    item.visible = Qt.binding(() => redactorWindow.visible);
                                                    if (item.imagePath !== undefined) {
                                                        item.imagePath = Qt.binding(() => widgetProxy.wImagePath);
                                                    }
                                                    if (item.wImagePath !== undefined) {
                                                        item.wImagePath = Qt.binding(() => widgetProxy.wImagePath);
                                                    }
                                                    if (item.path !== undefined) {
                                                        item.path = Qt.binding(() => widgetProxy.wImagePath);
                                                    }
                                                    if (item.source !== undefined && typeof item.source === "string") {
                                                        item.source = Qt.binding(() => widgetProxy.wImagePath);
                                                    }
                                                } catch (e) {}

                                                let activeModel = redactorMode.activeWidgetsModel;
                                                let row = (activeModel && widgetProxy.wIndex >= 0 && widgetProxy.wIndex < activeModel.count) ? activeModel.get(widgetProxy.wIndex) : null;
                                                if (row) {
                                                    let standardKeys = WidgetRegistry.standardKeys || [
                                                        "wType", "wVariant", "wX", "wY", "wWidth", "wHeight",
                                                        "wOpacity", "wRotation", "wImagePath", "wId"
                                                    ];
                                                    let ignoredProps = [
                                                        "objectName", "destroyed", "deleteLater", "parent", "data",
                                                        "resources", "children", "visible", "enabled", "x", "y", "z",
                                                        "width", "height", "opacity", "rotation", "scale"
                                                    ];
                                                    for (let k in row) {
                                                        if (!k || typeof k !== "string") continue;
                                                        if (k.endsWith("Changed") || k.startsWith("on") || typeof row[k] === "function" || row[k] === undefined) continue;
                                                        if (ignoredProps.includes(k) || standardKeys.includes(k)) continue;
                                                        try {
                                                            if (item[k] !== undefined && item[k] !== row[k]) {
                                                                item[k] = row[k];
                                                            }
                                                        } catch (e) {}
                                                    }
                                                }
                                                let res = redactorMode.gridEnabled
                                                    ? redactorMode.snapBoxToGrid(item, model.wX, model.wY, model.wWidth, model.wHeight)
                                                    : redactorMode.clampResize(item, model.wWidth, model.wHeight, 0, 0, true);

                                                let changed = false;
                                                if (res.x !== undefined && (model.wX !== res.x || model.wY !== res.y)) {
                                                    model.wX = res.x;
                                                    model.wY = res.y;
                                                    changed = true;
                                                }
                                                if (res.w !== model.wWidth || res.h !== model.wHeight) {
                                                    model.wWidth = res.w;
                                                    model.wHeight = res.h;
                                                    changed = true;
                                                }
                                                if (changed && !redactorMode.isInitializing) {
                                                    widgetProxy.triggerSync();
                                                }
                                            }
                                        }
                                    }

                                    Item {
                                        id: selectionUI
                                        z: 30
                                        anchors.fill: parent
                                        anchors.margins: -widgetProxy.selectionGap
                                        opacity: widgetProxy.isSelected ? 1.0 : 0.0
                                        visible: opacity > 0
                                        Behavior on opacity { NumberAnimation { duration: 150 } }

                                        property bool isAspectLocked: preview.item && preview.item.minAspect !== undefined && preview.item.maxAspect !== undefined && preview.item.minAspect === preview.item.maxAspect && preview.item.minAspect > 0
                                        readonly property bool isRotated90: Math.abs(Math.round(widgetProxy.wRotation || 0)) % 180 !== 0

                                        SelectionOutline {
                                            anchors.fill: parent
                                            lineWidth: 2 * widgetProxy.inv
                                            amplitude: 0.9 * widgetProxy.inv
                                            running: widgetProxy.isSelected && selectionUI.opacity > 0.001
                                        }

                                        MouseArea {
                                            id: resizeTl
                                            z: 20
                                            width: hs(24); height: hs(24)
                                            anchors.left: parent.left; anchors.top: parent.top
                                            anchors.margins: -hs(6)
                                            enabled: preview.status === Loader.Ready && widgetProxy.isSelected
                                            hoverEnabled: true
                                            preventStealing: true
                                            cursorShape: selectionUI.isRotated90 ? Qt.SizeBDiagCursor : Qt.SizeFDiagCursor

                                            property real startMouseX
                                            property real startMouseY
                                            property real startWidth
                                            property real startHeight
                                            property real startWidgetX
                                            property real startWidgetY

                                            onPressed: (mouse) => {
                                                widgetProxy.bringToFront();
                                                let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                                startMouseX = localPos.x;
                                                startMouseY = localPos.y;
                                                startWidth = model.wWidth;
                                                startHeight = model.wHeight;
                                                startWidgetX = model.wX;
                                                startWidgetY = model.wY;
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeTl, {left: true, top: true, right: false, bottom: false}, true);
                                                }
                                            }

                                            onReleased: {
                                                widgetProxy.finalizeSync();
                                            }

                                            onCanceled: {
                                                widgetProxy.finalizeSync();
                                            }
                                        }

                                        MouseArea {
                                            id: resizeTr
                                            z: 20
                                            width: hs(24); height: hs(24)
                                            anchors.right: parent.right; anchors.top: parent.top
                                            anchors.margins: -hs(6)
                                            enabled: preview.status === Loader.Ready && widgetProxy.isSelected
                                            hoverEnabled: true
                                            preventStealing: true
                                            cursorShape: selectionUI.isRotated90 ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor

                                            property real startMouseX
                                            property real startMouseY
                                            property real startWidth
                                            property real startHeight
                                            property real startWidgetX
                                            property real startWidgetY

                                            onPressed: (mouse) => {
                                                widgetProxy.bringToFront();
                                                let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                                startMouseX = localPos.x;
                                                startMouseY = localPos.y;
                                                startWidth = model.wWidth;
                                                startHeight = model.wHeight;
                                                startWidgetX = model.wX;
                                                startWidgetY = model.wY;
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeTr, {left: false, top: true, right: true, bottom: false}, true);
                                                }
                                            }

                                            onReleased: {
                                                widgetProxy.finalizeSync();
                                            }

                                            onCanceled: {
                                                widgetProxy.finalizeSync();
                                            }
                                        }

                                        MouseArea {
                                            id: resizeBl
                                            z: 20
                                            width: hs(24); height: hs(24)
                                            anchors.left: parent.left; anchors.bottom: parent.bottom
                                            anchors.margins: -hs(6)
                                            enabled: preview.status === Loader.Ready && widgetProxy.isSelected
                                            hoverEnabled: true
                                            preventStealing: true
                                            cursorShape: selectionUI.isRotated90 ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor

                                            property real startMouseX
                                            property real startMouseY
                                            property real startWidth
                                            property real startHeight
                                            property real startWidgetX
                                            property real startWidgetY

                                            onPressed: (mouse) => {
                                                widgetProxy.bringToFront();
                                                let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                                startMouseX = localPos.x;
                                                startMouseY = localPos.y;
                                                startWidth = model.wWidth;
                                                startHeight = model.wHeight;
                                                startWidgetX = model.wX;
                                                startWidgetY = model.wY;
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeBl, {left: true, top: false, right: false, bottom: true}, true);
                                                }
                                            }

                                            onReleased: {
                                                widgetProxy.finalizeSync();
                                            }

                                            onCanceled: {
                                                widgetProxy.finalizeSync();
                                            }
                                        }

                                        MouseArea {
                                            id: resizeBr
                                            z: 20
                                            width: hs(24); height: hs(24)
                                            anchors.right: parent.right; anchors.bottom: parent.bottom
                                            anchors.margins: -hs(6)
                                            enabled: preview.status === Loader.Ready && widgetProxy.isSelected
                                            hoverEnabled: true
                                            preventStealing: true
                                            cursorShape: selectionUI.isRotated90 ? Qt.SizeBDiagCursor : Qt.SizeFDiagCursor

                                            property real startMouseX
                                            property real startMouseY
                                            property real startWidth
                                            property real startHeight
                                            property real startWidgetX
                                            property real startWidgetY

                                            onPressed: (mouse) => {
                                                widgetProxy.bringToFront();
                                                let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                                startMouseX = localPos.x;
                                                startMouseY = localPos.y;
                                                startWidth = model.wWidth;
                                                startHeight = model.wHeight;
                                                startWidgetX = model.wX;
                                                startWidgetY = model.wY;
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeBr, {left: false, top: false, right: true, bottom: true}, true);
                                                }
                                            }

                                            onReleased: {
                                                widgetProxy.finalizeSync();
                                            }

                                            onCanceled: {
                                                widgetProxy.finalizeSync();
                                            }
                                        }

                                        MouseArea {
                                            id: resizeTop
                                            z: 20
                                            height: hs(16)
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                            anchors.leftMargin: hs(18); anchors.rightMargin: hs(18); anchors.topMargin: -hs(8)
                                            visible: !selectionUI.isAspectLocked
                                            enabled: visible && preview.status === Loader.Ready && widgetProxy.isSelected
                                            hoverEnabled: true
                                            preventStealing: true
                                            cursorShape: selectionUI.isRotated90 ? Qt.SizeHorCursor : Qt.SizeVerCursor

                                            property real startMouseX
                                            property real startMouseY
                                            property real startWidth
                                            property real startHeight
                                            property real startWidgetX
                                            property real startWidgetY

                                            onPressed: (mouse) => {
                                                widgetProxy.bringToFront();
                                                let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                                startMouseX = localPos.x;
                                                startMouseY = localPos.y;
                                                startWidth = model.wWidth;
                                                startHeight = model.wHeight;
                                                startWidgetX = model.wX;
                                                startWidgetY = model.wY;
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeTop, {left: false, top: true, right: false, bottom: false}, false);
                                                }
                                            }

                                            onReleased: {
                                                widgetProxy.finalizeSync();
                                            }

                                            onCanceled: {
                                                widgetProxy.finalizeSync();
                                            }
                                        }

                                        MouseArea {
                                            id: resizeBottom
                                            z: 20
                                            height: hs(16)
                                            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                            anchors.leftMargin: hs(18); anchors.rightMargin: hs(18); anchors.bottomMargin: -hs(8)
                                            visible: !selectionUI.isAspectLocked
                                            enabled: visible && preview.status === Loader.Ready && widgetProxy.isSelected
                                            hoverEnabled: true
                                            preventStealing: true
                                            cursorShape: selectionUI.isRotated90 ? Qt.SizeHorCursor : Qt.SizeVerCursor

                                            property real startMouseX
                                            property real startMouseY
                                            property real startWidth
                                            property real startHeight
                                            property real startWidgetX
                                            property real startWidgetY

                                            onPressed: (mouse) => {
                                                widgetProxy.bringToFront();
                                                let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                                startMouseX = localPos.x;
                                                startMouseY = localPos.y;
                                                startWidth = model.wWidth;
                                                startHeight = model.wHeight;
                                                startWidgetX = model.wX;
                                                startWidgetY = model.wY;
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeBottom, {left: false, top: false, right: false, bottom: true}, false);
                                                }
                                            }

                                            onReleased: {
                                                widgetProxy.finalizeSync();
                                            }

                                            onCanceled: {
                                                widgetProxy.finalizeSync();
                                            }
                                        }

                                        MouseArea {
                                            id: resizeLeft
                                            z: 20
                                            width: hs(16)
                                            anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                                            anchors.topMargin: hs(18); anchors.bottomMargin: hs(18); anchors.leftMargin: -hs(8)
                                            visible: !selectionUI.isAspectLocked
                                            enabled: visible && preview.status === Loader.Ready && widgetProxy.isSelected
                                            hoverEnabled: true
                                            preventStealing: true
                                            cursorShape: selectionUI.isRotated90 ? Qt.SizeVerCursor : Qt.SizeHorCursor

                                            property real startMouseX
                                            property real startMouseY
                                            property real startWidth
                                            property real startHeight
                                            property real startWidgetX
                                            property real startWidgetY

                                            onPressed: (mouse) => {
                                                widgetProxy.bringToFront();
                                                let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                                startMouseX = localPos.x;
                                                startMouseY = localPos.y;
                                                startWidth = model.wWidth;
                                                startHeight = model.wHeight;
                                                startWidgetX = model.wX;
                                                startWidgetY = model.wY;
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeLeft, {left: true, top: false, right: false, bottom: false}, false);
                                                }
                                            }

                                            onReleased: {
                                                widgetProxy.finalizeSync();
                                            }

                                            onCanceled: {
                                                widgetProxy.finalizeSync();
                                            }
                                        }

                                        MouseArea {
                                            id: resizeRight
                                            z: 20
                                            width: hs(16)
                                            anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                                            anchors.topMargin: hs(18); anchors.bottomMargin: hs(18); anchors.rightMargin: -hs(8)
                                            visible: !selectionUI.isAspectLocked
                                            enabled: visible && preview.status === Loader.Ready && widgetProxy.isSelected
                                            hoverEnabled: true
                                            preventStealing: true
                                            cursorShape: selectionUI.isRotated90 ? Qt.SizeVerCursor : Qt.SizeHorCursor

                                            property real startMouseX
                                            property real startMouseY
                                            property real startWidth
                                            property real startHeight
                                            property real startWidgetX
                                            property real startWidgetY

                                            onPressed: (mouse) => {
                                                widgetProxy.bringToFront();
                                                let localPos = mapToItem(workspaceArea, mouse.x, mouse.y);
                                                startMouseX = localPos.x;
                                                startMouseY = localPos.y;
                                                startWidth = model.wWidth;
                                                startHeight = model.wHeight;
                                                startWidgetX = model.wX;
                                                startWidgetY = model.wY;
                                            }

                                            onPositionChanged: (mouse) => {
                                                if (pressed) {
                                                    widgetProxy.applyResize(mouse, startMouseX, startMouseY, startWidth, startHeight, startWidgetX, startWidgetY, resizeRight, {left: false, top: false, right: true, bottom: false}, false);
                                                }
                                            }

                                            onReleased: {
                                                widgetProxy.finalizeSync();
                                            }

                                            onCanceled: {
                                                widgetProxy.finalizeSync();
                                            }
                                        }
                                    }
                                }

                                // Outline of widgets that are selected together with the primary one.
                                Rectangle {
                                    z: 25
                                    anchors.fill: parent
                                    anchors.margins: -widgetProxy.hs(5)
                                    visible: widgetProxy.isMultiSelected
                                    color: Qt.alpha(ThemeBackend.mauve, 0.08)
                                    border.width: Math.max(widgetProxy.hs(2), 0.5)
                                    border.color: ThemeBackend.mauve
                                    radius: ThemeBackend.borderRadius * widgetProxy.inv
                                }

                                WallpaperBlur {
                                    id: chromeBackdrop
                                    standalone: true
                                    opacity: 0
                                    x: bottomChrome.x
                                    y: bottomChrome.y
                                    width: bottomChrome.width * widgetProxy.inv
                                    height: bottomChrome.height * widgetProxy.inv
                                    radius: 0
                                }

                                ColumnLayout {
                                    id: bottomChrome
                                    property Item glassBackdropItem: chromeBackdrop
                                    z: 40
                                    // The proxy is zoomed with the world; the chrome is scaled back so its
                                    // buttons stay usable at any zoom.
                                    scale: widgetProxy.inv
                                    transformOrigin: Item.TopLeft
                                    opacity: (widgetProxy.isSelected && !baseSelectMa.pressed && !toolbar.panelOpen) ? 1.0 : 0.0
                                    visible: opacity > 0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                    spacing: s(6)

                                    Component {
                                        id: defaultAdditionalButtonComponent
                                        IconButton {
                                            id: defBtn
                                            property var settingData: null
                                            size: s(34)
                                            cornerRadius: ThemeBackend.borderRadius
                                            buttonIcon: (defBtn.settingData && defBtn.settingData.icon) ? defBtn.settingData.icon : ""
                                            iconFontSize: s((defBtn.settingData && defBtn.settingData.iconFontSize) ? defBtn.settingData.iconFontSize : 16)
                                            accentColor: redactorMode.resolveThemeColor((defBtn.settingData && defBtn.settingData.accentColor) ? defBtn.settingData.accentColor : "surface0")
                                            textColor: redactorMode.resolveThemeColor((defBtn.settingData && defBtn.settingData.textColor) ? defBtn.settingData.textColor : "mauve")
                                            onClicked: {
                                                if (defBtn.settingData && defBtn.settingData.action) {
                                                    redactorMode.handleAdditionalAction(defBtn.settingData.action, widgetProxy.wIndex, widgetProxy.wId, widgetProxy);
                                                }
                                            }
                                        }
                                    }

                                    readonly property real limitY: (toolbar.opacity > 0.1 && !redactorMode.toolbarObscured) ? toolbar.y : redactorMode.safeHeight

                                    readonly property bool fitsBelow: (widgetProxy.scrY + widgetProxy.scrH + s(8) + implicitHeight + s(8)) <= limitY
                                    readonly property bool fitsAbove: (widgetProxy.scrY - s(8) - implicitHeight - s(8)) >= 0

                                    readonly property bool fitsRight: (widgetProxy.scrX + widgetProxy.scrW + s(8) + implicitWidth + s(8)) <= redactorMode.safeWidth
                                    readonly property bool fitsLeft: (widgetProxy.scrX - s(8) - implicitWidth - s(8)) >= 0

                                    readonly property int calculatedPosMode: {
                                        if (fitsBelow) return 0;
                                        if (fitsAbove) return 1;
                                        if (fitsRight) return 2;
                                        if (fitsLeft) return 3;
                                        return 4;
                                    }

                                    property int posMode: 0

                                    onCalculatedPosModeChanged: {
                                        if (!baseSelectMa.pressed) {
                                            posMode = calculatedPosMode;
                                        }
                                    }

                                    Component.onCompleted: {
                                        posMode = calculatedPosMode;
                                    }

                                    x: {
                                        if (posMode === 2) {
                                            return widgetProxy.width + widgetProxy.selectionGap + s(8) * widgetProxy.inv;
                                        } else if (posMode === 3) {
                                            return -widgetProxy.selectionGap - (implicitWidth + s(8)) * widgetProxy.inv;
                                        } else {
                                            let screenX = widgetProxy.scrX + (widgetProxy.scrW - implicitWidth) / 2;
                                            let clampedScreenX = Math.max(s(8), Math.min(redactorMode.safeWidth - implicitWidth - s(8), screenX));
                                            return (clampedScreenX - widgetProxy.scrX) * widgetProxy.inv;
                                        }
                                    }

                                    y: {
                                        if (posMode === 0) {
                                            return widgetProxy.height + widgetProxy.selectionGap + s(8) * widgetProxy.inv;
                                        } else if (posMode === 1) {
                                            return -widgetProxy.selectionGap - (implicitHeight + s(8)) * widgetProxy.inv;
                                        } else if (posMode === 2 || posMode === 3) {
                                            let screenY = widgetProxy.scrY + (widgetProxy.scrH - implicitHeight) / 2;
                                            let clampedScreenY = Math.max(s(8), Math.min(limitY - implicitHeight - s(8), screenY));
                                            return (clampedScreenY - widgetProxy.scrY) * widgetProxy.inv;
                                        } else {
                                            let screenY = Math.min(limitY - implicitHeight - s(15), Math.max(s(15), widgetProxy.scrY + widgetProxy.scrH - implicitHeight - s(15)));
                                            return (screenY - widgetProxy.scrY) * widgetProxy.inv;
                                        }
                                    }

                                    property var variantsList: WidgetRegistry.variantList(widgetProxy.wType)
                                    property bool hasVariants: variantsList.length > 1

                                    RowLayout {
                                        spacing: s(4)
                                        Layout.alignment: Qt.AlignHCenter

                                        Rectangle {
                                            id: pxReadoutPill
                                            implicitWidth: pxReadoutText.implicitWidth + s(16)
                                            implicitHeight: s(34)
                                            color: pxGlass.active ? "transparent" : ThemeBackend.surface0
                                            radius: ThemeBackend.borderRadius

                                            GlassFill {
                                                id: pxGlass
                                                anchors.fill: parent
                                                radius: parent.radius
                                                tintColor: ThemeBackend.surface0
                                                tintAmount: 0.3
                                            }

                                            Text {
                                                id: pxReadoutText
                                                anchors.centerIn: parent
                                                text: Math.round(model.wWidth) + "x" + Math.round(model.wHeight)
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: s(12)
                                                font.bold: true
                                                color: ThemeBackend.text
                                            }
                                        }

                                        Rectangle {
                                            id: arReadoutPill
                                            implicitWidth: arReadoutText.implicitWidth + s(16)
                                            implicitHeight: s(34)
                                            color: arGlass.active ? "transparent" : ThemeBackend.surface0
                                            radius: ThemeBackend.borderRadius

                                            GlassFill {
                                                id: arGlass
                                                anchors.fill: parent
                                                radius: parent.radius
                                                tintColor: ThemeBackend.surface0
                                                tintAmount: 0.3
                                            }

                                            Text {
                                                id: arReadoutText
                                                anchors.centerIn: parent
                                                text: (model.wWidth / model.wHeight).toFixed(2) + ":1"
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: s(12)
                                                font.bold: true
                                                color: ThemeBackend.text
                                            }
                                        }

                                        Rectangle {
                                            id: pctReadoutPill
                                            implicitWidth: pctReadoutText.implicitWidth + s(16)
                                            implicitHeight: s(34)
                                            color: pctGlass.active ? "transparent" : ThemeBackend.surface0
                                            radius: ThemeBackend.borderRadius

                                            GlassFill {
                                                id: pctGlass
                                                anchors.fill: parent
                                                radius: parent.radius
                                                tintColor: ThemeBackend.surface0
                                                tintAmount: 0.3
                                            }

                                            Text {
                                                id: pctReadoutText
                                                anchors.centerIn: parent
                                                text: {
                                                    let def = widgetProxy.getDefaultSize(preview.item);
                                                    return Math.round((model.wWidth / def.w) * 100) + "%";
                                                }
                                                font.family: ThemeBackend.fontFamily
                                                font.pixelSize: s(12)
                                                font.bold: true
                                                color: ThemeBackend.text
                                            }
                                        }

                                        Repeater {
                                            model: WidgetRegistry.additionalSettings(widgetProxy.wType, "top", widgetProxy.wVariant)
                                            delegate: Loader {
                                                id: settingLoaderTop
                                                Layout.alignment: Qt.AlignVCenter

                                                readonly property var currentSetting: modelData
                                                readonly property var currentProxy: widgetProxy
                                                readonly property var currentModel: (redactorMode.activeWidgetsModel && widgetProxy.wIndex >= 0 && widgetProxy.wIndex < redactorMode.activeWidgetsModel.count) ? redactorMode.activeWidgetsModel.get(widgetProxy.wIndex) : null
                                                readonly property var currentFace: preview.item

                                                sourceComponent: {
                                                    if (modelData.component) return modelData.component;
                                                    if (modelData.sourceComponent) return modelData.sourceComponent;
                                                    if (modelData.source || modelData.file) return null;
                                                    return defaultAdditionalButtonComponent;
                                                }
                                                source: {
                                                    if (modelData.component || modelData.sourceComponent) return "";
                                                    if (modelData.source) return Qt.resolvedUrl(modelData.source);
                                                    if (modelData.file) return Qt.resolvedUrl(modelData.file);
                                                    return "";
                                                }

                                                function setupControl() {
                                                    if (!item) return;
                                                    try { if (item.settingData !== undefined) item.settingData = currentSetting; } catch (e) {}
                                                    try { if (item.typeData !== undefined) item.typeData = WidgetRegistry.types[widgetProxy.wType]; } catch (e) {}
                                                    try { if (item.redactor !== undefined) item.redactor = redactorMode; } catch (e) {}
                                                    try { if (item.proxy !== undefined) item.proxy = currentProxy; } catch (e) {}
                                                    try { if (item.widgetProxy !== undefined) item.widgetProxy = currentProxy; } catch (e) {}
                                                    try { if (item.widgetData !== undefined) item.widgetData = currentModel; } catch (e) {}
                                                    try { if (item.item !== undefined) item.item = currentFace; } catch (e) {}
                                                    try { if (item.widget !== undefined) item.widget = currentFace || currentProxy; } catch (e) {}
                                                    try { if (item.targetWidget !== undefined) item.targetWidget = currentFace || currentProxy; } catch (e) {}
                                                    try { if (item.activeWidgetsModel !== undefined) item.activeWidgetsModel = redactorMode.activeWidgetsModel; } catch (e) {}
                                                }

                                                onLoaded: setupControl()

                                                Connections {
                                                    target: preview
                                                    function onItemChanged() {
                                                        settingLoaderTop.setupControl();
                                                    }
                                                }

                                                Connections {
                                                    target: widgetProxy
                                                    function onWIndexChanged() {
                                                        settingLoaderTop.setupControl();
                                                    }
                                                    function onWVariantChanged() {
                                                        settingLoaderTop.setupControl();
                                                    }
                                                }
                                            }
                                        }

                                        IconButton {
                                            id: rotateBtn
                                            size: s(34)
                                            cornerRadius: ThemeBackend.borderRadius
                                            buttonIcon: "󰑖"
                                            iconFontSize: s(16)
                                            accentColor: ThemeBackend.surface0
                                            textColor: ThemeBackend.text
                                            onClicked: widgetProxy.rotateWidget()
                                        }

                                        IconButton {
                                            id: resetBtn
                                            size: s(34)
                                            cornerRadius: ThemeBackend.borderRadius
                                            buttonIcon: "󰑐"
                                            iconFontSize: s(15)
                                            accentColor: ThemeBackend.surface0
                                            textColor: ThemeBackend.text
                                            onClicked: widgetProxy.resetWidgetSize()
                                        }

                                        DeleteButton {
                                            id: closeBtn
                                            size: s(34)
                                            cornerRadius: ThemeBackend.borderRadius
                                            iconFontSize: s(18)

                                            onClicked: redactorMode.removeWidget(widgetProxy.wId)
                                        }
                                    }

                                    RowLayout {
                                        spacing: s(6)
                                        Layout.alignment: Qt.AlignHCenter

                                        Repeater {
                                            model: WidgetRegistry.additionalSettings(widgetProxy.wType, "bottom", widgetProxy.wVariant)
                                            delegate: Loader {
                                                id: settingLoaderBottom
                                                Layout.alignment: Qt.AlignVCenter

                                                readonly property var currentSetting: modelData
                                                readonly property var currentProxy: widgetProxy
                                                readonly property var currentModel: (redactorMode.activeWidgetsModel && widgetProxy.wIndex >= 0 && widgetProxy.wIndex < redactorMode.activeWidgetsModel.count) ? redactorMode.activeWidgetsModel.get(widgetProxy.wIndex) : null
                                                readonly property var currentFace: preview.item

                                                sourceComponent: {
                                                    if (modelData.component) return modelData.component;
                                                    if (modelData.sourceComponent) return modelData.sourceComponent;
                                                    if (modelData.source || modelData.file) return null;
                                                    return defaultAdditionalButtonComponent;
                                                }
                                                source: {
                                                    if (modelData.component || modelData.sourceComponent) return "";
                                                    if (modelData.source) return Qt.resolvedUrl(modelData.source);
                                                    if (modelData.file) return Qt.resolvedUrl(modelData.file);
                                                    return "";
                                                }

                                                function setupControl() {
                                                    if (!item) return;
                                                    try { if (item.settingData !== undefined) item.settingData = currentSetting; } catch (e) {}
                                                    try { if (item.typeData !== undefined) item.typeData = WidgetRegistry.types[widgetProxy.wType]; } catch (e) {}
                                                    try { if (item.redactor !== undefined) item.redactor = redactorMode; } catch (e) {}
                                                    try { if (item.proxy !== undefined) item.proxy = currentProxy; } catch (e) {}
                                                    try { if (item.widgetProxy !== undefined) item.widgetProxy = currentProxy; } catch (e) {}
                                                    try { if (item.widgetData !== undefined) item.widgetData = currentModel; } catch (e) {}
                                                    try { if (item.item !== undefined) item.item = currentFace; } catch (e) {}
                                                    try { if (item.widget !== undefined) item.widget = currentFace || currentProxy; } catch (e) {}
                                                    try { if (item.targetWidget !== undefined) item.targetWidget = currentFace || currentProxy; } catch (e) {}
                                                    try { if (item.activeWidgetsModel !== undefined) item.activeWidgetsModel = redactorMode.activeWidgetsModel; } catch (e) {}
                                                }

                                                onLoaded: setupControl()

                                                Connections {
                                                    target: preview
                                                    function onItemChanged() {
                                                        settingLoaderBottom.setupControl();
                                                    }
                                                }

                                                Connections {
                                                    target: widgetProxy
                                                    function onWIndexChanged() {
                                                        settingLoaderBottom.setupControl();
                                                    }
                                                    function onWVariantChanged() {
                                                        settingLoaderBottom.setupControl();
                                                    }
                                                }
                                            }
                                        }

                                        Dropdown {
                                            id: variantDropdown
                                            property var variantsList: bottomChrome.variantsList
                                            visible: bottomChrome.hasVariants
                                            implicitHeight: s(34)
                                            implicitWidth: s(150)
                                            accentColor: ThemeBackend.mauve
                                            baseColor: ThemeBackend.surface0
                                            dropdownColor: ThemeBackend.base
                                            borderColor: ThemeBackend.surface1
                                            textColor: ThemeBackend.text
                                            activeTextColor: ThemeBackend.crust
                                            cornerRadius: ThemeBackend.borderRadius
                                            fontPixelSize: s(11)
                                            fuzzySearch: false
                                            options: variantsList.map(v => v.label || v.id)

                                            function updateCurrentIndex() {
                                                let curVar = widgetProxy.wVariant;
                                                for (let i = 0; i < variantsList.length; i++) {
                                                    if (variantsList[i].id === curVar) {
                                                        currentIndex = i;
                                                        break;
                                                    }
                                                }
                                            }

                                            Component.onCompleted: updateCurrentIndex()

                                            Connections {
                                                target: widgetProxy
                                                function onWVariantChanged() {
                                                    variantDropdown.updateCurrentIndex();
                                                }
                                            }

                                            onSelected: (idx, value) => {
                                                if (idx >= 0 && idx < variantsList.length) {
                                                    widgetProxy.applyVariant(variantsList[idx].id);
                                                }
                                            }
                                        }

                                        Rectangle {
                                            id: opacityPill
                                            implicitWidth: bottomChrome.hasVariants ? s(200) : s(280)
                                            implicitHeight: s(34)
                                            color: opacityGlass.active ? "transparent" : ThemeBackend.surface0
                                            radius: ThemeBackend.borderRadius

                                            GlassFill {
                                                id: opacityGlass
                                                anchors.fill: parent
                                                radius: parent.radius
                                                tintColor: ThemeBackend.surface0
                                                tintAmount: 0.3
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: s(10)
                                                anchors.rightMargin: s(10)
                                                spacing: s(8)

                                                Text {
                                                    id: opReadoutText
                                                    text: Math.round(widgetProxy.wOpacity * 100) + "%"
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: s(11)
                                                    font.bold: true
                                                    color: ThemeBackend.text
                                                    Layout.preferredWidth: s(32)
                                                }

                                                Draggable {
                                                    id: opacitySlider
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: s(16)
                                                    Layout.alignment: Qt.AlignVCenter
                                                    from: 0.0
                                                    to: 100.0
                                                    value: Math.round(widgetProxy.wOpacity * 100)
                                                    backgroundColor: ThemeBackend.surface1
                                                    accentColor: ThemeBackend.mauve
                                                    gradColor1: ThemeBackend.mauve
                                                    gradColor2: Qt.lighter(ThemeBackend.mauve, 1.05)
                                                    gradColor3: Qt.lighter(ThemeBackend.mauve, 1.10)
                                                    cornerRadius: ThemeBackend.borderRadius
                                                    handleSize: s(16)
                                                    handleColor: Qt.lighter(ThemeBackend.mauve, 1.15)
                                                    handleHoverColor: Qt.lighter(ThemeBackend.mauve, 1.3)
                                                    handleDragColor: Qt.lighter(ThemeBackend.mauve, 1.45)
                                                    handleBorderColor: Qt.rgba(0, 0, 0, 0.2)
                                                    showValueBubble: false

                                                    Connections {
                                                        target: widgetProxy
                                                        function onWOpacityChanged() {
                                                            opacitySlider.value = Math.round(widgetProxy.wOpacity * 100);
                                                        }
                                                    }

                                                    onMoved: val => {
                                                        model.wOpacity = val / 100.0;
                                                        widgetProxy.triggerSync();
                                                    }

                                                    onDragFinished: {
                                                        widgetProxy.finalizeSync();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        anchors.centerIn: parent
                        visible: redactorMode.isReady && (redactorMode.activeWidgetsModel ? redactorMode.activeWidgetsModel.count === 0 : true)
                        width: s(400)
                        height: s(100)

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: s(8)

                            Text {
                                text: I18n.t("widgets.redactor.no_widgets_active")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: s(20)
                                font.bold: true
                                color: ThemeBackend.text
                                Layout.alignment: Qt.AlignHCenter
                            }
                            Text {
                                text: I18n.t("widgets.redactor.click_to_add")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: s(14)
                                color: ThemeBackend.subtext0
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    FileView {
                        id: layoutFile
                        path: (Caching.getStateDir && redactorWindow.safeMonitorName) ? (Caching.getStateDir("widgets/" + redactorWindow.safeMonitorName) + "/layout.json") : ""
                        watchChanges: false
                        onLoaded: redactorMode.loadLayoutFromText(text())
                    }

                    function loadLayoutFromText(content) {
                        let trimmed = (content || "").trim();
                        activeWidgetsModel.clear();
                        redactorMode.isInitializing = true;
                        if (trimmed !== "" && trimmed !== "[]") {
                            try {
                                let data = JSON.parse(trimmed);
                                redactorMode.topZ = data.length + 10;
                                for (let i = 0; i < data.length; i++) {
                                    let item = data[i];
                                    let type = item.wType || item.type || "time";
                                    let variant = item.wVariant || item.variant || WidgetRegistry.defaultVariant(type);
                                    let sVal = item.wScale !== undefined ? parseFloat(item.wScale) : 1.0;
                                    let defSize = WidgetRegistry.defaultSize(type);
                                    let defW = defSize.w;
                                    let defH = defSize.h;
                                    let w = item.wWidth !== undefined ? parseFloat(item.wWidth) : defW * sVal;
                                    let h = item.wHeight !== undefined ? parseFloat(item.wHeight) : defH * sVal;
                                    let op = item.wOpacity !== undefined ? parseFloat(item.wOpacity) : 1.0;
                                    let rot = (item.wRotation !== undefined) ? parseFloat(item.wRotation) : (item.rotation !== undefined ? parseFloat(item.rotation) : 0);
                                    if (isNaN(rot)) rot = 0;
                                    rot = ((Math.round(rot) % 360) + 360) % 360;
                                    let imgPath = item.wImagePath || item.imagePath || item.path || "";

                                    let x = item.wX !== undefined ? parseFloat(item.wX) : 100;
                                    let y = item.wY !== undefined ? parseFloat(item.wY) : 100;
                                    if (item.anchor && redactorWindow.targetScreen) {
                                        const output = redactorWindow.targetScreen;
                                        if (item.stretchWidth) w = output.width;
                                        if (item.stretchHeight) h = output.height;
                                        const position = WidgetRegistry.resolvePosition(item, output.width, output.height, w, h);
                                        x = position.x;
                                        y = position.y;
                                    }

                                    let entry = {
                                        wType: type,
                                        wVariant: variant,
                                        wX: x,
                                        wY: y,
                                        wWidth: w,
                                        wHeight: h,
                                        wOpacity: op,
                                        wRotation: rot,
                                        wImagePath: imgPath,
                                        wId: String(item.wId || item.id || ("w_" + Date.now() + "_" + i))
                                    };

                                    for (let key in item) {
                                        if (entry[key] === undefined && !WidgetRegistry.standardKeys.includes(key)) {
                                            entry[key] = item[key];
                                        }
                                    }

                                    activeWidgetsModel.append(entry);
                                }
                            } catch (e) {}
                        }
                        redactorMode.isReady = true;
                        redactorMode.resetHistory();
                        redactorMode.refreshCanvasWidgets();
                        if (redactorMode.canvasOn) redactorMode.gridEnabled = !!redactorMode.canvasCfg.snapToGrid;
                        if (redactorMode.selectedId !== "") redactorMode.multiIds = redactorMode.groupMates(redactorMode.selectedId);
                        redactorMode.updateToolbarObscured();
                        initTimer.restart();
                    }

                    Timer {
                        id: initTimer
                        interval: 200
                        repeat: false
                        onTriggered: redactorMode.isInitializing = false
                    }

                    function reloadLayout() {
                        layoutFile.reload();
                    }

                    Connections {
                        target: redactorWindow
                        function onSafeMonitorNameChanged() {
                            redactorMode.reloadLayout();
                        }
                    }

                    Component.onCompleted: {
                        let envData = Quickshell.env("QS_WIDGET_DATA") || Quickshell.env("QS_LAYOUT_DATA") || Quickshell.env("QS_LAYOUT_JSON");
                        if (envData && envData.trim() !== "") {
                            redactorMode.loadLayoutFromText(envData);
                        }
                    }

                    WidgetPicker {
                        id: toolbar
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: s(24)
                        anchors.horizontalCenter: parent.horizontalCenter
                        z: 200000
                        maxWidth: redactorMode.width - s(48)
                        redactor: redactorMode

                        opacity: (toolbar.panelOpen || !redactorMode.activeWidgetsModel || redactorMode.activeWidgetsModel.count === 0 || redactorMode.selectedId === "" || !redactorMode.toolbarObscured) ? 1.0 : 0.0
                        visible: opacity > 0
                        enabled: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                        IconButton {
                            size: toolbar.controlHeight
                            cornerRadius: ThemeBackend.borderRadius
                            buttonIcon: "󰕰"
                            iconFontSize: s(16)
                            accentColor: redactorMode.gridEnabled ? ThemeBackend.mauve : ThemeBackend.surface0
                            textColor: redactorMode.gridEnabled ? ThemeBackend.crust : ThemeBackend.text
                            Layout.alignment: Qt.AlignVCenter

                            onClicked: {
                                let turningOn = !redactorMode.gridEnabled;
                                redactorMode.gridEnabled = turningOn;
                                if (redactorMode.canvasOn) CanvasState.setValue(redactorWindow.safeMonitorName, "snapToGrid", turningOn);
                                if (turningOn) {
                                    redactorMode.snapAllWidgetsToGrid();
                                }
                            }
                        }

                        IconButton {
                            size: toolbar.controlHeight
                            cornerRadius: ThemeBackend.borderRadius
                            buttonIcon: "󰑐"
                            iconFontSize: s(16)
                            accentColor: ThemeBackend.surface0
                            textColor: ThemeBackend.text
                            Layout.alignment: Qt.AlignVCenter
                            visible: redactorMode.activeWidgetsModel ? (redactorMode.activeWidgetsModel.count > 0) : false
                            onClicked: redactorMode.removeAllWidgets()
                        }

                        ClickButton {
                            Layout.alignment: Qt.AlignVCenter
                            maxWidth: s(100)
                            implicitHeight: toolbar.controlHeight
                            horizontalPadding: s(14)
                            cornerRadius: ThemeBackend.borderRadius
                            buttonText: I18n.t("widgets.redactor.done")
                            textFontSize: s(12)
                            accentColor: ThemeBackend.mauve
                            textColor: ThemeBackend.crust
                            onClicked: {
                                redactorMode.selectedId = "";
                                root.targetSelectedWidgetId = "";
                                redactorWindow.exitRedactor();
                            }
                        }
                    }

                    // Rubber band selection (screen space).
                    Rectangle {
                        z: 150000
                        visible: redactorMode.marquee !== null
                        x: redactorMode.marquee ? redactorMode.marquee.x : 0
                        y: redactorMode.marquee ? redactorMode.marquee.y : 0
                        width: redactorMode.marquee ? redactorMode.marquee.w : 0
                        height: redactorMode.marquee ? redactorMode.marquee.h : 0
                        color: Qt.alpha(ThemeBackend.mauve, 0.12)
                        border.width: 1
                        border.color: ThemeBackend.mauve
                        radius: 2
                    }

                    CanvasRedactorPanel {
                        id: canvasPanel
                        z: 200000
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: s(24)
                        anchors.rightMargin: s(24)
                        redactor: redactorMode
                        monitorName: redactorWindow.safeMonitorName
                    }

                    Loader {
                        id: imagePickerLoader
                        anchors.fill: parent
                        z: 300000
                        active: false
                        sourceComponent: ImagePicker {
                            rootObj: redactorMode
                            property int targetWidgetIndex: -1
                            property string targetWidgetId: ""

                            onImageSelected: (filePath, fileName) => {
                                let model = redactorMode.activeWidgetsModel;
                                if (targetWidgetIndex >= 0 && targetWidgetId !== "") {
                                    if (model) {
                                        for (let i = 0; i < model.count; i++) {
                                            if (String(model.get(i).wId) === targetWidgetId) {
                                                model.setProperty(i, "wImagePath", filePath);
                                                break;
                                            }
                                        }
                                    }
                                    WidgetSync.setImagePath(redactorWindow.safeMonitorName, targetWidgetId, filePath);
                                    targetWidgetIndex = -1;
                                    targetWidgetId = "";
                                } else if (filePath !== "") {
                                    let def = WidgetRegistry.defaultSize("image");
                                    let defW = def.w;
                                    let defH = def.h;
                                    let spawnX = redactorMode.spawnX(defW);
                                    let spawnY = redactorMode.spawnY(defH);
                                    let newId = "w_" + Date.now() + "_" + Math.floor(Math.random() * 1000);

                                    if (redactorMode.gridEnabled) {
                                        let snapped = redactorMode.snapBoxToGrid(null, spawnX, spawnY, defW, defH);
                                        spawnX = snapped.x;
                                        spawnY = snapped.y;
                                        defW = snapped.w;
                                        defH = snapped.h;
                                    }

                                    let defVar = WidgetRegistry.defaultVariant("image");

                                    if (model) {
                                        model.append({
                                            "wType": "image",
                                            "wVariant": defVar,
                                            "wX": spawnX,
                                            "wY": spawnY,
                                            "wWidth": defW,
                                            "wHeight": defH,
                                            "wOpacity": 1.0,
                                            "wRotation": 0,
                                            "wImagePath": filePath,
                                            "wId": newId
                                        });
                                    }

                                    redactorMode.topZ += 1;
                                    redactorMode.selectedId = newId;
                                    root.targetSelectedWidgetId = newId;
                                    WidgetSync.addWidget(redactorWindow.safeMonitorName, newId, "image", spawnX, spawnY, defW, defH, 1.0, filePath, 0, defVar);
                                    WidgetSync.bringToFront(redactorWindow.safeMonitorName, newId);
                                    redactorMode.updateToolbarObscured();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
