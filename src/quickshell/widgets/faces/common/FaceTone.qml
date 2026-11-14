import QtQuick
import "../../../"

// Colours for the Restrained and Lush faces, derived from the current theme
// (ThemeBackend) only. Light themes are detected from the luminance of the
// theme's base colour, so the same face reads well on dark and light themes.
QtObject {
    id: tone

    readonly property real baseLuminance: 0.2126 * ThemeBackend.base.r + 0.7152 * ThemeBackend.base.g + 0.0722 * ThemeBackend.base.b
    readonly property bool isLight: baseLuminance > 0.5

    // text
    readonly property color ink: ThemeBackend.text
    readonly property color muted: ThemeBackend.subtext0
    readonly property color faint: Qt.alpha(ThemeBackend.text, isLight ? 0.5 : 0.42)

    // lines
    readonly property color hairline: Qt.alpha(ThemeBackend.text, isLight ? 0.18 : 0.13)
    readonly property color hairlineStrong: Qt.alpha(ThemeBackend.text, isLight ? 0.32 : 0.26)

    // accents
    readonly property color accent: ThemeBackend.mauve
    readonly property color accent2: ThemeBackend.blue
    readonly property color accent3: ThemeBackend.pink
    // A quiet accent for the Restrained faces: the theme accent pulled toward the text colour.
    readonly property color quietAccent: Qt.tint(ThemeBackend.subtext1, Qt.alpha(ThemeBackend.mauve, 0.45))

    // surfaces
    readonly property color surface: ThemeBackend.base
    readonly property color surfaceDeep: ThemeBackend.mantle
    // Light themes get a soft dark shade instead of a light glow.
    readonly property color glow: isLight ? Qt.darker(ThemeBackend.mauve, 1.9) : ThemeBackend.mauve
    readonly property real glowStrength: isLight ? 0.45 : 1.0
    readonly property color sheen: isLight ? "#ffffff" : Qt.lighter(ThemeBackend.text, 1.2)
}
