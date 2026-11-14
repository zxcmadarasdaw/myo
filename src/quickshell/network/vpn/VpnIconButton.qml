import QtQuick
import QtQuick.Layouts
import "../../"

// Square icon button in the VPN page's colours.
Rectangle {
    id: ib
    property string icon: ""
    property string tip: ""
    property bool spinning: false
    property color accent: VpnAppearance.style.text || "#eef1f6"
    signal clicked()

    implicitWidth: Scaler.s(30)
    implicitHeight: Scaler.s(30)
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    radius: Math.min(height / 2, (VpnAppearance.style.radius || 20) * 0.45 + 2)
    opacity: enabled ? 1.0 : 0.4
    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", mouse.pressed ? 0.20 : (mouse.containsMouse ? 0.13 : 0.06))
    border.width: 1
    border.color: Qt.alpha(VpnAppearance.style.border || "#ffffff", 0.10)
    activeFocusOnTab: true
    Behavior on color { ColorAnimation { duration: 140 } }

    Text {
        anchors.centerIn: parent
        text: ib.icon
        visible: !ib.spinning
        font.family: ThemeBackend.iconFont
        font.pixelSize: Math.round(ib.height * 0.46)
        color: ib.accent
    }
    VpnSpinner {
        anchors.centerIn: parent
        size: ib.height * 0.45
        running: ib.spinning
        visible: ib.spinning
        color: VpnAppearance.style.active || "#7fd4ff"
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: ib.radius + 3
        color: "transparent"
        border.width: 1.5
        border.color: Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.8)
        visible: ib.activeFocus
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: ib.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: ib.clicked()
    }
    Keys.onReturnPressed: ib.clicked()
    Keys.onSpacePressed: ib.clicked()
    Accessible.role: Accessible.Button
    Accessible.name: ib.tip
}
