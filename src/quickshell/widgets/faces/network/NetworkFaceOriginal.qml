import QtQuick
import "../../../reusables"
import "../../../"

// "Original": the bar's network indicator exactly as it looks in the bar
// (icon + network name pill), placed on the desktop. No speeds.
NetworkFaceBase {
    id: root
    minWidth: 90
    minHeight: 30
    maxHeight: 80

    readonly property bool connected: root.hasInterface

    ClickButton {
        id: pill
        anchors.centerIn: parent
        height: Math.min(parent.height, Scaler.s(30))
        maxWidth: parent.width
        cornerRadius: Math.max(0, ThemeBackend.borderRadius - Scaler.s(2))
        horizontalPadding: Scaler.s(12)
        buttonIcon: root.typeIcon
        iconFontSize: Scaler.s(15)
        buttonText: root.connectionName
        textFontSize: Scaler.s(12)
        accentColor: root.connected ? ThemeBackend.blue : ThemeBackend.surface0
        textColor: root.connected ? ThemeBackend.base : ThemeBackend.text
        onClicked: root.openNetworkPanel()
    }
}
