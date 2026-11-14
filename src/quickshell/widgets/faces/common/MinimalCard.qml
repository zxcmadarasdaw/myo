import QtQuick
import "../../../"

// Restrained background: a flat theme surface with a 1 px hairline.
// No shadow, no gradient, no blur; the corner radius stays tiny.
Rectangle {
    id: card

    property bool filled: true
    property real fillOpacity: Math.max(0.42, Math.min(0.78, ThemeBackend.elementOpacity * 0.75))
    property bool emphasised: false
    readonly property FaceTone tone: FaceTone {}

    radius: Math.min(Scaler.s(3), ThemeBackend.clampedBorderRadius)
    color: filled ? Qt.alpha(ThemeBackend.base, fillOpacity) : "transparent"
    border.width: 1
    border.color: emphasised ? tone.hairlineStrong : tone.hairline
    antialiasing: true

    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
}
