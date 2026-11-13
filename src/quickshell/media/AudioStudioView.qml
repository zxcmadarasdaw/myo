import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../"
import "../reusables"

// Alternate layout of MusicPopup, sharing its state and the existing audio engine.
Item {
    id: studio
    readonly property var playerSource: Mpris
    property string material: "liquid"
    property bool animations: true
    property bool showVisualizer: false
    signal closeRequested()
    readonly property bool animate: animations && GpuCompatibility.effective.profile !== "Performance"
    readonly property bool editable: MusicEffects.available && MusicEffects.eqState.effects && !MusicEffects.eqState.dyneq
    readonly property color accent: material === "neon" ? ThemeBackend.sky : ThemeBackend.mauve
    readonly property bool spectrumActive: visible && showVisualizer && GpuCompatibility.shadersAllowed
    property bool subscribed: false
    function updateSpectrum() {
        if (spectrumActive && !subscribed) { Spectrum.registerConsumer(); subscribed = true; }
        else if (!spectrumActive && subscribed) { Spectrum.unregisterConsumer(); subscribed = false; }
    }
    onSpectrumActiveChanged: updateSpectrum()
    Component.onCompleted: updateSpectrum()
    Component.onDestruction: if (subscribed) Spectrum.unregisterConsumer()

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        color: Qt.alpha(ThemeBackend.base, studio.material === "minimal" ? 0.98 : ThemeBackend.elementOpacity)
        border.color: Qt.alpha(studio.accent, studio.material === "neon" ? 0.7 : 0.25)
        GlassFill { anchors.fill: parent; radius: parent.radius; allowed: studio.material !== "minimal" && studio.material !== "mica"; tintColor: ThemeBackend.base }
        WallpaperBlur { anchors.fill: parent; z: -1; radius: parent.radius; visible: studio.material !== "minimal" && GpuCompatibility.blurAllowed }
    }
    ScrollView {
        id: scroll
        anchors.fill: parent
        anchors.margins: 16
        clip: true
        contentWidth: availableWidth
        ColumnLayout {
            width: scroll.availableWidth
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    Text { text: "Audio Studio"; color: ThemeBackend.text; font.family: ThemeBackend.fontFamily; font.pixelSize: 22; font.bold: true }
                    Text { Layout.fillWidth: true; text: Audio.defaultSink ? Audio.getNodeName(Audio.defaultSink) : "Нет устройства вывода"; color: ThemeBackend.subtext0; elide: Text.ElideRight; font.pixelSize: 11 }
                }
                StudioButton { text: "×"; Accessible.name: "Свернуть Audio Studio"; onClicked: studio.closeRequested() }
            }
            StudioComboBox {
                Layout.fillWidth: true
                property var players: playerSource.players.values
                model: ["Auto · активное воспроизведение"].concat(players.map(p => p.identity || p.dbusName))
                currentIndex: MprisController.selectedBus === "" ? 0 : Math.max(0, players.findIndex(p => p.dbusName === MprisController.selectedBus)+1)
                onActivated: index => MprisController.selectedBus = index > 0 ? players[index-1].dbusName : ""
                Accessible.name: "Активный музыкальный плеер"
            }
            Text {
                objectName: "audioStatus"
                Layout.fillWidth: true
                visible: text.length > 0
                text: MusicEffects.error || MusicEffects.notice
                color: MusicEffects.error ? ThemeBackend.peach : studio.accent
                wrapMode: Text.Wrap
                font.pixelSize: 12
            }
            RowLayout {
                Layout.fillWidth: true
                StudioComboBox {
                    Layout.fillWidth: true
                    objectName: "audioPreset"
                    model: MusicEffects.presets
                    currentIndex: Math.max(0, MusicEffects.presets.indexOf(MusicEffects.eqState.preset))
                    displayText: MusicEffects.eqState.preset
                    enabled: studio.editable
                    onActivated: index => MusicEffects.command(["preset", MusicEffects.presets[index]])
                    Accessible.name: "Аудиопрофиль"
                }
                StudioButton {
                    checkable: true
                    text: "Эффекты"
                    checked: MusicEffects.eqState.effects
                    enabled: MusicEffects.available
                    onClicked: { MusicEffects.command(["set_effects", checked]); checked = Qt.binding(() => MusicEffects.eqState.effects); }
                }
            }
            Text { visible: MusicEffects.eqState.dyneq; text: "Dynamic EQ активен — выключите для ручной настройки"; color: ThemeBackend.subtext0; font.pixelSize: 11 }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "EQUALIZER · ±12 dB"; color: studio.accent; font.pixelSize: 10; font.letterSpacing: 1.5; Layout.fillWidth: true }
                StudioButton {
                    checkable: true
                    text: "Dynamic EQ"
                    checked: MusicEffects.eqState.dyneq
                    enabled: MusicEffects.available && MusicEffects.eqState.effects
                    onClicked: { MusicEffects.command(["set_dyneq", checked]); checked = Qt.binding(() => MusicEffects.eqState.dyneq); }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
                    ColumnLayout {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: scroll.availableWidth / 10
                        Layout.maximumWidth: 10000
                        spacing: 2
                        Text { Layout.alignment: Qt.AlignHCenter; text: Number(MusicEffects.eqState["b"+(index+1)]).toFixed(0); color: studio.accent; font.pixelSize: 10 }
                        StudioSlider {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredHeight: 125
                            objectName: "eqBand" + (index+1)
                            orientation: Qt.Vertical
                            from: -12; to: 12; stepSize: 1
                            value: Number(MusicEffects.eqState["b"+(index+1)])
                            enabled: studio.editable
                            animate: studio.animate; accent: studio.accent
                            onMoved: MusicEffects.command(["set_band", index+1, Math.round(value)])
                            Accessible.name: modelData + " Hz"
                        }
                        Text { Layout.alignment: Qt.AlignHCenter; text: modelData; color: ThemeBackend.subtext0; font.pixelSize: 10 }
                    }
                }
            }
            Visualizer {
                Layout.fillWidth: true; Layout.preferredHeight: visible ? 40 : 0
                visible: studio.spectrumActive
                active: studio.subscribed
                previewDemo: false
                color: studio.accent; count: 48; mirrored: false
            }
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: [{name:"Bass", key:"bass", bands:[1,2,3]}, {name:"Mid", key:"mid", bands:[4,5,6,7]}, {name:"Treble", key:"treble", bands:[8,9,10]}]
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        readonly property real gain: modelData.bands.reduce((sum,b) => sum + Number(MusicEffects.eqState["b"+b]), 0)/modelData.bands.length
                        Text { text: modelData.name + " · " + parent.gain.toFixed(1) + " dB"; color: ThemeBackend.text; font.pixelSize: 11 }
                        StudioSlider {
                            Layout.fillWidth: true; Layout.preferredWidth: 100
                            from: -12; to: 12; stepSize: 1
                            objectName: "tone_" + modelData.key
                            value: parent.gain; enabled: studio.editable
                            animate: studio.animate; accent: studio.accent
                            onMoved: MusicEffects.command(["set_tone", modelData.key, Math.round(value)])
                            Accessible.name: modelData.name
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "Volume"; color: ThemeBackend.text; font.pixelSize: 11 }
                StudioSlider {
                    Layout.fillWidth: true
                    objectName: "masterVolume"
                    from: 0; to: 100; stepSize: 1
                    enabled: !!(Audio.defaultSink && Audio.defaultSink.audio)
                    value: enabled ? Audio.defaultSink.audio.volume * 100 : 0
                    onMoved: Audio.setVolume(Audio.defaultSink, value)
                    animate: studio.animate; accent: studio.accent
                    Accessible.name: "Общая громкость"
                }
                StudioButton { text: Audio.defaultSink && Audio.defaultSink.audio && Audio.defaultSink.audio.muted ? "Unmute" : "Mute"; enabled: !!Audio.defaultSink; onClicked: Audio.toggleMute(Audio.defaultSink) }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: "L"; color: ThemeBackend.subtext0 }
                StudioSlider {
                    Layout.fillWidth: true
                    from: -1; to: 1; stepSize: 0.01
                    value: MusicEffects.eqState.balance
                    enabled: MusicEffects.available && MusicEffects.eqState.effects
                    animate: studio.animate; accent: studio.accent
                    onMoved: MusicEffects.command(["set_balance", Math.round(value*100)/100])
                    Accessible.name: "Баланс левого и правого каналов"
                }
                Text { text: "R"; color: ThemeBackend.subtext0 }
                StudioButton { text: "Reset"; enabled: MusicEffects.available; onClicked: MusicEffects.command(["reset"]) }
            }
            RowLayout {
                Layout.fillWidth: true
                TextField { id: presetName; Layout.fillWidth: true; placeholderText: "Название своего пресета"; maximumLength: 60
                    color: ThemeBackend.text; placeholderTextColor: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily; font.pixelSize: 12
                    background: Rectangle { radius: 9; color: ThemeBackend.surface0; border.color: Qt.alpha(studio.accent,0.2) }
                }
                StudioButton { text: "Save Preset"; enabled: presetName.text.trim().length > 0 && MusicEffects.available && !MusicEffects.busy; onClicked: MusicEffects.command(["save_preset", presetName.text]) }
            }
        }
    }
}
