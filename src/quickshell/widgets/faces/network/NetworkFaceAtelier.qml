import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Network, Atelier: real /proc/net/dev speeds from the shared NetStats sampler (through
// NetworkFaceBase), a live graph when there is room, totals on request.
// Click: next interface. Double click: Network Control.
NetworkFaceBase {
    id: root
    clip: true
    minWidth: 140
    minHeight: 44

    property string faceStyle: "matte"

    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }

    readonly property string look: kit.styleId
    readonly property bool compact: look === "compact" || height < Scaler.s(90)
    readonly property bool framedGraph: look === "retro" || look === "technical"
    readonly property bool showGraph: !compact && height >= Scaler.s(130)

    AtelierCard {
        id: card
        kit: kit
        title: root.connectionName
        detail: root.ifaceName + (root.latencyText !== "" ? "  ·  " + root.latencyText : "")
        showHeader: kit.hasHeader && !root.compact
    }

    ColumnLayout {
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        spacing: Scaler.s(6)

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: !root.showGraph
            Layout.preferredHeight: root.showGraph ? Math.max(Scaler.s(28), card.contentHeight * 0.32) : -1
            spacing: Scaler.s(14)

            Repeater {
                model: [
                    { down: true, text: root.rxText, short: root.rxShort, total: root.rxTotalText },
                    { down: false, text: root.txText, short: root.txShort, total: root.txTotalText }
                ]
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Scaler.s(6)
                    Text {
                        text: root.framedGraph ? (modelData.down ? "RX" : "TX") : (modelData.down ? "↓" : "↑")
                        font.family: kit.labelFamily
                        font.pixelSize: Math.max(Scaler.s(10), Math.min(Scaler.s(15), card.contentHeight * 0.2))
                        font.letterSpacing: kit.tracking
                        color: modelData.down ? kit.accent3 : kit.accent2
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: root.compact ? modelData.short : modelData.text
                            font.family: kit.displayFamily
                            font.weight: kit.displayWeight
                            font.pixelSize: Math.max(8, Math.min(height * 0.85, Scaler.s(30)))
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 8
                            verticalAlignment: Text.AlignVCenter
                            color: kit.ink
                        }
                        Text {
                            visible: root.showTotals && !root.compact
                            Layout.fillWidth: true
                            text: kit.label(I18n.t("widgets.network.total", "total")) + " " + modelData.total
                            elide: Text.ElideRight
                            font.family: kit.labelFamily
                            font.pixelSize: Scaler.s(9)
                            color: kit.faint
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: root.showGraph
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: root.framedGraph ? Qt.alpha(ThemeBackend.crust, 0.6) : "transparent"
            border.width: root.framedGraph ? 1 : 0
            border.color: kit.hair
            radius: root.framedGraph ? 0 : Scaler.s(4)

            NetGraph {
                anchors.fill: parent
                anchors.margins: parent.border.width + 1
                visible: root.showGraph
                rxData: root.hist.rx
                txData: root.hist.tx
                rxColor: kit.accent3
                txColor: kit.accent2
                lineWidth: root.look === "minimal" || root.look === "elegant" ? 1.2 : 1.8
                fillOpacity: root.look === "borderless" || root.look === "minimal" ? 0.1 : 0.2
                sampleInterval: root.updateInterval
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
