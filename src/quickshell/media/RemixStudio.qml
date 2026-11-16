import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../"

ColumnLayout {
    id: remix
    spacing: 8
    property string pendingName: ""
    property var pendingPlayer: null
    property real pendingRate: 1
    property bool applyRate: false
    readonly property var profiles: MusicEffects.remixes || []
    readonly property var profile: profiles[picker.currentIndex] || null
    readonly property bool editable: MusicEffects.available && MusicEffects.eqState.effects && !MusicEffects.eqState.dyneq
    readonly property bool canChangeProfiles: MusicEffects.available && !MusicEffects.busy
    readonly property string destination: nameField.text.trim()

    Text {
        text: qsTr("Live Remix")
        color: ThemeBackend.text
        font.pixelSize: 18
        font.bold: true
    }
    PlaybackSpeed { id: speed; objectName: "studioPlaybackSpeed"; Layout.fillWidth: true }
    Text {
        Layout.fillWidth: true
        text: qsTr("Speed applies to the selected player. Effects apply to streams routed through Serpantinum.")
        color: ThemeBackend.subtext0
        wrapMode: Text.Wrap
        font.pixelSize: 11
    }
    RowLayout {
        Layout.fillWidth: true
        Repeater {
            model: [{key: "bass", bands: [1, 2, 3], name: qsTr("Bass Boost")},
                    {key: "treble", bands: [8, 9, 10], name: qsTr("Treble Boost")}]
            ColumnLayout {
                id: boost
                required property var modelData
                Layout.fillWidth: true
                readonly property real gain: modelData.bands.reduce((sum, band) => sum + MusicEffects.eqState["b" + band], 0) / modelData.bands.length
                StudioButton {
                    Layout.fillWidth: true
                    text: boost.modelData.name
                    checkable: true
                    checked: boost.gain > 0
                    enabled: remix.editable
                    onClicked: {
                        MusicEffects.command(["set_remix_tone", boost.modelData.key, checked ? 3 : 0]);
                        checked = Qt.binding(() => boost.gain > 0);
                    }
                }
                StudioSlider {
                    Layout.fillWidth: true
                    from: 0; to: 4; stepSize: 1
                    value: Math.max(0, Math.min(4, boost.gain))
                    enabled: remix.editable
                    onMoved: MusicEffects.command(["set_remix_tone", boost.modelData.key, Math.round(value)])
                    Accessible.name: boost.modelData.name + " dB"
                }
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        StudioComboBox {
            Layout.fillWidth: true
            model: [qsTr("Dynamics off"), qsTr("Balanced"), qsTr("Night")]
            currentIndex: Math.max(0, ["off", "balanced", "night"].indexOf(MusicEffects.eqState.dynamics))
            enabled: MusicEffects.available && MusicEffects.eqState.effects
            onActivated: index => MusicEffects.command(["set_dynamics", ["off", "balanced", "night"][index]])
        }
        StudioButton {
            text: qsTr("Mono")
            checkable: true
            checked: MusicEffects.eqState.mono === true
            enabled: MusicEffects.available && MusicEffects.eqState.effects
            onClicked: {
                MusicEffects.command(["set_mono", checked]);
                checked = Qt.binding(() => MusicEffects.eqState.mono === true);
            }
        }
        StudioButton {
            text: qsTr("Original")
            enabled: MusicEffects.available || speed.supported
            onClicked: {
                if (MusicEffects.available) MusicEffects.command(["set_effects", "false"]);
                speed.setRate(1);
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        StudioComboBox {
            id: picker
            Layout.fillWidth: true
            model: remix.profiles.map(profile => profile.name)
        }
        StudioButton {
            text: qsTr("Load")
            enabled: remix.canChangeProfiles && !!remix.profile
            onClicked: {
                remix.pendingName = remix.profile.name;
                remix.pendingPlayer = speed.player;
                remix.pendingRate = remix.profile.rate ?? 1;
                remix.applyRate = remix.profile.rate !== null;
                MusicEffects.command(["load_remix", remix.pendingName]);
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: !!remix.profile && remix.profile.rate !== null
        text: remix.profile && remix.profile.rate !== null
              ? (speed.supported && remix.profile.rate >= speed.minimum && remix.profile.rate <= speed.maximum
                 ? qsTr("Saved speed") + " " + remix.profile.rate.toFixed(2) + "×"
                 : qsTr("This player cannot use the speed saved in this remix.")) : ""
        wrapMode: Text.Wrap
        color: ThemeBackend.subtext0
        font.pixelSize: 11
    }
    TextField {
        id: nameField
        Layout.fillWidth: true
        maximumLength: 60
        placeholderText: qsTr("Remix name")
    }
    CheckBox {
        id: rememberSpeed
        text: qsTr("Include current speed in preset")
        enabled: speed.supported && !!speed.player && speed.player.rate >= 0.5 && speed.player.rate <= 2
    }
    Flow {
        Layout.fillWidth: true
        spacing: 5
        StudioButton {
            text: qsTr("Save Preset")
            enabled: remix.canChangeProfiles && remix.destination !== ""
            onClicked: {
                const args = ["save_remix", remix.destination];
                if (rememberSpeed.enabled && rememberSpeed.checked) args.push(speed.player.rate);
                MusicEffects.command(args);
            }
        }
        StudioButton {
            text: qsTr("Rename")
            enabled: remix.canChangeProfiles && remix.profile?.editable === true && remix.destination !== ""
            onClicked: MusicEffects.command(["rename_remix", remix.profile.name, remix.destination])
        }
        StudioButton {
            text: qsTr("Duplicate")
            enabled: remix.canChangeProfiles && !!remix.profile && remix.destination !== ""
            onClicked: MusicEffects.command(["duplicate_remix", remix.profile.name, remix.destination])
        }
        StudioButton {
            text: qsTr("Delete")
            enabled: remix.canChangeProfiles && remix.profile?.editable === true
            onClicked: MusicEffects.command(["delete_remix", remix.profile.name])
        }
        StudioButton {
            text: qsTr("Reset Remix")
            enabled: MusicEffects.available || speed.supported
            onClicked: {
                if (MusicEffects.available) MusicEffects.command(["reset"]);
                speed.setRate(1);
            }
        }
    }
    Connections {
        target: MusicEffects
        ignoreUnknownSignals: true
        function onRemixLoaded(name) {
            if (name !== remix.pendingName) return;
            if (remix.applyRate && remix.pendingPlayer === speed.player)
                speed.setRate(remix.pendingRate);
            remix.pendingName = "";
            remix.pendingPlayer = null;
        }
    }
}
