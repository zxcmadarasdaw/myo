import QtQuick
import "../../../reusables"
import "../../../"
import "../common"

// Visualizer, Restrained: hair-thin bars in a quiet colour over a 1 px baseline.
// No card, no glow; bars fall gently.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 50
    property real minHeight: 30
    property real maxWidth: 99999
    property real maxHeight: 99999
    property real minAspect: 0
    property real maxAspect: 99999

    readonly property FaceTone tone: FaceTone {}
    property bool isVisVisible: visible

    MinimalAppear { target: root }

    SubscriptionGate {
        id: spectrumGate
        target: Spectrum
        acquire: "registerConsumer"
        release: "unregisterConsumer"
        wanted: root.isVisVisible
    }

    readonly property real barSpacing: Scaler.s(5)
    readonly property real barWidth: Scaler.s(2)
    readonly property int activeBars: Math.max(4, Math.min(128, Math.floor((width + barSpacing) / (barWidth + barSpacing))))

    Visualizer {
        anchors.fill: parent
        anchors.bottomMargin: Scaler.s(2)
        active: spectrumGate.active
        count: root.activeBars
        spacing: root.barSpacing
        color: root.tone.quietAccent
        maxLength: height * 0.9
        minLength: 1
        radiusRatio: 0.0
        opacityBase: 0.55
        opacityRange: 0.45
        edgeFade: true
        fall: 0.6
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: root.tone.hairline
    }
}
