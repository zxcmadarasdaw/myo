import QtQuick
import "../../../"

// Level indicator in the look's own form (kit.t.meter):
// line, hair, pill, bar (solid strips); blocks (Retro cells); ticks (Technical scale).
Item {
    id: meter

    property AtelierKit kit: null
    property real value: 0
    property color color: kit ? kit.accent : ThemeBackend.mauve
    property string kind: kit ? kit.t.meter : "line"

    readonly property real shown: Math.max(0, Math.min(1, animated))
    property real animated: value
    Behavior on animated { NumberAnimation { duration: meter.kit ? meter.kit.duration(650) : 0; easing.type: Easing.OutCubic } }

    readonly property color track: kit ? kit.hair : Qt.alpha(ThemeBackend.text, 0.12)
    implicitHeight: kind === "hair" ? 1 : kind === "line" ? Scaler.s(2) : kind === "pill" ? Scaler.s(6)
        : kind === "bar" ? Scaler.s(5) : kind === "blocks" ? Scaler.s(9) : Scaler.s(10)

    // strips
    Rectangle {
        visible: ["line", "hair", "pill", "bar"].indexOf(meter.kind) !== -1
        anchors.fill: parent
        radius: meter.kind === "pill" ? height / 2 : 0
        color: meter.track
        Rectangle {
            width: parent.width * meter.shown
            height: parent.height
            radius: parent.radius
            color: meter.color
        }
    }

    // Retro cells
    Row {
        visible: meter.kind === "blocks"
        anchors.fill: parent
        spacing: Scaler.s(2)
        readonly property int count: Math.max(5, Math.min(24, Math.floor((meter.width + spacing) / Scaler.s(11))))
        Repeater {
            model: meter.kind === "blocks" ? parent.count : 0
            Rectangle {
                required property int index
                readonly property int cells: parent.count
                width: (meter.width - (cells - 1) * Scaler.s(2)) / cells
                height: meter.height
                color: index < Math.round(meter.shown * cells) ? meter.color : "transparent"
                border.width: 1
                border.color: index < Math.round(meter.shown * cells) ? meter.color : meter.track
            }
        }
    }

    // Technical scale
    Row {
        visible: meter.kind === "ticks"
        anchors.fill: parent
        spacing: Scaler.s(2)
        readonly property int count: Math.max(10, Math.min(80, Math.floor((meter.width + spacing) / Scaler.s(4))))
        Repeater {
            model: meter.kind === "ticks" ? parent.count : 0
            Rectangle {
                required property int index
                readonly property int cells: parent.count
                readonly property bool lit: index < Math.round(meter.shown * cells)
                width: Math.max(1, (meter.width - (cells - 1) * Scaler.s(2)) / cells)
                height: index % 5 === 0 ? meter.height : meter.height * 0.6
                anchors.bottom: parent.bottom
                color: lit ? meter.color : meter.track
            }
        }
    }
}
