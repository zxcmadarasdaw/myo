import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"
import "UsageReadings.js" as UsageReadings

// CPU / RAM / temperature / disk, Lush: a glowing gradient ring with the
// figure inside, on ornamented glass that brightens as the load rises.
UsageFaceBase {
    id: root
    minWidth: 120
    minHeight: 100
    minAspect: 0.6
    maxAspect: 3.5

    property string kind: "cpu"     // cpu | ram | temp | disk

    readonly property FaceTone tone: FaceTone {}
    readonly property var reading: UsageReadings.read(root.kind, SysData.cpu, SysData.ramPercent, SysData.ramGb,
                                                      SysData.temp, SysData.diskPercent, SysData.diskGb, SysData.diskTotalGb)
    readonly property bool hot: reading.value >= 0.85
    readonly property color colorA: hot ? ThemeBackend.peach : tone.accent
    readonly property color colorB: hot ? ThemeBackend.red : tone.accent2
    readonly property bool wide: width > height * 1.35
    readonly property real pad: Math.max(Scaler.s(10), Math.min(width, height) * 0.1)

    LushAppear { target: root }

    LushCard {
        anchors.fill: parent
        accent: root.colorA
        accent2: root.colorB
        intensity: 0.45 + root.reading.value * 0.5
        ornate: Math.min(root.width, root.height) >= Scaler.s(110)
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        columns: root.wide ? 2 : 1
        columnSpacing: root.pad
        rowSpacing: Scaler.s(2)

        FaceRing {
            Layout.fillHeight: true
            Layout.fillWidth: !root.wide
            Layout.preferredWidth: root.wide ? height : -1
            Layout.alignment: Qt.AlignHCenter
            lush: true
            value: root.reading.value
            colorA: root.colorA
            colorB: root.colorB
            thickness: Math.max(Scaler.s(4), Math.min(width, height) * 0.085)

            LushGlowText {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.62
                height: width * 0.5
                text: root.reading.text
                font.weight: Font.DemiBold
                font.pixelSize: height
                fontSizeMode: Text.Fit
                minimumPixelSize: 8
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                glowColor: root.tone.isLight ? root.tone.glow : root.colorA
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: root.wide ? Qt.AlignVCenter : Qt.AlignHCenter
            spacing: 0
            visible: root.wide || root.height >= Scaler.s(140)

            Text {
                Layout.fillWidth: true
                horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
                text: root.reading.icon + "  " + I18n.t(root.reading.titleKey, root.reading.title)
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(10), Math.min(Scaler.s(15), root.height * 0.1))
                font.italic: true
                color: root.tone.ink
            }
            Text {
                Layout.fillWidth: true
                visible: root.reading.detail !== ""
                horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
                text: root.reading.detail
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.08))
                font.letterSpacing: Scaler.s(1)
                color: root.tone.muted
            }
        }
    }
}
