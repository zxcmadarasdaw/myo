import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../"
import "../common"

// Battery, Atelier: UPower's display device, as in the other battery faces. On a desktop
// without a battery it says so instead of showing 0 %.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property string faceStyle: "matte"
    property real minWidth: 110
    property real minHeight: 44
    property real maxWidth: 600
    property real maxHeight: 300
    property real minAspect: 1.0
    property real maxAspect: 8.0
    property bool isRound: false

    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }

    readonly property bool hasBattery: UPower.displayDevice.ready ? UPower.displayDevice.isLaptopBattery : !SystemInfo.isDesktop
    readonly property int capacity: (UPower.displayDevice.ready && hasBattery) ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property bool charging: hasBattery && UPower.displayDevice.ready
        && (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
    readonly property color stateColor: !hasBattery ? kit.faint : charging ? ThemeBackend.green : capacity <= 20 ? kit.alarm : kit.accent
    readonly property string stateText: !hasBattery ? I18n.t("widgets.battery.none", "No battery")
        : (charging ? I18n.t("widgets.battery.charging", "Charging") : I18n.t("widgets.battery.discharging", "On battery"))

    AtelierCard {
        id: card
        kit: kit
        title: I18n.t("widgets.types.battery", "Battery")
        detail: root.stateText
        showHeader: kit.hasHeader && root.height >= Scaler.s(90)
        emphasised: root.hasBattery && !root.charging && root.capacity <= 20
    }

    ColumnLayout {
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        spacing: Scaler.s(4)

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Text {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: root.hasBattery ? root.capacity + "<font color='" + kit.faint + "'>%</font>" : "—"
                textFormat: Text.StyledText
                font.family: kit.displayFamily
                font.weight: kit.displayWeight
                font.pixelSize: height
                fontSizeMode: Text.Fit
                minimumPixelSize: 10
                color: kit.ink
                verticalAlignment: Text.AlignVCenter
            }
            Text {
                visible: !card.showHeader && root.width >= Scaler.s(170)
                Layout.alignment: Qt.AlignBottom | Qt.AlignRight
                text: kit.label(root.stateText)
                font.family: kit.labelFamily
                font.pixelSize: Scaler.s(10)
                font.letterSpacing: kit.tracking
                color: kit.muted
            }
        }

        AtelierMeter {
            kit: kit
            visible: root.hasBattery
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            value: root.capacity / 100
            color: root.stateColor
        }
    }
}
