pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../"

Item {
    id: root

    signal wallpaperChanged(string screenName, string path, string transition)
    signal playbackChanged(string screenName, string state)
    signal wallpaperCleared(string screenName)

    property var screenWallpapers: ({})
    property var screenWallpaperPaths: ({})
    property var engines: ({})
    property bool sessionLocked: false
    readonly property var audioModes: ["off", "mute", "duck"]
    readonly property var audioSources: ["primary", "monitor", "none"]
    readonly property var audioSettings: {
        const saved = Config.getSetting("wallpaperAudio", {}) || {};
        return {
            enabled: saved.enabled === true,
            muted: saved.muted === true,
            volume: audioPercent(saved.volume, 50),
            mode: audioModes.includes(saved.mode) ? saved.mode : "off",
            duckVolume: audioPercent(saved.duckVolume, 15),
            reactToPlayback: saved.reactToPlayback !== false,
            reactToCalls: saved.reactToCalls !== false,
            muteOnLock: saved.muteOnLock !== false,
            source: audioSources.includes(saved.source) ? saved.source : "primary",
            monitor: typeof saved.monitor === "string" ? saved.monitor : ""
        };
    }
    readonly property var audioMonitors: Array.from(Quickshell.screens, screen => screen.name)
    readonly property string audioScreenName: {
        if (audioSettings.source === "none") return "";
        if (audioSettings.source === "monitor")
            return audioMonitors.includes(audioSettings.monitor) ? audioSettings.monitor : "";
        // Quickshell exposes Qt's screen list, which starts with its primary output.
        return audioMonitors[0] || "";
    }
    readonly property var audioEngine: audioScreenName ? engines[audioScreenName] || null : null
    readonly property string audioTrackState: audioEngine?.audioTrackState ?? "unknown"
    readonly property bool smartAudioWatching: audioMonitor.watching
    readonly property bool smartAudioReady: audioMonitor.ready
    readonly property bool smartAudioActive: audioMonitor.active
    readonly property int effectiveAudioVolume: {
        if (sessionLocked && audioSettings.muteOnLock) return 0;
        if (audioMonitor.waiting || (smartAudioActive && audioSettings.mode === "mute")) return 0;
        if (smartAudioActive && audioSettings.mode === "duck")
            return Math.min(audioSettings.volume, audioSettings.duckVolume);
        return audioSettings.volume;
    }

    function audioPercent(value: var, fallback: int): int {
        return typeof value === "number" && isFinite(value) ? Math.max(0, Math.min(100, Math.round(value))) : fallback;
    }

    function setAudioSetting(key: string, value: var): void {
        Config.setSetting("wallpaperAudio." + key, value);
    }

    WallpaperAudioMonitor {
        id: audioMonitor
        watching: root.audioSettings.enabled && !root.audioSettings.muted
                  && root.audioSettings.volume > 0 && root.audioSettings.mode !== "off"
                  && root.audioTrackState === "present" && !root.audioEngine.playbackPaused
                  && (root.audioSettings.reactToPlayback || root.audioSettings.reactToCalls)
        watchPlayback: root.audioSettings.reactToPlayback
        watchCalls: root.audioSettings.reactToCalls
    }

    // Last wallpaper requested for every output. Outputs that appear later
    // (hotplug, slow monitor init on login) adopt it instead of staying empty.
    property string lastRequestedAll: ""

    // Opt-in (Settings -> Diagnostics): while a screen recorder runs, the
    // wallpaper engine uses its existing light path (video snapshot, paused
    // GIF, no shader transitions). Normal playback returns when recording stops.
    readonly property bool recordingLiteEnabled: (typeof Config !== "undefined") && !!Config.getSetting("general.recordingLite", false)
    property bool captureActive: false
    readonly property bool captureLite: recordingLiteEnabled && captureActive
    onRecordingLiteEnabledChanged: if (!recordingLiteEnabled) captureActive = false

    Process {
        id: captureProbe
        command: ["sh", "-c", "pgrep -x obs >/dev/null || pgrep -x wf-recorder >/dev/null || pgrep -x wl-screenrec >/dev/null || pgrep -x kooha >/dev/null || pgrep -f '^gpu-screen-recorder' >/dev/null"]
        onExited: (code) => { root.captureActive = root.recordingLiteEnabled && code === 0; }
    }
    Timer {
        interval: 4000
        repeat: true
        triggeredOnStart: true
        running: root.recordingLiteEnabled
        onTriggered: { if (!captureProbe.running) captureProbe.running = true; }
    }

    readonly property var transitionIds: ["fade", "wipe", "circle", "swipe", "paint", "wave", "blinds", "clock", "hex", "ink"]
    readonly property var transitionModes: ["random", "custom"]
    readonly property var wipeOrientations: ["random", "horizontal", "vertical"]
    readonly property var circleOrigins: ["random", "center"]
    readonly property var swipeDirections: ["left", "right", "top", "bottom", "top_left", "top_right", "bottom_left", "bottom_right"]
    readonly property var defaultTransitionSettings: ({
        "mode": "random",
        "pool": root.transitionIds,
        "effects": {
            "fade": { "duration": 1000 },
            "wipe": { "duration": 1600, "orientation": "random" },
            "circle": { "duration": 1600, "origin": "random" },
            "swipe": { "duration": 1600, "direction": "random" },
            "paint": { "duration": 2400 },
            "wave": { "duration": 1800, "direction": "random", "speed": 1 },
            "blinds": { "duration": 1600, "orientation": "random", "speed": 1 },
            "clock": { "duration": 1800, "origin": "center", "speed": 1 },
            "hex": { "duration": 2000, "size": 80, "speed": 1 },
            "ink": { "duration": 3000, "origin": "random", "speed": 1 }
        }
    })

    Component.onCompleted: {
        if (Compositor.name === "niri") NiriState.subscribe();
        if (Compositor.name === "umbriel") UmbrielState.subscribe();
    }
    Component.onDestruction: {
        if (Compositor.name === "niri") NiriState.unsubscribe();
        if (Compositor.name === "umbriel") UmbrielState.unsubscribe();
    }

    function transitionWorkspace(screenName: string): string {
        if (Compositor.name === "hyprland") {
            const workspace = screenName ? Hyprland.monitors.values.find(m => m.name === screenName)?.activeWorkspace
                                         : Hyprland.focusedWorkspace;
            if (workspace && workspace.id > 0)
                return "hyprland:" + (screenName || workspace.monitor?.name || "") + ":" + workspace.id;
        }
        if (Compositor.name === "niri") {
            const workspaces = Object.values(NiriState.workspacesMap);
            const workspace = workspaces.find(w => screenName ? w.output === screenName && w.is_active : w.is_focused);
            if (workspace && workspace.output && workspace.idx > 0)
                return "niri:" + workspace.output + ":" + workspace.idx;
        }
        if (Compositor.name === "umbriel") {
            const output = screenName || UmbrielState.focusedOutput;
            const index = UmbrielState.activeIndicesByOutput[output];
            if (output && Number.isInteger(index) && index >= 0)
                return "umbriel:" + output + ":" + (index + 1);
        }
        return "";
    }

    function transitionSettings(workspace = "") {
        let d = root.defaultTransitionSettings;
        let s = (typeof Config !== "undefined") ? Config.getSetting("wallpaperTransition", {}) : {};
        if (!s || typeof s !== "object") s = {};
        if (workspace) {
            const profiles = Config.getSetting("wallpaperTransitionByWorkspace", {}) || {};
            if (profiles[workspace] && typeof profiles[workspace] === "object") s = profiles[workspace];
        }
        let effects = {};
        for (let i = 0; i < root.transitionIds.length; i++) {
            let id = root.transitionIds[i];
            effects[id] = Object.assign({}, d.effects[id], (s.effects && typeof s.effects[id] === "object") ? s.effects[id] : {});
        }
        let single = s.mode === "single" && root.transitionIds.indexOf(s.type) !== -1;
        let pool = single ? [s.type] : (Array.isArray(s.pool) ? s.pool.filter(id => root.transitionIds.indexOf(id) !== -1) : d.pool.slice());
        if (pool.length === 0) pool = d.pool.slice();
        return {
            "mode": single ? "custom" : (root.transitionModes.indexOf(s.mode) !== -1 ? s.mode : d.mode),
            "pool": pool,
            "effects": effects
        };
    }

    function transitionDuration(fx: var): int {
        const duration = Math.max(100, Math.min(10000, Number(fx.duration) || 1000));
        const speed = Math.max(0.25, Math.min(4, Number(fx.speed) || 1));
        return Math.max(100, Math.round(duration / speed));
    }

    function hexCells(fx: var): int {
        return Math.max(20, Math.min(240, Math.round(Number(fx.size) || 80)));
    }

    function resolveTransition(typeIndex, screenName = "") {
        let s = root.transitionSettings(root.transitionWorkspace(screenName));
        let id;
        if (typeIndex >= 0 && typeIndex < root.transitionIds.length) {
            id = root.transitionIds[typeIndex];
        } else {
            let candidates = s.mode === "custom" ? s.pool : root.transitionIds;
            id = candidates[Math.floor(Math.random() * candidates.length)];
        }
        let fx = s.effects[id];
        let dirIdx = root.swipeDirections.indexOf(fx.direction);
        return {
            "type": root.transitionIds.indexOf(id),
            "duration": root.transitionDuration(fx),
            "hexSize": root.hexCells(fx),
            "vertical": fx.orientation === "vertical" || (fx.orientation !== "horizontal" && Math.random() < 0.5),
            "direction": dirIdx >= 0 ? dirIdx : Math.floor(Math.random() * root.swipeDirections.length),
            "centered": fx.origin === "center"
        };
    }

    function registerEngine(screenName: string, engine: var): void {
        if (!screenName) return;
        let map = Object.assign({}, root.engines);
        map[screenName] = engine;
        root.engines = map;
        publishEngineState(screenName, engine);
    }

    function publishEngineState(screenName: string, engine: var): void {
        if (!screenName || root.engines[screenName] !== engine) return;
        const paths = Object.assign({}, root.screenWallpaperPaths);
        const titles = Object.assign({}, root.screenWallpapers);
        if (engine.currentWallpaperPath) paths[screenName] = engine.currentWallpaperPath;
        else delete paths[screenName];
        if (engine.originalFileName) titles[screenName] = engine.originalFileName;
        else delete titles[screenName];
        root.screenWallpaperPaths = paths;
        root.screenWallpapers = titles;
    }

    function unregisterEngine(screenName: string, engine: var): void {
        if (!screenName || root.engines[screenName] !== engine) return;
        let map = Object.assign({}, root.engines);
        delete map[screenName];
        root.engines = map;
        const paths = Object.assign({}, root.screenWallpaperPaths);
        const titles = Object.assign({}, root.screenWallpapers);
        delete paths[screenName];
        delete titles[screenName];
        root.screenWallpaperPaths = paths;
        root.screenWallpapers = titles;
    }

    function setWallpaper(screenName: string, path: string, transition: string): void {
        if (screenName === "all" && path) root.lastRequestedAll = path;
        root.wallpaperChanged(screenName, path, transition ? transition : "fade");
    }

    function getWallpaper(screenName: string): string {
        if (!screenName || screenName === "") {
            let keys = Object.keys(root.screenWallpapers);
            return keys.length > 0 ? root.screenWallpapers[keys[0]] : "";
        }
        return root.screenWallpapers[screenName] || "";
    }

    function getWallpaperPath(screenName: string): string {
        if (!screenName || screenName === "") {
            let keys = Object.keys(root.screenWallpaperPaths);
            return keys.length > 0 ? root.screenWallpaperPaths[keys[0]] : "";
        }
        return root.screenWallpaperPaths[screenName] || "";
    }

    function setPlayback(screenName: string, state: string): void {
        root.playbackChanged(screenName, state);
    }

    function clearWallpaper(screenName: string): void {
        root.wallpaperCleared(screenName);
    }

    function shuffle(screenName: string, transition: string): void {
        let scrName = screenName || "all";
        let dir = Config.getSetting("wallpaperDir", "") || Config.getSetting("wallpaper_dir", "") || Quickshell.env("WALLPAPER_DIR") || (Quickshell.env("HOME") + "/Pictures/Wallpapers");
        let script =
            "[ -d \"$1\" ] && find -L \"$1\" -maxdepth 1 -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.webp\" -o -iname \"*.bmp\" -o -iname \"*.gif\" -o -iname \"*.avif\" -o -iname \"*.mp4\" -o -iname \"*.mkv\" -o -iname \"*.mov\" -o -iname \"*.webm\" \\) 2>/dev/null | shuf -n 1";
        shuffleProcess.targetScreenName = scrName;
        shuffleProcess.transition = transition || "";
        shuffleProcess.command = ["bash", "-c", script, "shuffle", dir];
        shuffleProcess.running = false;
        shuffleProcess.running = true;
    }

    Process {
        id: shuffleProcess
        running: false
        property string targetScreenName: ""
        property string transition: ""

        stdout: StdioCollector {
            onStreamFinished: {
                let picked = this.text.trim();
                if (picked !== "") root.setWallpaper(shuffleProcess.targetScreenName, picked, shuffleProcess.transition);
            }
        }
    }

    IpcHandler {
        target: "wallpaper"

        function setWallpaper(screenName: string, path: string, transition: string): void {
            root.setWallpaper(screenName, path, transition);
        }

        function getWallpaper(screenName: string): string {
            return root.getWallpaper(screenName);
        }

        function getWallpaperPath(screenName: string): string {
            return root.getWallpaperPath(screenName);
        }

        function setPlayback(screenName: string, state: string): void {
            root.setPlayback(screenName, state);
        }

        function clearWallpaper(screenName: string): void {
            root.clearWallpaper(screenName);
        }
    }
}
