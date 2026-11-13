import QtQuick
import QtQuick.Controls
import "../"

Slider {
    id: control
    property bool animate: true
    property color accent: ThemeBackend.mauve
    readonly property bool isVertical: orientation === Qt.Vertical
    padding: 8
    hoverEnabled: true
    implicitWidth: isVertical ? 32 : 120
    implicitHeight: isVertical ? 150 : 32
    opacity: enabled ? 1 : 0.35
    Behavior on opacity { NumberAnimation { duration: control.animate ? 150 : 0 } }
    background: Rectangle {
        x: control.isVertical ? (control.width - width)/2 : control.leftPadding
        y: control.isVertical ? control.topPadding : (control.height - height)/2
        width: control.isVertical ? 5 : control.availableWidth
        height: control.isVertical ? control.availableHeight : 5
        radius: 3
        color: ThemeBackend.surface1
        Rectangle {
            anchors.bottom: parent.bottom
            width: control.isVertical ? parent.width : parent.width * control.position
            height: control.isVertical ? parent.height * control.position : parent.height
            radius: 3
            color: control.accent
            Behavior on height { enabled: !control.pressed && control.animate; NumberAnimation { duration: 140 } }
            Behavior on width { enabled: !control.pressed && control.animate; NumberAnimation { duration: 140 } }
        }
    }
    handle: Rectangle {
        x: control.isVertical ? (control.width-width)/2 : control.leftPadding + control.visualPosition * (control.availableWidth-width)
        y: control.isVertical ? control.topPadding + control.visualPosition * (control.availableHeight-height) : (control.height-height)/2
        width: control.isVertical ? 22 : 14
        height: control.isVertical ? 12 : 14
        radius: 5
        color: control.pressed ? control.accent : ThemeBackend.text
        border.color: control.hovered ? control.accent : ThemeBackend.surface2
        Behavior on color { ColorAnimation { duration: control.animate ? 120 : 0 } }
    }
}

