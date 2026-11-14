import QtQuick
import QtQuick.Effects
import "../../../reusables"
import "../../../"
import "../common"

// Visualizer, Lush: rounded, mirrored bars with a soft accent glow on
// ornamented glass; the card itself brightens with the music's energy.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 120
    property real minHeight: 70
    property real maxWidth: 99999
    property real maxHeight: 99999
    property real minAspect: 0
    property real maxAspect: 99999

    readonly property FaceTone tone: FaceTone {}
    property bool isVisVisible: visible

    LushAppear { target: root }

    SubscriptionGate {
        id: spectrumGate
        target: Spectrum
        acquire: "registerConsumer"
        release: "unregisterConsumer"
        wanted: root.isVisVisible
    }

    LushCard {
        anchors.fill: parent
        ornate: root.height >= Scaler.s(100)
        intensity: 0.45 + Math.min(0.5, bars.energy * 0.6)
    }

    readonly property real pad: Math.max(Scaler.s(10), Math.min(width, height) * 0.12)
    readonly property real barSpacing: Scaler.s(5)
    readonly property real barWidth: Scaler.s(6)
    readonly property int activeBars: Math.max(6, Math.min(96, Math.floor((width - pad * 2 + barSpacing) / (barWidth + barSpacing))))

    Visualizer {
        id: bars
        anchors.fill: parent
        anchors.margins: root.pad
        active: spectrumGate.active
        count: root.activeBars
        spacing: root.barSpacing
        alignment: "center"
        mirrored: true
        color: root.tone.accent
        tintStrength: 0.35
        maxLength: height * 0.96
        minLength: Scaler.s(3)
        radiusRatio: 0.5
        opacityBase: 0.55
        opacityRange: 0.45
        edgeFade: true
        rise: 0.6
        fall: 0.35

        layer.enabled: !root.tone.isLight
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.tone.accent2
            shadowBlur: 0.9
            shadowOpacity: 0.55
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            autoPaddingEnabled: true
        }
    }
}
