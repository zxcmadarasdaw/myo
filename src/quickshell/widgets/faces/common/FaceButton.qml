import QtQuick
import "../../../"

// Icon/text button for the Restrained and Lush faces.
//   lush: false -> no fill, a 1 px outline on hover, muted text
//   lush: true  -> a soft accent pill with an inner highlight
Item {
    id: btn

    property string text: ""
    property string iconFont: ThemeBackend.iconFont
    property real fontSize: Scaler.s(14)
    property bool lush: false
    property bool primary: false
    property color accent: tone.accent
    property string accessibleName: text
    readonly property bool hovered: area.containsMouse
    readonly property FaceTone tone: FaceTone {}

    signal clicked()

    implicitWidth: Math.max(Scaler.s(28), label.implicitWidth + Scaler.s(14))
    implicitHeight: Scaler.s(28)
    opacity: enabled ? 1 : 0.4

    Accessible.role: Accessible.Button
    Accessible.name: btn.accessibleName

    scale: area.pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: btn.lush ? height / 2 : Math.min(Scaler.s(3), ThemeBackend.clampedBorderRadius)
        antialiasing: true
        color: btn.lush
            ? Qt.alpha(btn.primary ? btn.accent : ThemeBackend.text, btn.primary ? (btn.hovered ? 0.42 : 0.3) : (btn.hovered ? 0.14 : 0.07))
            : (btn.primary ? Qt.alpha(ThemeBackend.text, btn.hovered ? 0.1 : 0.05) : "transparent")
        border.width: 1
        border.color: btn.lush
            ? Qt.alpha(btn.primary ? btn.accent : btn.tone.sheen, btn.primary ? 0.65 : (btn.tone.isLight ? 0.4 : 0.12))
            : (btn.hovered || btn.primary ? btn.tone.hairlineStrong : "transparent")
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: btn.text
        font.family: btn.iconFont
        font.pixelSize: btn.fontSize
        color: btn.lush ? btn.tone.ink : (btn.hovered || btn.primary ? btn.tone.ink : btn.tone.muted)
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
