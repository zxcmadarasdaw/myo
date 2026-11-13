import QtQuick
import QtQuick.Controls
import "../"

ComboBox {
    id: control
    implicitHeight: 32
    implicitWidth: 160
    leftPadding: 10
    rightPadding: 28
    opacity: enabled ? 1 : 0.4
    palette.window: ThemeBackend.base
    palette.base: ThemeBackend.surface0
    palette.text: ThemeBackend.text
    palette.buttonText: ThemeBackend.text
    palette.highlight: ThemeBackend.surface1
    palette.highlightedText: ThemeBackend.mauve
    font.family: ThemeBackend.fontFamily
    font.pixelSize: 12
    background: Rectangle { radius: 9; color: ThemeBackend.surface0; border.color: Qt.alpha(ThemeBackend.mauve, control.activeFocus ? 0.8 : 0.2) }
    contentItem: Text {
        text: control.displayText
        color: ThemeBackend.text
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text { x: control.width-22; anchors.verticalCenter: parent.verticalCenter; text: "⌄"; color: ThemeBackend.mauve; font.pixelSize: 16 }
}
