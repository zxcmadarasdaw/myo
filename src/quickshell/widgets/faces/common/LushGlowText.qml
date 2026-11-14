import QtQuick
import QtQuick.Effects
import "../../../"

// Display type for Lush faces: the theme font with a soft coloured glow
// (a dark soft shadow on light themes instead).
Text {
    id: t

    property color glowColor: tone.glow
    property real glowAmount: 0.7
    readonly property FaceTone tone: FaceTone {}

    font.family: ThemeBackend.fontFamily
    color: tone.ink
    renderType: Text.QtRendering

    layer.enabled: glowAmount > 0
    layer.smooth: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: t.glowColor
        shadowBlur: 0.8
        shadowOpacity: Math.min(1, t.glowAmount * (t.tone.isLight ? 0.35 : 0.75))
        shadowHorizontalOffset: 0
        shadowVerticalOffset: t.tone.isLight ? Scaler.s(1) : 0
        autoPaddingEnabled: true
    }
}
