import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Network, Restrained: the connection in small capitals, then download and
// upload as two light figures separated by a 1 px rule. Click: next interface.
NetworkFaceBase {
    id: root
    clip: true
    minWidth: 140
    minHeight: 60

    readonly property FaceTone tone: FaceTone {}
    readonly property real pad: Math.max(Scaler.s(8), Math.min(width, height) * 0.12)
    readonly property bool showHeader: height >= Scaler.s(80)

    MinimalAppear { target: root }

    MinimalCard { anchors.fill: parent }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(Scaler.s(4), root.height * 0.05)

        Text {
            visible: root.showHeader
            Layout.fillWidth: true
            text: (root.connectionName + "  ·  " + root.ifaceName + (root.latencyText !== "" ? "  ·  " + root.latencyText : "")).toUpperCase()
            elide: Text.ElideRight
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.09))
            font.letterSpacing: Scaler.s(1.5)
            color: root.tone.muted
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.pad

            Repeater {
                model: [
                    { icon: "↓", text: root.rxText },
                    { icon: "↑", text: root.txText }
                ]
                RowLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Scaler.s(6)

                    Rectangle {
                        visible: index === 1
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        color: root.tone.hairline
                    }
                    Text {
                        text: modelData.icon
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Math.max(Scaler.s(10), Math.min(Scaler.s(16), root.height * 0.16))
                        color: root.tone.quietAccent
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: modelData.text
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Light
                        font.pixelSize: Math.min(height * 0.8, Scaler.s(28))
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 8
                        color: root.tone.ink
                        verticalAlignment: Text.AlignVCenter
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
