import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Clock, Lush: glowing display digits on layered glass, a breathing colon,
// and the weekday framed by fine accent rules.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 140
    property real minHeight: 70
    property real maxWidth: 1400
    property real maxHeight: 700
    property real minAspect: 1.1
    property real maxAspect: 5.0
    property bool isRound: false

    readonly property FaceTone tone: FaceTone {}
    readonly property bool showDate: height >= Scaler.s(100)
    readonly property real pad: Math.max(Scaler.s(12), Math.min(width, height) * 0.14)

    LushAppear { target: root }

    LushCard { anchors.fill: parent; intensity: 0.75 }

    // soft breathing of the colon (InOutSine, no overshoot)
    property real colon: 1
    SequentialAnimation on colon {
        running: root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 1000; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(Scaler.s(2), root.height * 0.03)

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Row {
                id: digits
                anchors.centerIn: parent
                spacing: 0
                readonly property real px: Math.min(parent.height * 0.92, parent.width / 3.1)

                LushGlowText {
                    text: DateTime.hour
                    font.pixelSize: digits.px
                    font.weight: Font.DemiBold
                    glowAmount: 0.9
                }
                LushGlowText {
                    text: ":"
                    font.pixelSize: digits.px
                    font.weight: Font.Light
                    color: root.tone.accent
                    opacity: root.colon
                    glowAmount: 1.0
                }
                LushGlowText {
                    text: DateTime.minute
                    font.pixelSize: digits.px
                    font.weight: Font.DemiBold
                    glowAmount: 0.9
                }
                Text {
                    visible: DateTime.amPm !== ""
                    y: digits.height - height - digits.px * 0.14
                    leftPadding: Scaler.s(4)
                    text: DateTime.amPm
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: digits.px * 0.28
                    color: root.tone.muted
                }
            }
        }

        RowLayout {
            visible: root.showDate
            Layout.fillWidth: true
            spacing: Scaler.s(10)

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.alpha(root.tone.accent, 0.7) }
                }
            }
            Text {
                text: DateTime.dayName
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(10), Math.min(Scaler.s(16), root.height * 0.1))
                font.italic: true
                font.letterSpacing: Scaler.s(1)
                color: root.tone.ink
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.alpha(root.tone.accent2, 0.7) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }

        Text {
            visible: root.showDate
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: DateTime.fullDate
            elide: Text.ElideRight
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Math.max(Scaler.s(9), Math.min(Scaler.s(12), root.height * 0.075))
            font.letterSpacing: Scaler.s(2)
            font.capitalization: Font.AllUppercase
            color: root.tone.muted
        }
    }
}
