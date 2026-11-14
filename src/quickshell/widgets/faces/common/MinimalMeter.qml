import QtQuick
import "../../../"

// Restrained level indicator: a 1 px track with a 2 px filled segment.
Item {
    id: meter

    property real value: 0          // 0..1
    property color color: tone.quietAccent
    property bool vertical: false
    readonly property FaceTone tone: FaceTone {}

    readonly property real shown: Math.max(0, Math.min(1, isNaN(value) ? 0 : value))

    implicitHeight: vertical ? Scaler.s(40) : Scaler.s(2)
    implicitWidth: vertical ? Scaler.s(2) : Scaler.s(40)

    Rectangle {
        anchors.centerIn: parent
        width: meter.vertical ? 1 : parent.width
        height: meter.vertical ? parent.height : 1
        color: meter.tone.hairline
    }

    Rectangle {
        id: fill
        x: meter.vertical ? (parent.width - width) / 2 : 0
        y: meter.vertical ? parent.height - height : (parent.height - height) / 2
        width: meter.vertical ? Math.max(1, Math.min(2, parent.width)) : parent.width * meter.shown
        height: meter.vertical ? parent.height * meter.shown : Math.max(1, Math.min(2, parent.height))
        color: meter.color
        Behavior on width { enabled: !meter.vertical; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: meter.vertical; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    }
}
