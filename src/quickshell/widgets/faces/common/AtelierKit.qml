import QtQuick
import "../../../"
import "AtelierStyles.js" as Styles

// Tokens of one Atelier look (see AtelierStyles.js), resolved against the current theme.
//   AtelierKit { id: kit; style: root.faceStyle }
// Colours come from ThemeBackend only, so a Themess palette restyles every look.
QtObject {
    id: kit

    property string style: "matte"
    readonly property string styleId: Styles.valid(style) ? style : "matte"
    readonly property var t: Styles.get(styleId)

    // ---- motion ------------------------------------------------------------------------
    // full: entrance, hover and the small looping details; reduced: entrance and hover
    // only; off: nothing moves. Performance mode and the GPU fallback force "off".
    readonly property string motionSetting: {
        const value = Config.getSetting("widgetStudio.motion", "full");
        return ["full", "reduced", "off"].indexOf(value) !== -1 ? value : "full";
    }
    readonly property bool lowPower: Config.getSetting("general.performance", false) === true
        || (typeof GpuCompatibility !== "undefined" && !!GpuCompatibility.effective && GpuCompatibility.effective.fallback === true)
    readonly property string motion: lowPower ? "off" : motionSetting
    readonly property bool loops: motion === "full"
    readonly property bool transitions: motion !== "off"
    function duration(ms) { return transitions ? ms : 0; }

    // ---- colours -----------------------------------------------------------------------
    readonly property real baseLuminance: 0.2126 * ThemeBackend.base.r + 0.7152 * ThemeBackend.base.g + 0.0722 * ThemeBackend.base.b
    readonly property bool isLight: baseLuminance > 0.5
    readonly property color ink: ThemeBackend.text
    readonly property color muted: ThemeBackend.subtext0
    readonly property color faint: Qt.alpha(ThemeBackend.text, isLight ? 0.5 : 0.42)
    readonly property color accent: ThemeBackend.mauve
    readonly property color accent2: ThemeBackend.pink
    readonly property color accent3: ThemeBackend.blue
    readonly property color hair: Qt.alpha(ThemeBackend.text, isLight ? 0.16 : 0.12)
    readonly property color hairStrong: Qt.alpha(ThemeBackend.text, isLight ? 0.3 : 0.24)
    readonly property color surface: t.fillTone === "crust" ? ThemeBackend.crust : ThemeBackend.base
    readonly property color warn: ThemeBackend.peach
    readonly property color alarm: ThemeBackend.red
    function level(value) { return value >= 0.9 ? alarm : value >= 0.75 ? warn : accent; }

    // ---- type --------------------------------------------------------------------------
    readonly property string sans: ThemeBackend.fontFamily
    readonly property string serif: "serif"
    readonly property string mono: "JetBrains Mono"
    function family(kind) { return kind === "serif" ? serif : kind === "mono" ? mono : sans; }
    readonly property string displayFamily: family(t.display)
    readonly property string labelFamily: family(t.label)
    readonly property int displayWeight: t.displayWeight
    function label(text) { return t.caps ? String(text).toUpperCase() : String(text); }
    readonly property real tracking: Scaler.s(t.tracking)

    // ---- geometry ----------------------------------------------------------------------
    readonly property real radius: Scaler.s(t.radius)
    function pad(base) { return Math.round(Scaler.s(base) * t.pad); }
    readonly property bool hasHeader: t.header !== "none"
    readonly property real headerHeight: t.header === "titlebar" ? Scaler.s(22)
        : t.header === "kicker" ? Scaler.s(22) : t.header === "none" ? 0 : Scaler.s(18)
}
