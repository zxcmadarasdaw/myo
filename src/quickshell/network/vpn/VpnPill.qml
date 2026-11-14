import QtQuick
import QtQuick.Layouts
import "../../"

// Text button in the VPN page's colours.
Rectangle {
    id: pb
    property string text: ""
    property string icon: ""
    property color accent: VpnAppearance.style.active || "#7fd4ff"
    property bool filled: true
    property bool busy: false
    signal clicked()

    implicitWidth: row.implicitWidth + Scaler.s(26)
    implicitHeight: Scaler.s(32)
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    radius: Math.min(height / 2, (VpnAppearance.style.radius || 20) * 0.6 + 4)
    opacity: enabled ? 1.0 : 0.45
    color: filled ? Qt.alpha(accent, mouse.pressed ? 0.95 : (mouse.containsMouse ? 0.85 : 0.75))
                  : Qt.alpha(accent, mouse.pressed ? 0.30 : (mouse.containsMouse ? 0.20 : 0.12))
    border.width: filled ? 0 : 1
    border.color: Qt.alpha(accent, 0.45)
    scale: mouse.pressed ? 0.97 : 1.0
    activeFocusOnTab: true
    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    readonly property color ink: filled ? (VpnAppearance.style.background || "#0b0d12") : accent

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Scaler.s(6)
        VpnSpinner {
            visible: pb.busy
            running: pb.busy
            size: Scaler.s(12)
            color: pb.ink
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: pb.icon !== "" && !pb.busy
            text: pb.icon
            font.family: ThemeBackend.iconFont
            font.pixelSize: Scaler.s(13)
            color: pb.ink
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: pb.text
            visible: text !== ""
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: Scaler.s(12)
            color: pb.ink
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Rectangle {                                   // keyboard focus ring
        anchors.fill: parent
        anchors.margins: -3
        radius: pb.radius + 3
        color: "transparent"
        border.width: 1.5
        border.color: Qt.alpha(pb.accent, 0.8)
        visible: pb.activeFocus
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: pb.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: pb.clicked()
    }
    Keys.onReturnPressed: pb.clicked()
    Keys.onSpacePressed: pb.clicked()
    Accessible.role: Accessible.Button
    Accessible.name: pb.text
}
