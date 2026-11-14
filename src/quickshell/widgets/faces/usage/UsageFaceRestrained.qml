import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"
import "UsageReadings.js" as UsageReadings

// CPU / RAM / temperature / disk, Restrained: a small-caps label, a light
// figure and a 1 px level line. `kind` is set by the per-type files.
UsageFaceBase {
    id: root
    clip: true
    minWidth: 100
    minHeight: 56

    property string kind: "cpu"     // cpu | ram | temp | disk

    readonly property FaceTone tone: FaceTone {}
    readonly property var reading: UsageReadings.read(root.kind, SysData.cpu, SysData.ramPercent, SysData.ramGb,
                                                      SysData.temp, SysData.diskPercent, SysData.diskGb, SysData.diskTotalGb)
    readonly property real pad: Math.max(Scaler.s(8), Math.min(width, height) * 0.12)

    property real shownValue: reading.value
    Behavior on shownValue { enabled: root.visible; NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

    MinimalAppear { target: root }

    MinimalCard {
        anchors.fill: parent
        emphasised: root.reading.value >= 0.9
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(Scaler.s(2), root.height * 0.04)

        RowLayout {
            Layout.fillWidth: true
            visible: !root.compactMode || root.height >= Scaler.s(70)
            Text {
                Layout.fillWidth: true
                text: I18n.t(root.reading.titleKey, root.reading.title).toUpperCase()
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.1))
                font.letterSpacing: Scaler.s(1.5)
                color: root.tone.muted
            }
            Text {
                visible: root.reading.detail !== "" && root.width >= Scaler.s(150)
                text: root.reading.detail
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.1))
                color: root.tone.faint
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.reading.text
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Light
            font.pixelSize: height
            fontSizeMode: Text.Fit
            minimumPixelSize: 10
            color: root.tone.ink
            verticalAlignment: Text.AlignVCenter
        }

        MinimalMeter {
            Layout.fillWidth: true
            Layout.preferredHeight: Scaler.s(2)
            value: root.shownValue
            color: root.reading.value >= 0.9 ? ThemeBackend.red : root.tone.quietAccent
        }
    }
}
