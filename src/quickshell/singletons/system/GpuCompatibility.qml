pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "GpuPolicy.js" as Policy

Item {
    id: root
    visible: false
    readonly property string selectedProfile: Policy.normalizeProfile(Config.getSetting("graphics.profile", "Balanced"))
    readonly property bool manualSafeMode: Config.getSetting("graphics.safeMode", false) === true
    readonly property bool environmentSafeMode: Quickshell.env("SERPANTINUM_SAFE_GRAPHICS") === "1"
    property var backends: ({})
    property var shaderStates: ({})
    property var shaderErrors: ({})
    property var mediaStates: ({})
    property var report: ({})
    property string scanError: ""
    property bool started: false
    property bool notifiedChange: false
    readonly property bool busy: scanner.running
    readonly property var effective: Policy.policy(selectedProfile, manualSafeMode || environmentSafeMode, backends, shaderErrors)
    readonly property bool shadersAllowed: effective.shaders
    readonly property bool blurAllowed: effective.blur
    readonly property var recommended: Policy.recommendation(report, effective, backends, shaderStates)
    readonly property var previousHardware: Config.getSetting("graphics.lastHardware", {})
    readonly property bool hardwareChanged: Policy.hardwareChanged(previousHardware.fingerprint, report.fingerprint)
    readonly property string helper: Caching.serpantinumDir + "/scripts/system/gpu_compatibility.py"
    property var decodeResult: ({})
    readonly property bool decodeBusy: decoder.running
    signal retryVideoRequested()
    function retryVideos() { mediaStates = ({}); retryVideoRequested(); }

    function setProfile(name) {
        if (Config.dataReady) Config.setSetting("graphics.profile", Policy.normalizeProfile(name));
    }
    function setSafeMode(enabled) {
        if (Config.dataReady) Config.setSetting("graphics.safeMode", !!enabled);
    }
    function observeBackend(key, value) {
        if (backends[key] === value) return;
        let next = Object.assign({}, backends); next[key] = value; backends = next;
    }
    function forgetBackend(key) {
        let next = Object.assign({}, backends); delete next[key]; backends = next;
    }
    function observeShader(key, status, log) {
        if (status === ShaderEffect.Error) {
            // Defer policy changes until the renderer callback has returned;
            // fallback can unload the reporting component.
            Qt.callLater(function() {
                let errors = Object.assign({}, root.shaderErrors);
                errors[key] = String(log || "ShaderEffect error").slice(0, 2000);
                root.shaderErrors = errors;
            });
        }
        const value = status === ShaderEffect.Error ? "error" : (status === ShaderEffect.Compiled ? "compiled" : "uncompiled");
        if (shaderStates[key] !== value) {
            let next = Object.assign({}, shaderStates); next[key] = value; shaderStates = next;
        }
    }
    function resetShaderErrors() {
        shaderStates = ({}); shaderErrors = ({});
    }
    function observeMedia(key, path, state, detail) {
        let next = Object.assign({}, mediaStates);
        next[key] = {path: path, state: state, detail: String(detail || "").slice(0, 2000)};
        mediaStates = next;
    }
    function forgetMedia(key) {
        if (mediaStates[key] === undefined) return;
        let next = Object.assign({}, mediaStates); delete next[key]; mediaStates = next;
    }
    function acceptHardware() {
        if (!Config.dataReady || !report.fingerprint || report.status !== "ok") return;
        Config.setSetting("graphics.lastHardware", {fingerprint: report.fingerprint,
            models: report.gpus.map(function(g) { return g.model; })});
        notifiedChange = false;
    }
    function scan() {
        if (scanner.running || !Config.dataReady) return;
        scanError = "";
        scanner.running = true;
        watchdog.restart();
    }
    function start() {
        if (started || !Config.dataReady) return;
        started = true;
        scan();
    }
    function decodeFile(path, backend, device) {
        if (decoder.running) return;
        decodeResult = {status: "running"};
        decoder.command = ["python3", helper, "--decode-file", path, "--backend", backend, "--device", device];
        decoder.running = true;
        decodeWatchdog.restart();
    }

    Component.onCompleted: start()
    Connections {
        target: Config
        function onDataReadyChanged() { root.start(); }
    }
    onHardwareChangedChanged: {
        if (hardwareChanged && !notifiedChange) {
            notifiedChange = true;
            Quickshell.execDetached(["notify-send", "Serpantinum: GPU changed",
                "Open Settings → Display → GPU compatibility. Your theme, widgets and wallpaper have been kept."]);
        }
    }

    Timer {
        id: watchdog
        interval: 90000
        onTriggered: {
            scanner.running = false;
            root.scanError = "GPU probe timed out or could not start. Check python3 and the helper path.";
        }
    }
    Process {
        id: scanner
        command: ["python3", root.helper]
        stdout: StdioCollector {
            onStreamFinished: {
                watchdog.stop();
                try {
                    let value = JSON.parse(this.text);
                    if (value.schema !== 1 || !Array.isArray(value.gpus)) throw new Error(value.message || "Invalid probe response");
                    root.report = value;
                    if (!root.previousHardware.fingerprint && value.fingerprint) root.acceptHardware();
                } catch (e) { root.scanError = String(e); }
            }
        }
        onExited: function(code) {
            if (code !== 0) { watchdog.stop(); root.scanError = "GPU helper exited with code " + code; }
        }
    }
    Timer {
        id: decodeWatchdog
        interval: 25000
        onTriggered: { decoder.running = false; root.decodeResult = {status: "timeout", message: "Decode probe did not finish."}; }
    }
    Process {
        id: decoder
        stdout: StdioCollector {
            onStreamFinished: {
                decodeWatchdog.stop();
                try { root.decodeResult = JSON.parse(this.text); }
                catch (e) { root.decodeResult = {status: "error", message: "Invalid decode response: " + e}; }
            }
        }
        onExited: function(code) {
            if (code !== 0) { decodeWatchdog.stop(); root.decodeResult = {status: "error", message: "Decoder helper exited with code " + code}; }
        }
    }
}
