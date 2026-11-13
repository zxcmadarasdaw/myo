import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../"
import "../media"
import "MusicDrawerGeometry.js" as Geometry
import "../reusables"

Item {
    id: drawer
    required property var host
    property bool opened: false
    readonly property var options: host.customProps || ({})
    readonly property bool animate: options.musicAnimations !== false && GpuCompatibility.effective.profile !== "Performance"
    readonly property var placement: Geometry.layout(host.screenX, host.screenY,
        host.screenBoxHeight + height, host.screen ? host.screen.width : 1920,
        host.screen ? host.screen.height : 1080, 540)
    readonly property bool opensUp: placement.up
    readonly property real panelHeight: placement.height
    readonly property real panelWidth: placement.width
    property real reveal: opened && host.visible && panelHeight > 0 ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: drawer.animate ? 260 : 0; easing.type: Easing.OutCubic } }
    onVisibleChanged: if (!visible) opened = false
    Rectangle {
        anchors.fill: parent
        radius: height/2
        color: Qt.alpha(ThemeBackend.surface0, strip.hovered ? 0.95 : 0.8)
        border.color: Qt.alpha(ThemeBackend.mauve, strip.hovered ? 0.65 : 0.25)
        Behavior on color { ColorAnimation { duration: drawer.animate ? 120 : 0 } }
        Text { anchors.centerIn: parent; text: drawer.opened ? "──────  ⌃  Audio Studio  ──────" : "──────  ⌄  Audio Studio  ──────"; color: ThemeBackend.text; font.pixelSize: 11 }
        TapHandler { onTapped: drawer.opened = !drawer.opened }
        HoverHandler { id: strip; cursorShape: Qt.PointingHandCursor }
    }
    PanelWindow {
        id: panel
        screen: drawer.host.screen
        visible: drawer.reveal > 0.001 && drawer.host.visible
        color: "transparent"
        focusable: true
        anchors.top: true
        anchors.left: true
        margins.left: drawer.placement.x
        margins.top: drawer.opensUp ? drawer.placement.edge - implicitHeight : drawer.placement.edge
        implicitWidth: drawer.panelWidth
        implicitHeight: Math.max(1, Math.round(drawer.panelHeight * drawer.reveal))
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "qs-music-studio-" + drawer.host.wId
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        Item {
            anchors.fill: parent
            clip: true
            Loader {
                width: parent.width
                height: drawer.panelHeight
                y: drawer.opensUp ? 0 : -(1 - drawer.reveal) * 20
                opacity: drawer.reveal
                active: panel.visible
                source: "../media/MusicPopup.qml"
                onLoaded: {
                    item.studioMode = true;
                    item.studioMaterial = Qt.binding(() => String(drawer.options.musicMaterial || "liquid"));
                    item.studioAnimations = Qt.binding(() => drawer.animate);
                    item.studioVisualizer = Qt.binding(() => drawer.options.musicVisualizer === true);
                    item.visible = true;
                    item.closeStudioRequested.connect(() => drawer.opened = false);
                }
            }
            Shortcut { sequence: "Escape"; enabled: panel.visible; onActivated: drawer.opened = false }
        }
    }
}
