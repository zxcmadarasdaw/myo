import QtQuick
import Quickshell
import Quickshell.Io
import "WallpaperAudioActivity.js" as Activity

Item {
    id: root
    required property bool watching
    required property bool watchPlayback
    required property bool watchCalls

    readonly property bool active: root.watching && root.heldActivity
    readonly property bool waiting: root.watching && !initialAttemptFinished
    property bool initialAttemptFinished: false
    property bool ready: false
    property bool heldActivity: false
    property bool playback: false
    property bool calls: false
    property var graph: new Map()
    property var lines: []

    function updateActivity() {
        if (!watching) return;
        if ((watchPlayback && playback) || (watchCalls && calls)) {
            releaseTimer.stop();
            heldActivity = true;
        } else if (heldActivity && !releaseTimer.running) {
            releaseTimer.start();
        }
    }

    function readLine(line) {
        if (!watching || !monitor.running) return;
        // pw-dump --monitor emits successive JSON arrays, one per graph update.
        if (line.startsWith("[")) lines = [];
        else if (lines.length === 0) return;
        lines.push(line);
        if (!line.startsWith("]") && !(lines.length === 1 && line.trim().endsWith("]"))) return;
        let batch;
        try {
            batch = JSON.parse(lines.join("\n"));
        } catch (error) {
            lines = [];
            return;
        }
        lines = [];
        if (!Array.isArray(batch)) return;
        Activity.updateGraph(graph, batch);
        const state = Activity.activity(graph, Quickshell.processId);
        playback = state.playback;
        calls = state.calls;
        updateActivity();
        ready = true;
        initialAttemptFinished = true;
        startupTimeout.stop();
    }

    function reset() {
        ready = false;
        heldActivity = false;
        playback = false;
        calls = false;
        graph.clear();
        lines = [];
        releaseTimer.stop();
    }

    onWatchPlaybackChanged: updateActivity()
    onWatchCallsChanged: updateActivity()
    onWatchingChanged: {
        if (watching) {
            startupTimeout.restart();
            monitor.running = true;
        } else {
            startupTimeout.stop();
            retryTimer.stop();
            monitor.running = false;
            reset();
            initialAttemptFinished = false;
        }
    }

    Process {
        id: monitor
        command: ["sh", "-c", "exec pw-dump --monitor --no-colors"]
        stdout: SplitParser { onRead: line => root.readLine(line) }
        onStarted: {
            retryTimer.stop();
            if (root.watching) startupTimeout.restart();
            else running = false;
        }
        onExited: {
            startupTimeout.stop();
            root.reset();
            if (root.watching) {
                root.initialAttemptFinished = true;
                retryTimer.restart();
            }
        }
    }

    Timer {
        id: startupTimeout
        interval: 2500
        onTriggered: {
            root.initialAttemptFinished = true;
            monitor.running = false;
        }
    }
    Timer {
        id: retryTimer
        interval: 5000
        onTriggered: {
            if (root.watching) {
                startupTimeout.restart();
                monitor.running = true;
            }
        }
    }
    Timer {
        id: releaseTimer
        interval: 500
        onTriggered: root.heldActivity = false
    }
}
