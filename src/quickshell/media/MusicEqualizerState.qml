import QtQuick
import Quickshell.Io
import "../"

// Both the original popup and its desktop drawer share the same acknowledged state.
MusicPlayerState {
    id: root
    property var eqData: MusicEffects.eqState
    property var savedEqData: MusicEffects.eqState
    property color eqAccentColor: ThemeBackend.mauve
    property real eqLightningProgress: 0
    property real eqLightningFade: 1
    property real lastEqUpdate: 0
    property bool presetAnimationEnabled: true
    property bool audioTestRunning: false
    property bool effectsSubscribed: false
    function subscribeEffects() {
        if (active && !effectsSubscribed) { MusicEffects.register(); effectsSubscribed = true; }
        else if (!active && effectsSubscribed) { MusicEffects.unregister(); effectsSubscribed = false; }
    }
    Connections { target: root; function onActiveChanged() { root.subscribeEffects(); } }
    Component.onCompleted: subscribeEffects()
    Component.onDestruction: { if (effectsSubscribed) MusicEffects.unregister(); }
    function restoreLastSavedEqualizer() {} // Every successful change is already persistent.
    SequentialAnimation {
        id: eqLightningAnim
        running: false
        ScriptAction { script: { root.eqLightningFade = 0.0; root.eqLightningProgress = 0.0; } }
        NumberAnimation {
            target: root; property: "eqLightningProgress";
            from: 0.0; to: 10.0;
            duration: 650;
            easing.type: Easing.OutSine
        }
        PauseAnimation { duration: 150 }
        NumberAnimation {
            target: root; property: "eqLightningFade";
            from: 0.0; to: 1.0;
            duration: 800;
            easing.type: Easing.OutQuad
        }
        ScriptAction { script: { root.eqLightningProgress = 0.0; } }
    }

    function triggerEqLightning() {
        Sounds.playSfx("musicpopup/swoosh.wav", 0.75);
        eqLightningAnim.restart();
    }

    Connections {
        target: MusicEffects
        function onApplied(command) {
            if (root.active && root.presetAnimationEnabled && command === "preset" && GpuCompatibility.effective.profile !== "Performance") root.triggerEqLightning();
        }
    }
    function applyPresetOptimistically(name) { MusicEffects.command(["preset", name]); }
    function setBand(band, value) { MusicEffects.command(["set_band", band, Math.round(value)]); }
    function setBalance(value) { MusicEffects.command(["set_balance", Math.round(value * 100) / 100]); }
    function setAudioFlag(name, value) {
        if (["mono", "swap", "dyneq"].indexOf(name) >= 0) MusicEffects.command(["set_" + name, value]);
    }
    function setDynamics(value) { MusicEffects.command(["set_dynamics", value]); }
    function resetAudio() { MusicEffects.command(["reset_audio"]); }
    function toggleAudioTest() {
        if (!MusicEffects.available || testProcess.running) return;
        testProcess.command = ["bash", Caching.qsDir + "/media/equalizer.sh", audioTestRunning ? "stop_test" : "test"];
        testProcess.running = true;
        audioTestRunning = !audioTestRunning;
        testTimer.restart();
    }
    Timer { id: testTimer; interval: 3200; onTriggered: root.audioTestRunning = false }
    Process { id: testProcess; onExited: (code) => { if (code !== 0) root.audioTestRunning = false; } }
}
