import QtQuick
import "../../../"

// Lush level bar: a recessed track, a two-colour gradient fill with a soft
// glow under it and a highlight along the top edge.
Item {
    id: meter

    property real value: 0          // 0..1
    property color colorA: tone.accent
    property color colorB: tone.accent2
    readonly property FaceTone tone: FaceTone {}

    readonly property real shown: Math.max(0, Math.min(1, isNaN(value) ? 0 : value))
    property real animated: shown
    Behavior on animated { NumberAnimation { duration: 900; easing.type: Easing.OutQuint } }

    implicitHeight: Scaler.s(8)
    implicitWidth: Scaler.s(80)

    readonly property real r: height / 2

    Rectangle {
        anchors.fill: parent
        radius: meter.r
        color: Qt.alpha(meter.tone.isLight ? Qt.darker(ThemeBackend.base, 1.15) : ThemeBackend.crust, 0.55)
        border.width: 1
        border.color: meter.tone.hairline
    }

    // glow under the fill
    Rectangle {
        visible: !meter.tone.isLight && meter.animated > 0.01
        x: -Scaler.s(2)
        y: -Scaler.s(2)
        width: Math.max(meter.height, meter.width * meter.animated) + Scaler.s(4)
        height: meter.height + Scaler.s(4)
        radius: height / 2
        color: Qt.alpha(meter.colorB, 0.16)
    }

    Rectangle {
        width: Math.max(meter.height, meter.width * meter.animated)
        height: meter.height
        radius: meter.r
        visible: meter.animated > 0.005
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: meter.colorA }
            GradientStop { position: 1.0; color: meter.colorB }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: Math.max(1, parent.height * 0.35)
            radius: height / 2
            color: Qt.alpha("#ffffff", meter.tone.isLight ? 0.35 : 0.22)
        }
    }
}
