import QtQuick
import QtQuick.Layouts
import "../"

ColumnLayout {
    id: control
    readonly property var player: MprisController.activePlayer
    readonly property real minimum: MprisController.minimumRate
    readonly property real maximum: MprisController.maximumRate
    readonly property bool supported: MprisController.rateSupported
    readonly property string readout: player && MprisController.finiteRate(player.rate) ? player.rate.toFixed(2) + "×" : "—"
    spacing: 4

    function setRate(rate) {
        return MprisController.setRate(rate);
    }
    Text {
        Layout.fillWidth: true
        text: qsTr("Playback speed") + "  " + control.readout
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
    }
    StudioSlider {
        Layout.fillWidth: true
        enabled: control.supported
        from: enabled ? control.minimum : 1
        to: enabled ? control.maximum : 1
        value: enabled && control.player ? control.player.rate : 1
        stepSize: 0.01
        onMoved: control.setRate(value)
        Accessible.name: qsTr("Playback speed")
    }
    RowLayout {
        Repeater {
            model: [0.75, 1, 1.25, 1.5]
            StudioButton {
                required property real modelData
                text: modelData.toFixed(2) + "×"
                enabled: control.supported && modelData >= control.minimum && modelData <= control.maximum
                onClicked: control.setRate(modelData)
            }
        }
        StudioButton {
            text: qsTr("Reset")
            enabled: control.supported && control.minimum <= 1 && control.maximum >= 1
            onClicked: control.setRate(1)
        }
    }
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: !control.supported ? qsTr("Speed control is unavailable in this player.") : MprisController.rateError
        color: ThemeBackend.subtext0
        wrapMode: Text.Wrap
        font.pixelSize: 11
    }
}
