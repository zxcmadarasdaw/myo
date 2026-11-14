import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../../../"
import "../../../reusables"

// Lush background, built in layers:
//   1. a soft halo just outside the card (stays inside the widget's 8 px aura)
//   2. frosted glass (wallpaper blur) when the GPU allows it
//   3. a tinted vertical gradient with two radial accent glows, masked to the
//      rounded card
//   4. an accent rim, an inner highlight line and a top sheen
//   5. optional corner ornaments (LushOrnament)
// All colours come from the theme; light themes get a dark shade instead of a glow.
Item {
    id: lush

    property real radius: Math.max(Scaler.s(14), Math.min(Scaler.s(26), ThemeBackend.clampedBorderRadius * 1.6))
    property color accent: tone.accent
    property color accent2: tone.accent2
    property bool ornate: true
    property bool glass: true
    property bool halo: true
    property real bodyOpacity: Math.max(0.55, Math.min(0.86, ThemeBackend.elementOpacity * 0.85))
    // 0..1: how bright the glows are. Faces raise it for "active" states.
    property real intensity: 0.6
    Behavior on intensity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

    readonly property FaceTone tone: FaceTone {}
    readonly property real glowGain: lush.intensity * lush.tone.glowStrength

    // ---- 1. halo ---------------------------------------------------------------------
    Repeater {
        model: lush.halo ? 3 : 0
        Rectangle {
            required property int index
            readonly property real spread: Scaler.s(2) * (index + 1)
            anchors.fill: parent
            anchors.margins: -spread
            radius: lush.radius + spread
            color: "transparent"
            border.width: Scaler.s(2)
            border.color: Qt.alpha(lush.tone.glow, (0.16 - index * 0.045) * lush.glowGain)
            antialiasing: true
        }
    }

    // ---- 2. glass ----------------------------------------------------------------------
    WallpaperBlur {
        anchors.fill: parent
        radius: lush.radius
        visible: lush.glass && GpuCompatibility.blurAllowed
    }

    // ---- 3. body -----------------------------------------------------------------------
    Rectangle {
        id: bodyMask
        anchors.fill: parent
        radius: lush.radius
        visible: false
        layer.enabled: true
        antialiasing: true
    }

    Item {
        id: body
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: bodyMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(Qt.tint(ThemeBackend.base, Qt.alpha(lush.accent, 0.14)), lush.bodyOpacity) }
                GradientStop { position: 0.55; color: Qt.alpha(ThemeBackend.base, lush.bodyOpacity) }
                GradientStop { position: 1.0; color: Qt.alpha(Qt.tint(ThemeBackend.mantle, Qt.alpha(lush.accent2, 0.16)), Math.min(1, lush.bodyOpacity + 0.06)) }
            }
        }

        Shape {
            anchors.fill: parent
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: body.width * 0.12; centerY: -body.height * 0.1
                    focalX: centerX; focalY: centerY
                    centerRadius: Math.max(body.width, body.height) * 0.75
                    focalRadius: 0
                    GradientStop { position: 0.0; color: Qt.alpha(lush.accent, 0.30 * lush.glowGain) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                startX: 0; startY: 0
                PathLine { x: body.width; y: 0 }
                PathLine { x: body.width; y: body.height }
                PathLine { x: 0; y: body.height }
                PathLine { x: 0; y: 0 }
            }
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: body.width * 0.95; centerY: body.height * 1.1
                    focalX: centerX; focalY: centerY
                    centerRadius: Math.max(body.width, body.height) * 0.65
                    focalRadius: 0
                    GradientStop { position: 0.0; color: Qt.alpha(lush.accent2, 0.24 * lush.glowGain) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                startX: 0; startY: 0
                PathLine { x: body.width; y: 0 }
                PathLine { x: body.width; y: body.height }
                PathLine { x: 0; y: body.height }
                PathLine { x: 0; y: 0 }
            }
        }

        // top sheen
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(lush.tone.sheen, lush.tone.isLight ? 0.35 : 0.08) }
                GradientStop { position: 0.38; color: "transparent" }
            }
        }
    }

    // ---- 4. rim ------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        radius: lush.radius
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Qt.tint(lush.tone.hairlineStrong, Qt.alpha(lush.accent, 0.55)), 0.75)
        antialiasing: true
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, lush.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(lush.tone.sheen, lush.tone.isLight ? 0.55 : 0.07)
        antialiasing: true
    }

    // ---- 5. ornaments ------------------------------------------------------------------
    LushOrnament {
        anchors.fill: parent
        visible: lush.ornate && Math.min(lush.width, lush.height) >= Scaler.s(70)
        radius: lush.radius
        color: Qt.alpha(lush.accent, lush.tone.isLight ? 0.55 : 0.5)
    }
}
