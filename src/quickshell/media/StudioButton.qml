import QtQuick
import QtQuick.Controls
import "../"

Button {
    id: control
    property color accent: ThemeBackend.mauve
    implicitWidth: Math.max(32, contentItem.implicitWidth + 22)
    implicitHeight: 32
    hoverEnabled: true
    opacity: enabled ? 1 : 0.4
    background: Rectangle {
        radius: 9
        color: control.checked ? Qt.alpha(control.accent, 0.23) : (control.hovered ? ThemeBackend.surface1 : ThemeBackend.surface0)
        border.color: control.checked || control.hovered ? Qt.alpha(control.accent, 0.7) : Qt.alpha(control.accent, 0.15)
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    contentItem: Text {
        text: control.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: 12
        color: control.checked ? control.accent : ThemeBackend.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
