import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../"
import "../common"

// Battery, Lush: a glowing gradient ring with the charge, set on ornamented
// glass. The palette follows the state: green while charging, red when low.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 150
    property real minHeight: 80
    property real maxWidth: 600
    property real maxHeight: 400
    property real minAspect: 0.9
    property real maxAspect: 4.5
    property bool isRound: false

    readonly property FaceTone tone: FaceTone {}
    readonly property bool hasBattery: UPower.displayDevice.ready ? UPower.displayDevice.isLaptopBattery : !SystemInfo.isDesktop
    readonly property int capacity: (UPower.displayDevice.ready && hasBattery) ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property bool charging: hasBattery && UPower.displayDevice.ready
        && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
    readonly property bool low: hasBattery && !charging && capacity <= 20
    readonly property color colorA: charging ? ThemeBackend.green : (low ? ThemeBackend.red : tone.accent)
    readonly property color colorB: charging ? ThemeBackend.teal : (low ? ThemeBackend.peach : tone.accent2)
    readonly property string stateText: !hasBattery ? I18n.t("widgets.battery.none", "No battery")
        : (charging ? I18n.t("widgets.battery.charging", "Charging") : I18n.t("widgets.battery.discharging", "On battery"))
    readonly property real pad: Math.max(Scaler.s(12), Math.min(width, height) * 0.12)

    LushAppear { target: root }

    LushCard {
        anchors.fill: parent
        accent: root.colorA
        accent2: root.colorB
        intensity: root.charging ? 0.9 : 0.6
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.pad * 0.8

        FaceRing {
            Layout.fillHeight: true
            Layout.preferredWidth: height
            lush: true
            value: root.capacity / 100
            colorA: root.colorA
            colorB: root.colorB
            thickness: Math.max(Scaler.s(4), height * 0.09)

            Text {
                anchors.centerIn: parent
                text: root.charging ? "󱐋" : (root.hasBattery ? "󰁹" : "󰚥")
                font.family: ThemeBackend.iconFont
                font.pixelSize: parent.height * 0.26
                color: root.colorA
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            LushGlowText {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: root.hasBattery ? root.capacity + "%" : "—"
                font.weight: Font.DemiBold
                font.pixelSize: height
                fontSizeMode: Text.Fit
                minimumPixelSize: 12
                verticalAlignment: Text.AlignVCenter
                glowColor: root.tone.isLight ? root.tone.glow : root.colorA
            }
            Text {
                Layout.fillWidth: true
                visible: root.height >= Scaler.s(90)
                text: root.stateText
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(9), Math.min(Scaler.s(13), root.height * 0.1))
                font.italic: true
                color: root.tone.muted
            }
        }
    }
}
