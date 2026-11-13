import QtQuick
import "../../../"

// "Compact Panel": a small pill with both speeds, sized like a bar module.
NetworkFaceBase {
    id: root
    minWidth: 120
    minHeight: 26
    maxHeight: 60

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, row.implicitWidth + Scaler.s(20))
        height: Math.min(parent.height, Scaler.s(30))
        radius: Math.max(0, ThemeBackend.borderRadius - Scaler.s(2))
        color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Scaler.s(8)
            Text { text: root.typeIcon; font.family: ThemeBackend.iconFont; font.pixelSize: Scaler.s(13); color: ThemeBackend.blue; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "󰇚" + root.rxShort; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(11); font.bold: true; color: ThemeBackend.text; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "󰕒" + root.txShort; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(11); font.bold: true; color: ThemeBackend.subtext1; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.isLive
        onClicked: root.cycleInterface()
        onDoubleClicked: root.openNetworkPanel()
    }
}
