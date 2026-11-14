import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Timer, Atelier: timer / stopwatch / pomodoro from TimerStyledBase (the quick-actions
// timer), with the type, meter and frame of the chosen look.
TimerStyledBase {
    id: root
    clip: true

    property string faceStyle: "technical"
    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }

    readonly property string look: kit.styleId

    AtelierCard {
        id: card
        kit: kit
        title: root.modeNames[root.mode] || I18n.t("quickactions.tabs.timer", "Timer")
        detail: root.phaseText
        showHeader: kit.hasHeader && root.height < Scaler.s(120)
        emphasised: root.running
    }

    ColumnLayout {
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
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
                    text: kit.label(modelData)
                    font.family: kit.labelFamily
                    font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.07))
                    font.letterSpacing: kit.tracking
                    color: index === root.mode ? kit.accent : kit.faint
                    MouseArea { anchors.fill: parent; anchors.margins: -Scaler.s(4); enabled: root.interactive; cursorShape: Qt.PointingHandCursor; onClicked: root.selectMode(index) }
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: root.phaseText !== ""
                text: root.phaseText
                font.family: kit.labelFamily
                font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.07))
                color: kit.muted
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.timeText
            font.family: kit.displayFamily
            font.weight: kit.displayWeight
            font.pixelSize: height
            fontSizeMode: Text.Fit
            minimumPixelSize: 10
            color: root.running ? kit.ink : kit.muted
            horizontalAlignment: root.look === "editorial" || root.look === "technical" ? Text.AlignLeft : Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        AtelierMeter {
            kit: kit
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            value: root.progress
            color: kit.accent
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.height >= Scaler.s(100)
            spacing: Scaler.s(6)
            FaceButton {
                text: root.running ? "Ⅱ" : "▶"; iconFont: ThemeBackend.fontFamily
                primary: true
                lush: root.look === "premium"
                accent: kit.accent
                implicitWidth: Scaler.s(44)
                accessibleName: I18n.t("widgets.timer.startPause", "Start / pause")
                enabled: root.interactive
                onClicked: root.toggle()
            }
            FaceButton {
                text: root.secondaryIcon; iconFont: ThemeBackend.fontFamily
                lush: root.look === "premium"
                implicitWidth: Scaler.s(44)
                accessibleName: root.secondaryName
                enabled: root.interactive
                onClicked: root.secondary()
            }
        }
    }
}
