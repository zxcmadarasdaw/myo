import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Timer, Lush: a glowing gradient ring around a display-set time, mode pills
// above and pill controls below; the glass brightens while running.
TimerStyledBase {
    id: root
    minWidth: 200
    minHeight: 160

    readonly property FaceTone tone: FaceTone {}
    readonly property real pad: Math.max(Scaler.s(12), Math.min(width, height) * 0.08)
    readonly property color colorA: root.mode === 2 && FocusTimer.pomoState !== 0 ? ThemeBackend.green : tone.accent
    readonly property color colorB: root.mode === 2 && FocusTimer.pomoState !== 0 ? ThemeBackend.teal : tone.accent2

    LushAppear { target: root }

    LushCard {
        anchors.fill: parent
        accent: root.colorA
        accent2: root.colorB
        intensity: root.running ? 0.9 : 0.5
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Scaler.s(6)

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Scaler.s(4)
            visible: root.height >= Scaler.s(200)
            Repeater {
                model: root.modeNames
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool current: index === root.mode
                    implicitWidth: modeLabel.implicitWidth + Scaler.s(16)
                    implicitHeight: Scaler.s(22)
                    radius: height / 2
                    color: current ? Qt.alpha(root.colorA, 0.28) : "transparent"
                    border.width: 1
                    border.color: current ? Qt.alpha(root.colorA, 0.65) : root.tone.hairline
                    Behavior on color { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    Text {
                        id: modeLabel
                        anchors.centerIn: parent
                        text: modelData
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: parent.current ? root.tone.ink : root.tone.muted
                    }
                    MouseArea { anchors.fill: parent; enabled: root.interactive; cursorShape: Qt.PointingHandCursor; onClicked: root.selectMode(index) }
                }
            }
        }

        FaceRing {
            Layout.fillWidth: true
            Layout.fillHeight: true
            lush: true
            value: root.progress
            colorA: root.colorA
            colorB: root.colorB
            thickness: Math.max(Scaler.s(4), Math.min(width, height) * 0.06)

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.68
                spacing: 0
                LushGlowText {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(parent.width * 0.32, Scaler.s(64))
                    text: root.timeText
                    font.weight: Font.DemiBold
                    font.pixelSize: height
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    glowColor: root.tone.isLight ? root.tone.glow : root.colorA
                    glowAmount: root.running ? 1.0 : 0.5
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.phaseText !== "" ? root.phaseText : root.modeNames[root.mode]
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    font.italic: true
                    color: root.tone.muted
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Scaler.s(8)
            FaceButton {
                lush: true; primary: true
                text: root.running ? "Ⅱ" : "▶"; iconFont: ThemeBackend.fontFamily
                accent: root.colorA
                implicitWidth: Scaler.s(52); implicitHeight: Scaler.s(30)
                accessibleName: I18n.t("widgets.timer.startPause", "Start / pause")
                enabled: root.interactive
                onClicked: root.toggle()
            }
            FaceButton {
                lush: true
                text: root.secondaryIcon; iconFont: ThemeBackend.fontFamily
                implicitWidth: Scaler.s(40); implicitHeight: Scaler.s(30)
                accessibleName: root.secondaryName
                enabled: root.interactive
                onClicked: root.secondary()
            }
        }
    }
}
