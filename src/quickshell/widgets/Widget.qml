import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

PanelWindow {
    id: root
    color: "transparent"

    property string wId: Quickshell.env("QS_WIDGET_ID") || "preview"
    property string wType: "time"
    property string wVariant: ""
    property string wImagePath: ""
    property real wX: 0
    property real wY: 0
    property real wWidth: 250
    property real wHeight: 120
    property real wOpacity: 1.0
    property real wRotation: 0

    property var customProps: ({})

    readonly property real auraMargin: 8

    readonly property bool isSelected: typeof DesktopMenuController !== "undefined"
        && DesktopMenuController.isVisible
        && DesktopMenuController.mode === "widget"
        && DesktopMenuController.targetWidgetId === String(root.wId)
        && (!DesktopMenuController.screen || !root.screen || !DesktopMenuController.screen.name || !root.screen.name || DesktopMenuController.screen.name === root.screen.name)

    function applyCustomProps() {
        let it = faceLoader.item;
        if (!it || !customProps) return;
        let ignoredProps = [
            "objectName", "destroyed", "deleteLater", "parent", "data",
            "resources", "children", "visible", "enabled", "x", "y", "z",
            "width", "height", "opacity", "rotation", "scale"
        ];
        for (let k in customProps) {
            if (!k || typeof k !== "string") continue;
            if (k.endsWith("Changed") || k.startsWith("on") || typeof customProps[k] === "function" || customProps[k] === undefined) continue;
            if (ignoredProps.includes(k)) continue;
            try {
                if (it[k] !== undefined && it[k] !== customProps[k]) {
                    it[k] = customProps[k];
                }
            } catch (e) {}
        }
    }

    onCustomPropsChanged: applyCustomProps()

    property bool isRedacting: false
    property bool initialized: false

    property bool wantsKeyboardFocus: false
    readonly property bool effectiveKeyboardFocus: wantsKeyboardFocus || (faceLoader.item && (faceLoader.item.wantsKeyboardFocus || faceLoader.item.keyboardFocus || faceLoader.item.isEditingUser)) || false

    property real animX: wX
    property real animY: wY
    Behavior on animX {
        enabled: root.initialized && !root.isRedacting
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }
    Behavior on animY {
        enabled: root.initialized && !root.isRedacting
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    property real effectiveWidth: wWidth
    property real effectiveHeight: wHeight

    // Infinite canvas. wX / wY are world coordinates; the camera of this monitor
    // decides where that is on screen. Without a camera (or with the canvas
    // disabled) the camera is the home camera and world == screen, exactly as
    // before the canvas existed.
    property var camera: null
    readonly property real camX: camera ? camera.viewX : 0
    readonly property real camY: camera ? camera.viewY : 0
    readonly property real camZoom: camera ? camera.viewZoom : 1

    readonly property bool quarterTurned: Math.round(wRotation || 0) % 180 !== 0
    readonly property real boxWidth: quarterTurned ? effectiveHeight : effectiveWidth
    readonly property real boxHeight: quarterTurned ? effectiveWidth : effectiveHeight

    readonly property real screenX: (animX - camX) * camZoom
    readonly property real screenY: (animY - camY) * camZoom
    readonly property real screenBoxWidth: boxWidth * camZoom
    readonly property real screenBoxHeight: boxHeight * camZoom

    // Entirely outside the monitor. WidgetLoader hides such windows, which also
    // stops their animations and shaders until the camera comes back.
    readonly property real cullMargin: 48
    readonly property bool offCanvas: {
        if (!camera || !screen || !(screen.width > 0) || !(screen.height > 0)) return false;
        return screenX > screen.width + cullMargin
            || screenY > screen.height + cullMargin
            || screenX + screenBoxWidth < -cullMargin
            || screenY + screenBoxHeight < -cullMargin;
    }

    onWWidthChanged: updateEffectiveSize()
    onWHeightChanged: updateEffectiveSize()
    onWVariantChanged: updateEffectiveSize()
    onWTypeChanged: updateEffectiveSize()

    WlrLayershell.namespace: "qs-widget-" + wType + "-" + wId
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: effectiveKeyboardFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    exclusionMode: ExclusionMode.Ignore
    focusable: effectiveKeyboardFocus

    onEffectiveKeyboardFocusChanged: {
        if (effectiveKeyboardFocus && typeof root.requestActivate === "function") {
            root.requestActivate();
        }
    }

    anchors.top: true
    anchors.left: true
    margins.left: screenX - root.auraMargin
    margins.top: screenY - root.auraMargin

    implicitWidth: screenBoxWidth + (root.auraMargin * 2)
    implicitHeight: screenBoxHeight + (root.auraMargin * 2)

    Component.onCompleted: {
        Qt.callLater(() => {
            root.initialized = true;
        });
    }

    Component.onDestruction: {
        visible = false;
        faceLoader.active = false;
        faceLoader.source = "";
    }

    function updateEffectiveSize() {
        if (!faceLoader.item) {
            root.effectiveWidth = root.wWidth;
            root.effectiveHeight = root.wHeight;
            return;
        }
        let item = faceLoader.item;
        let c = {
            minW: item.minWidth !== undefined ? item.minWidth : 10,
            minH: item.minHeight !== undefined ? item.minHeight : 10,
            maxW: item.maxWidth !== undefined ? item.maxWidth : 9999,
            maxH: item.maxHeight !== undefined ? item.maxHeight : 9999,
            minA: item.minAspect !== undefined ? item.minAspect : 0,
            maxA: item.maxAspect !== undefined ? item.maxAspect : 9999
        };
        let w = Math.max(c.minW, Math.min(c.maxW, root.wWidth));
        let h = Math.max(c.minH, Math.min(c.maxH, root.wHeight));

        let ratio = w / h;
        if (ratio < c.minA && c.minA > 0) {
            let mA = c.minA;
            let hProj = (w * mA + h) / (mA * mA + 1);
            let hMin = Math.max(c.minH, c.minW / mA);
            let hMax = Math.min(c.maxH, c.maxW / mA);
            h = Math.max(hMin, Math.min(hMax, hProj));
            w = h * mA;
        } else if (ratio > c.maxA && c.maxA > 0) {
            let mA = c.maxA;
            let hProj = (w * mA + h) / (mA * mA + 1);
            let hMin = Math.max(c.minH, c.minW / mA);
            let hMax = Math.min(c.maxH, c.maxW / mA);
            h = Math.max(hMin, Math.min(hMax, hProj));
            w = h * mA;
        }

        w = Math.max(c.minW, Math.min(c.maxW, w));
        h = Math.max(c.minH, Math.min(c.maxH, h));

        root.effectiveWidth = w;
        root.effectiveHeight = h;
    }

    Loader {
        id: faceLoader
        property string wImagePath: root.wImagePath
        property string imagePath: root.wImagePath
        property string path: root.wImagePath
        // Read by faces that act on the system (terminal, file dock) or save
        // their own state: only a real desktop widget starts shells or writes
        // to its layout. Previews (editor, settings, lock screen) do not set
        // these, so faces stay inert there. Existing faces ignore them.
        readonly property bool liveDesktopWidget: true
        readonly property string widgetId: String(root.wId)
        readonly property string widgetMonitor: root.screen ? String(root.screen.name || "") : ""
        visible: root.visible
        source: WidgetRegistry.faceFile(root.wType, root.wVariant)
        width: root.effectiveWidth
        height: root.effectiveHeight
        anchors.centerIn: parent
        rotation: root.wRotation || 0
        // The face keeps its own size and is scaled as a whole, so every face
        // zooms the same way without knowing about the canvas.
        scale: root.camZoom
        opacity: root.wOpacity
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        onLoaded: {
            if (item) {
                try {
                    item.visible = Qt.binding(() => root.visible);
                    if (item.imagePath !== undefined) {
                        item.imagePath = Qt.binding(() => root.wImagePath);
                    }
                    if (item.wImagePath !== undefined) {
                        item.wImagePath = Qt.binding(() => root.wImagePath);
                    }
                    if (item.path !== undefined) {
                        item.path = Qt.binding(() => root.wImagePath);
                    }
                    if (item.source !== undefined && typeof item.source === "string") {
                        item.source = Qt.binding(() => root.wImagePath);
                    }
                } catch (e) {}
            }
            root.applyCustomProps();
            root.updateEffectiveSize();
        }
    }

    Item {
        id: auraContainer
        width: faceLoader.width * root.camZoom + (root.auraMargin * 2)
        height: faceLoader.height * root.camZoom + (root.auraMargin * 2)
        anchors.centerIn: faceLoader
        rotation: faceLoader.rotation
        visible: opacity > 0.001
        opacity: root.isSelected ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        SelectionOutline {
            anchors.fill: parent
            running: root.isSelected && auraContainer.opacity > 0.001
        }
    }

    MouseArea {
        id: widgetMenuArea
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | (DesktopMenuController.isVisible ? Qt.LeftButton : 0)
        enabled: !root.isRedacting
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                DesktopMenuController.toggle(root.screen, (root.screenX - root.auraMargin) + mouse.x, (root.screenY - root.auraMargin) + mouse.y, "widget", root.wId);
            } else {
                DesktopMenuController.hide();
            }
        }
    }
}
