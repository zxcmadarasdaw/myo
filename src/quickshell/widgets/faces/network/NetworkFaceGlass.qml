import QtQuick
import QtQuick.Layouts
import "../../../reusables"
import "../../../"

// "Glass Network": a glass card with the full connection picture.
NetworkFaceBase {
    id: root
    minWidth: 220
    minHeight: 120

    Rectangle {
        id: card
        anchors.fill: parent
        radius: ThemeBackend.clampedBorderRadius
        color: Qt.alpha(ThemeBackend.surface0, ThemeBackend.elementOpacity)
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.text, 0.08)
        clip: true

        WallpaperBlur {
            z: -1
            anchors.fill: parent
            radius: parent.radius
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Scaler.s(14)
        spacing: Scaler.s(6)

        RowLayout {
            Layout.fillWidth: true
            spacing: Scaler.s(10)

            Rectangle {
                Layout.preferredWidth: Scaler.s(34)
                Layout.preferredHeight: Scaler.s(34)
                radius: width / 2
                color: Qt.alpha(ThemeBackend.blue, 0.18)
                Text {
                    anchors.centerIn: parent
                    text: root.typeIcon
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(17)
                    color: ThemeBackend.blue
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: root.connectionName
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(13)
                    font.bold: true
                    color: ThemeBackend.text
                }
                Text {
                    Layout.fillWidth: true
                    text: root.typeLabel + " · " + root.ifaceName + (root.latencyText !== "" ? " · " + root.latencyText : "")
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    color: ThemeBackend.subtext0
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Scaler.s(8)

            Repeater {
                model: [
                    { icon: "󰇚", label: I18n.t("widgets.network.download", "Download"), value: root.rxText, total: root.rxTotalText, color: ThemeBackend.blue },
                    { icon: "󰕒", label: I18n.t("widgets.network.upload", "Upload"), value: root.txText, total: root.txTotalText, color: ThemeBackend.mauve }
                ]
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Row {
                        spacing: Scaler.s(4)
                        Text { text: modelData.icon; font.family: ThemeBackend.iconFont; font.pixelSize: Scaler.s(12); color: modelData.color }
                        Text { text: modelData.label; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(10); color: ThemeBackend.subtext0 }
                    }
                    Text {
                        text: modelData.value
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(16)
                        font.bold: true
                        color: ThemeBackend.text
                    }
                    Text {
                        visible: root.showTotals
                        text: "Σ " + modelData.total
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(9)
                        color: ThemeBackend.subtext0
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.isLive
        acceptedButtons: Qt.LeftButton
        onClicked: root.cycleInterface()
        onDoubleClicked: root.openNetworkPanel()
    }
}
