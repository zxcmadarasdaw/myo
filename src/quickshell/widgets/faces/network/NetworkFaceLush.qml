import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Network, Lush: ornamented glass with a glowing connection badge, the two
// speeds as display figures and a soft live graph along the bottom.
// Click: next interface; double click: the network panel.
NetworkFaceBase {
    id: root
    minWidth: 220
    minHeight: 120

    readonly property FaceTone tone: FaceTone {}
    readonly property real pad: Math.max(Scaler.s(14), Math.min(width, height) * 0.1)
    readonly property bool showGraph: height >= Scaler.s(150)

    LushAppear { target: root }

    LushCard {
        anchors.fill: parent
        intensity: 0.5 + Math.min(0.4, (root.rxSpeed + root.txSpeed) / (4 * 1024 * 1024))
    }

    NetGraph {
        visible: root.showGraph
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Scaler.s(6)
        height: parent.height * 0.32
        opacity: 0.75
        rxData: root.hist.rx
        txData: root.hist.tx
        sampleInterval: root.updateInterval
        rxColor: root.tone.accent2
        txColor: root.tone.accent
        lineWidth: 1.5
        fillOpacity: 0.16
        glow: !root.tone.isLight
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        anchors.bottomMargin: root.showGraph ? root.height * 0.3 : root.pad
        spacing: Scaler.s(6)

        RowLayout {
            Layout.fillWidth: true
            spacing: Scaler.s(10)

            Rectangle {
                Layout.preferredWidth: Scaler.s(34)
                Layout.preferredHeight: Scaler.s(34)
                radius: width / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(root.tone.accent, 0.35) }
                    GradientStop { position: 1.0; color: Qt.alpha(root.tone.accent2, 0.2) }
                }
                border.width: 1
                border.color: Qt.alpha(root.tone.accent, 0.6)
                LushGlowText {
                    anchors.centerIn: parent
                    text: root.typeIcon
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(16)
                    color: root.tone.ink
                    glowAmount: 0.8
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
                    font.pixelSize: Scaler.s(14)
                    font.weight: Font.DemiBold
                    color: root.tone.ink
                }
                Text {
                    Layout.fillWidth: true
                    text: root.ifaceName + (root.latencyText !== "" ? "  ·  " + root.latencyText : "")
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    font.italic: true
                    color: root.tone.muted
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: root.pad

            Repeater {
                model: [
                    { label: I18n.t("widgets.network.download", "Download"), value: root.rxText, total: root.rxTotalText, color: root.tone.accent2 },
                    { label: I18n.t("widgets.network.upload", "Upload"), value: root.txText, total: root.txTotalText, color: root.tone.accent }
                ]
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: modelData.label
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(9)
                        font.letterSpacing: Scaler.s(1.5)
                        font.capitalization: Font.AllUppercase
                        color: modelData.color
                    }
                    LushGlowText {
                        Layout.fillWidth: true
                        text: modelData.value
                        elide: Text.ElideRight
                        font.pixelSize: Math.max(Scaler.s(14), Math.min(Scaler.s(22), root.height * 0.14))
                        font.weight: Font.DemiBold
                        glowColor: root.tone.isLight ? root.tone.glow : modelData.color
                        glowAmount: 0.6
                    }
                    Text {
                        visible: root.showTotals
                        text: "Σ " + modelData.total
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(9)
                        color: root.tone.faint
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
