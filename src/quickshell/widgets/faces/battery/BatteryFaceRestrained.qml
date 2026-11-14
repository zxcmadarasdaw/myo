import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../"
import "../common"

// Battery, Restrained: a light percentage, a 1 px level line and one word
// of state. Low charge turns the line red, charging turns it green.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property real minWidth: 110
    property real minHeight: 50
    property real maxWidth: 600
    property real maxHeight: 300
    property real minAspect: 1.0
    property real maxAspect: 6.0
    property bool isRound: false

    readonly property FaceTone tone: FaceTone {}
    readonly property bool hasBattery: UPower.displayDevice.ready ? UPower.displayDevice.isLaptopBattery : !SystemInfo.isDesktop
    readonly property int capacity: (UPower.displayDevice.ready && hasBattery) ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property bool charging: hasBattery && UPower.displayDevice.ready
        && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
    readonly property color stateColor: !hasBattery ? tone.faint : (charging ? ThemeBackend.green : (capacity <= 20 ? ThemeBackend.red : tone.quietAccent))
    readonly property string stateText: !hasBattery ? I18n.t("widgets.battery.none", "No battery")
        : (charging ? I18n.t("widgets.battery.charging", "Charging") : I18n.t("widgets.battery.discharging", "On battery"))
    readonly property real pad: Math.max(Scaler.s(8), Math.min(width, height) * 0.14)

    MinimalAppear { target: root }

    MinimalCard { anchors.fill: parent }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.max(Scaler.s(3), root.height * 0.05)

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Scaler.s(8)

            Text {
                Layout.fillHeight: true
                Layout.fillWidth: true
                text: root.hasBattery ? root.capacity + "<font color='" + root.tone.faint + "'>%</font>" : "—"
                textFormat: Text.StyledText
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Light
                font.pixelSize: height
                fontSizeMode: Text.Fit
                minimumPixelSize: 10
                color: root.tone.ink
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                visible: root.width >= Scaler.s(160)
                Layout.alignment: Qt.AlignBottom | Qt.AlignRight
                text: root.stateText.toUpperCase()
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(8), Math.min(Scaler.s(11), root.height * 0.12))
                font.letterSpacing: Scaler.s(1.5)
                color: root.tone.muted
            }
        }

        MinimalMeter {
            Layout.fillWidth: true
            Layout.preferredHeight: Scaler.s(2)
            value: root.capacity / 100
            color: root.stateColor
        }
    }
}
