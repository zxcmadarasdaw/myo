import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Timer, Restrained: three mode words, a light time figure, a 1 px progress
// line and two outline controls.
TimerStyledBase {
    id: root
    clip: true

    readonly property FaceTone tone: FaceTone {}
    readonly property real pad: Math.max(Scaler.s(8), Math.min(width, height) * 0.1)

    MinimalAppear { target: root }

    MinimalCard { anchors.fill: parent; emphasised: root.running }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(Scaler.s(4), root.height * 0.04)

        RowLayout {
            Layout.fillWidth: true
            visible: root.height >= Scaler.s(120)
            spacing: Scaler.s(12)
            Repeater {
                model: root.modeNames
                Text {
                    required property var modelData
                    required property int index
                    text: modelData.toUpperCase()
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.07))
                    font.letterSpacing: Scaler.s(1.5)
                    color: index === root.mode ? root.tone.ink : root.tone.faint
                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.bottom
                        anchors.topMargin: Scaler.s(2)
                        height: 1
                        color: root.tone.quietAccent
                        opacity: index === root.mode ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }
                    MouseArea { anchors.fill: parent; anchors.margins: -Scaler.s(4); enabled: root.interactive; cursorShape: Qt.PointingHandCursor; onClicked: root.selectMode(index) }
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: root.phaseText !== ""
                text: root.phaseText
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.07))
                color: root.tone.muted
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.timeText
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Light
            font.pixelSize: height
            fontSizeMode: Text.Fit
            minimumPixelSize: 10
            font.letterSpacing: Scaler.s(1)
            color: root.running ? root.tone.ink : root.tone.muted
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        MinimalMeter {
            Layout.fillWidth: true
            Layout.preferredHeight: Scaler.s(2)
            value: root.progress
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.height >= Scaler.s(100)
            spacing: Scaler.s(6)
            FaceButton {
                text: root.running ? "Ⅱ" : "▶"; iconFont: ThemeBackend.fontFamily
                primary: true
                implicitWidth: Scaler.s(44)
                accessibleName: I18n.t("widgets.timer.startPause", "Start / pause")
                enabled: root.interactive
                onClicked: root.toggle()
            }
            FaceButton {
                text: root.secondaryIcon; iconFont: ThemeBackend.fontFamily
                implicitWidth: Scaler.s(44)
                accessibleName: root.secondaryName
                enabled: root.interactive
                onClicked: root.secondary()
            }
        }
    }
}
