import QtQuick
import QtQuick.Layouts
import "../../../"

// "Minimal Speed": just the two numbers, no card.
NetworkFaceBase {
    id: root
    minWidth: 110
    minHeight: 44

    readonly property real fs: Math.max(Scaler.s(11), Math.min(root.height / 3.2, root.width / 9))

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Scaler.s(2)

        Repeater {
            model: [
                { icon: "󰇚", text: root.rxText, color: ThemeBackend.blue },
                { icon: "󰕒", text: root.txText, color: ThemeBackend.mauve }
            ]
            Row {
                spacing: Scaler.s(6)
                Text {
                    text: modelData.icon
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: root.fs
                    color: modelData.color
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: modelData.text
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.fs
                    font.bold: true
                    color: ThemeBackend.text
                    style: Text.Raised
                    styleColor: Qt.alpha(ThemeBackend.crust, 0.35)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.isLive
        acceptedButtons: Qt.LeftButton
        onClicked: root.cycleInterface()
    }
}
