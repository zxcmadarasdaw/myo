import QtQuick
import "../../../reusables"
import "../../../"
import "../common"

// Visualizer, Atelier: the real Spectrum (CAVA via the shared consumer gate), drawn in
// the look's form. With onlyWhilePlaying the face holds no Spectrum subscription and fades
// out while nothing plays, so the spectrum process is not kept alive for an idle desktop.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property string faceStyle: "minimal"
    property bool onlyWhilePlaying: false
    property real minWidth: 60
    property real minHeight: 30
    property real maxWidth: 99999
    property real maxHeight: 99999
    property real minAspect: 0
    property real maxAspect: 99999

    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }

    readonly property string look: kit.styleId
    readonly property bool sounding: !onlyWhilePlaying || previewMode || MprisController.isPlaying
    readonly property bool framed: look === "retro" || look === "technical" || look === "premium" || look === "matte"

    SubscriptionGate {
        id: spectrumGate
        target: Spectrum
        acquire: "registerConsumer"
        release: "unregisterConsumer"
        wanted: root.visible && root.sounding
    }

    opacity: sounding ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: kit.duration(600); easing.type: Easing.OutCubic } }

    AtelierCard {
        id: card
        visible: root.framed
        kit: kit
        title: "Spectrum"
        showHeader: false
        margin: kit.pad(8)
    }

    readonly property real barWidth: look === "retro" ? Scaler.s(8) : look === "technical" ? Scaler.s(2)
                                    : look === "editorial" ? Scaler.s(6) : look === "premium" ? Scaler.s(4) : Scaler.s(3)
    readonly property real barSpacing: look === "retro" || look === "technical" ? Scaler.s(3) : Scaler.s(4)

    Item {
        id: area
        x: root.framed ? card.contentX : 0
        y: root.framed ? card.contentY : 0
        width: root.framed ? card.contentWidth : root.width
        height: root.framed ? card.contentHeight : root.height

        Visualizer {
            anchors.fill: parent
            anchors.bottomMargin: root.look === "editorial" ? 0 : 1
            active: spectrumGate.active
            count: Math.max(4, Math.min(128, Math.floor((width + root.barSpacing) / (root.barWidth + root.barSpacing))))
            spacing: root.barSpacing
            color: root.look === "premium" ? kit.accent2 : kit.accent
            alignment: root.look === "editorial" ? "center" : "end"
            maxLength: height * (root.look === "editorial" ? 1 : 0.92)
            minLength: root.look === "retro" ? Scaler.s(2) : 1
            radiusRatio: root.look === "premium" || root.look === "elegant" ? 0.5 : 0.0
            opacityBase: root.look === "minimal" || root.look === "borderless" ? 0.55 : 0.8
            opacityRange: 0.2
            edgeFade: root.look !== "retro" && root.look !== "technical"
            fall: root.look === "retro" ? 0.45 : 0.6
        }

        // Retro: cut the bars into cells with lines in the card colour (no shader).
        Repeater {
            model: root.look === "retro" ? Math.floor(area.height / Scaler.s(6)) : 0
            Rectangle {
                required property int index
                y: area.height - (index + 1) * Scaler.s(6)
                width: area.width
                height: Scaler.s(2)
                color: Qt.alpha(ThemeBackend.crust, 0.95)
            }
        }

        Rectangle {
            visible: root.look !== "editorial"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: root.look === "technical" ? Qt.alpha(kit.accent, 0.6) : kit.hair
        }
    }
}
