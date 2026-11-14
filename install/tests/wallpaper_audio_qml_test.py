"""Exercise wallpaper audio with real Qt Multimedia and simulated PipeWire events.

Run with PySide6 and ffmpeg on PATH. Quickshell and the compositor are stubbed.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import QObject, QMetaObject, QUrl, Q_ARG, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtMultimedia import QMediaPlayer
from PySide6.QtQml import QQmlComponent, QQmlEngine

ROOT = Path(__file__).resolve().parents[2] / "src/quickshell"
app = QGuiApplication([])
messages = []
qInstallMessageHandler(lambda kind, context, message: messages.append(message))


def wait_for(predicate, message):
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        app.processEvents()
        if predicate():
            return
        time.sleep(0.01)
    raise AssertionError(f"{message}\n" + "\n".join(messages[-15:]))


def encode(path, video_codec, audio_codec=None):
    command = ["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=s=64x48:r=20"]
    if audio_codec:
        command += ["-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-c:a", audio_codec]
    subprocess.run(command + ["-t", "4", "-c:v", video_codec, str(path)], check=True)


def object_(id_, kind, **info):
    return {"id": id_, "type": f"PipeWire:Interface:{kind}", "info": info}


def stream(id_, media_class, state="running", props=None, params=None):
    return object_(id_, "Node", state=state, props={"media.class": media_class, **(props or {})}, params=params or {})


def link(id_, source, target, state="active"):
    return object_(id_, "Link", state=state, **{"output-node-id": source, "input-node-id": target})


with tempfile.TemporaryDirectory(prefix="wallpaper-audio-", ignore_cleanup_errors=True) as directory:
    root = Path(directory)

    def write(name, content):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    sources = [
        "singletons/system/Config.qml",
        "singletons/theme/Wallpaper.qml",
        "singletons/audio/AudioStream.js",
        "singletons/audio/WallpaperAudioActivity.js",
        "singletons/audio/WallpaperAudioMonitor.qml",
        "guide/wallpaper/WallpaperAudioSection.qml",
        "reusables/guide/SettingsRow.qml",
        "reusables/guide/SettingsGroup.qml",
        "reusables/inputs/Toggle.qml",
        "reusables/inputs/Dropdown.qml",
        "reusables/buttons/IconButton.qml",
        "reusables/behavior/Draggable.qml",
    ]
    for name in sources:
        write(name, (ROOT / name).read_text(encoding="utf-8"))

    write("qmldir", """singleton Wallpaper 1.0 singletons/theme/Wallpaper.qml
WallpaperAudioMonitor 1.0 singletons/audio/WallpaperAudioMonitor.qml
singleton Config 1.0 singletons/system/Config.qml
singleton Caching 1.0 Caching.qml
singleton GpuCompatibility 1.0 GpuCompatibility.qml
singleton ThemeBackend 1.0 ThemeBackend.qml
singleton I18n 1.0 I18n.qml
""")
    write("reusables/qmldir", """Toggle 1.0 inputs/Toggle.qml
Dropdown 1.0 inputs/Dropdown.qml
IconButton 1.0 buttons/IconButton.qml
Draggable 1.0 behavior/Draggable.qml
GlassFill 1.0 GlassFill.qml
GlassLens 1.0 GlassLens.qml
""")
    write("reusables/GlassFill.qml", """import QtQuick
Item {
    property bool active: false
    property bool forceClear
    property bool allowed
    property bool followBackdropHover
    property real radius
    property color tintColor
    property real tintAmount
    property real tintStrength
    property real frost
    property real rim
    property real saturation
    property real thickness
    property real press
    property real shadow
    property real pulse
    property var backdropOverride
}
""")
    write("reusables/GlassLens.qml", """import QtQuick
Item {
    property bool glassActive: false
    property bool instant
    property real targetX
    property real targetY
    property real targetWidth
    property real targetHeight
    property real radius
    property bool followBackdropHover
    property bool forceClear
    property var backdropOverride
    property color tintColor
    property real tintAmount
    property real tintStrength
    property real shadow
    property real restPress
    property real fastDuration
    property real slowDuration
    property real press
}
""")
    write("ThemeBackend.qml", """pragma Singleton
import QtQuick
QtObject {
    property bool liquidGlass: false
    property int borderRadius: 8
    property int clampedBorderRadius: 8
    property string fontFamily: "sans-serif"
    property string iconFont: "sans-serif"
    property color text: "white"
    property color subtext0: "lightgray"
    property color crust: "#111111"
    property color mantle: "#111111"
    property color base: "#222222"
    property color surface0: "#333333"
    property color surface1: "#444444"
    property color surface2: "#555555"
    property color mauve: "violet"
    property color blue: "blue"
}
""")
    write("I18n.qml", """pragma Singleton
import QtQuick
QtObject {
    property int layoutDirection: Qt.LeftToRight
    property int textAlignment: Text.AlignLeft
    property bool rtl: false
    function t(key, fallback) { return fallback || key; }
}
""")
    write("Caching.qml", """pragma Singleton
import QtQuick
QtObject { function fileUrl(path) { return path; } }
""")
    write("GpuCompatibility.qml", """pragma Singleton
import QtQuick
QtObject { function observeMedia(key, path, state, reason) {} }
""")
    write("Quickshell/qmldir", "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n")
    write("Quickshell/Quickshell.qml", """pragma Singleton
import QtQuick
QtObject {
    property int processId: 4242
    property var screens: [{name: "DP-1"}, {name: "HDMI-A-1"}]
    property var pipewireParser: null
    property var settingsCommand: []
    property string settingsText: ""
    function execDetached(command) {}
    function env(name) {
        return name === "QS_SETTINGS" ? """ + json.dumps((root / "settings.json").as_posix()) + """ : "";
    }
}
""")
    write("Quickshell/Io/qmldir", """module Quickshell.Io
Process 1.0 Process.qml
SplitParser 1.0 SplitParser.qml
StdioCollector 1.0 StdioCollector.qml
IpcHandler 1.0 IpcHandler.qml
FileView 1.0 FileView.qml
""")
    write("Quickshell/Io/Process.qml", """import QtQuick
import Quickshell
QtObject {
    property var command
    property bool running: false
    property var stdout
    signal exited(int code)
    signal started()
    onRunningChanged: {
        if (running && command[0] === "bash" && command[2].startsWith('target="$1"')) {
            Quickshell.settingsCommand = command;
            Qt.callLater(() => { running = false; exited(0); });
        }
        if (running && stdout && typeof stdout.read === "function") {
            Quickshell.pipewireParser = stdout;
            started();
        }
        else if (!running && Quickshell.pipewireParser === stdout) Quickshell.pipewireParser = null;
    }
}
""")
    write("Quickshell/Io/SplitParser.qml", "import QtQuick\nQtObject { signal read(string line) }")
    write("Quickshell/Io/StdioCollector.qml", "import QtQuick\nQtObject { property string text; signal streamFinished() }")
    write("Quickshell/Io/IpcHandler.qml", "import QtQuick\nQtObject { property string target }")
    write("Quickshell/Io/FileView.qml", """import QtQuick
import Quickshell
QtObject {
    property string path
    property bool watchChanges
    property bool printErrors
    signal loaded()
    signal loadFailed()
    signal fileChanged()
    function text() { return Quickshell.settingsText; }
    function reload() { if (text()) loaded(); else loadFailed(); }
}
""")

    engine_source = (ROOT / "wallpaper/WallpaperEngine.qml").read_text(encoding="utf-8")
    layers = []
    for slot in "AB":
        match = re.search(rf"\n( +)Component \{{\n\s+id: videoLayerComp{slot}\n.*?\n\1\}}", engine_source, re.S)
        assert match, f"missing video layer {slot}"
        layer = match[0]
        layer = layer.replace("anchors.fill: parent", "")
        layer = layer.replace(f"id: player{slot}\n", f'id: player{slot}\nobjectName: "player{slot}"\n')
        layers.append(layer)
    engine_properties = "\n".join(re.findall(
        r"[^\n]*readonly property (?:var activeVideo|string audioTrackState|bool audioSelected):[^\n]*"
        r"(?:\n +&&[^\n]*)?", engine_source
    )[:3])

    write("VideoHarness.qml", """import QtQuick
import QtMultimedia
import "."
Item {
    id: barWindow
    required property string monitorName
    readonly property var screen: ({name: monitorName})
    property int activeLayer: 0
    property bool playbackPaused: false
    property bool staticVideoA: false
    property bool staticVideoB: false
    property string failedVideoA
    property string failedVideoB
    property string pathA
    property string pathB
    readonly property bool isVideoA: pathA !== ""
    readonly property bool isVideoB: pathB !== ""
    function reportLoadError(path, reason) { console.error(reason); }
    Loader { id: videoLoaderA; sourceComponent: videoLayerCompA }
    Loader { id: videoLoaderB; sourceComponent: videoLayerCompB }
""" + engine_properties + "\n".join(layers) + "\n}")

    write("Harness.qml", """import QtQuick
import Quickshell
import "."
import "guide/wallpaper"
Item {
    property bool locked: false
    readonly property var settingsCommand: Quickshell.settingsCommand
    readonly property string settingsPayload: Quickshell.settingsCommand[5] || ""
    readonly property int baseVolume: Wallpaper.audioSettings.volume
    readonly property bool enabledAudio: Wallpaper.audioSettings.enabled
    readonly property string track: Wallpaper.audioTrackState
    readonly property bool pipewireReady: Wallpaper.smartAudioReady
    readonly property bool smartActive: Wallpaper.smartAudioActive
    readonly property bool monitoring: !!Quickshell.pipewireParser
    function feed(payload) {
        for (const line of payload.split("\\n")) Quickshell.pipewireParser.read(line);
    }
    function change(key, value) { Wallpaper.setAudioSetting(key, value); }
    function loadSettings(payload) { Quickshell.settingsText = payload; Config.reloadFromDisk(); }
    function disconnectOther() { Quickshell.screens = [Quickshell.screens[0]]; }
    function reconnectOther() { Quickshell.screens = [{name: "DP-1"}, {name: "HDMI-A-1"}]; }
    Binding { target: Wallpaper; property: "sessionLocked"; value: locked }
    WallpaperAudioSection { width: 520; expanded: true }
    VideoHarness { id: monitorA; objectName: "main"; monitorName: "DP-1" }
    VideoHarness { id: monitorB; objectName: "other"; monitorName: "HDMI-A-1" }
    Component.onCompleted: {
        Wallpaper.registerEngine(monitorA.monitorName, monitorA);
        Wallpaper.registerEngine(monitorB.monitorName, monitorB);
    }
}
""")

    mp4, silent_mp4, webm = [root / name for name in ("with-audio.mp4", "silent.mp4", "with-audio.webm")]
    encode(mp4, "libx264", "aac")
    encode(silent_mp4, "libx264")
    encode(webm, "libvpx-vp9", "libopus")
    qml = QQmlEngine()
    qml.addImportPath(str(root))
    component = QQmlComponent(qml, QUrl.fromLocalFile(str(root / "Harness.qml")))
    host = component.create()
    assert host is not None, "\n".join(error.toString() for error in component.errors())

    def invoke(name, *values):
        QMetaObject.invokeMethod(host, name, *[Q_ARG("QVariant", value) for value in values])

    def output(media):
        return media.audioOutput()

    def position_advances(media):
        position = media.position()
        wait_for(lambda: media.position() != position, "video keeps playing")

    main, other = host.findChild(QObject, "main"), host.findChild(QObject, "other")
    first = main.findChild(QMediaPlayer, "playerA")
    second = main.findChild(QMediaPlayer, "playerB")
    remote = other.findChild(QMediaPlayer, "playerA")
    main.setProperty("pathA", mp4.as_uri())
    main.setProperty("pathB", webm.as_uri())
    other.setProperty("pathA", webm.as_uri())
    wait_for(lambda: first.hasAudio() and second.hasAudio() and remote.hasAudio(), "MP4 and WebM expose tracks")
    wait_for(lambda: first.videoSink().videoFrame().isValid(), "MP4 produces a video frame")
    assert all(output(media) is None for media in (first, second, remote))
    invoke("change", "enabled", True)
    wait_for(lambda: output(first) is not None, "sound enabled while playing")
    assert output(second) is None and output(remote) is None
    invoke("change", "volume", 64)
    assert abs(output(first).volume() - 0.64) < 0.001
    invoke("change", "muted", True)
    assert output(first).isMuted()
    position_advances(first)
    invoke("change", "muted", False)
    assert not output(first).isMuted()

    invoke("change", "mode", "duck")
    wait_for(lambda: host.property("monitoring"), "one monitor starts on demand")
    playback_class = "Stream/Output/Audio"
    capture_class = "Stream/Input/Audio"
    own = stream(1, playback_class, props={"client.id": 19})
    player_node = {"application.name": "Firefox"}
    playback_link = link(12, 2, 30)
    microphone_link = link(13, 31, 3)
    baseline = [
        own, object_(19, "Client", props={"application.process.id": "4242"}),
        stream(4, playback_class, props={"node.group": "serpantinum-audio"},
               params={"Props": [{"mute": False, "channelVolumes": [1.0, 1.0]}]}),
        stream(2, playback_class, "idle", player_node), stream(3, capture_class),
        stream(30, "Audio/Sink"), stream(31, "Audio/Source"),
        link(11, 1, 30), playback_link, link(14, 4, 30), link(15, 30, 3)
    ]

    def feed(batch):
        invoke("feed", json.dumps(batch, indent=2))

    feed(baseline)
    assert host.property("pipewireReady") and not host.property("smartActive"), "\n".join(messages)
    assert abs(output(first).volume() - 0.64) < 0.001
    feed([stream(2, playback_class, props={**player_node, "pulse.corked": True})])
    assert not host.property("smartActive")
    feed([stream(2, playback_class, props=player_node, params={"Props": [{"mute": True}]})])
    assert not host.property("smartActive")
    feed([stream(2, playback_class, props=player_node), link(12, 2, 30, "paused")])
    assert not host.property("smartActive")
    feed([playback_link])
    assert host.property("smartActive")
    assert abs(output(first).volume() - 0.15) < 0.001 and not output(first).isMuted()
    invoke("change", "duckVolume", 80)
    assert abs(output(first).volume() - 0.64) < 0.001
    invoke("change", "mode", "mute")
    assert output(first).isMuted()
    position_advances(first)
    feed([{"id": 2, "info": None}])
    wait_for(lambda: not output(first).isMuted(), "volume restored after playback disappears")
    feed([microphone_link])
    assert output(first).isMuted()
    invoke("change", "reactToCalls", False)
    wait_for(lambda: not output(first).isMuted(), "microphone toggle restores volume")
    invoke("change", "reactToCalls", True)
    assert output(first).isMuted()
    invoke("feed", '[{"id":13,"info":null}]')
    wait_for(lambda: not output(first).isMuted(), "microphone disconnect restores volume")
    invoke("change", "reactToPlayback", False)
    feed([stream(2, playback_class, props=player_node)])
    assert not output(first).isMuted()
    feed([stream(2, playback_class, props={"media.role": "Communication"})])
    assert output(first).isMuted()
    invoke("change", "mode", "off")
    assert not host.property("monitoring") and not output(first).isMuted()

    host.setProperty("locked", True)
    assert output(first).isMuted()
    position_advances(first)
    host.setProperty("locked", False)
    assert not output(first).isMuted()
    main.setProperty("activeLayer", 1)
    second.play()
    assert output(first) is None and output(second) is not None
    invoke("change", "monitor", "HDMI-A-1")
    invoke("change", "source", "monitor")
    assert output(second) is None and output(remote) is not None
    invoke("disconnectOther")
    assert output(remote) is None
    invoke("reconnectOther")
    assert output(remote) is not None
    invoke("change", "source", "none")
    assert output(remote) is None
    invoke("change", "source", "primary")
    main.setProperty("pathB", silent_mp4.as_uri())
    wait_for(lambda: host.property("track") == "absent" and not second.hasAudio(), "silent MP4 exposes no track")
    assert output(second) is None
    assert second.playbackState() == QMediaPlayer.PlaybackState.PlayingState
    position_advances(second)
    wait_for(lambda: second.videoSink().videoFrame().isValid(), "silent MP4 produces a video frame")
    main.setProperty("activeLayer", 0)
    first.play()
    assert output(first) is not None
    main.setProperty("playbackPaused", True)
    first.stop()
    assert output(first) is None
    main.setProperty("playbackPaused", False)
    first.play()
    assert output(first) is not None
    invoke("change", "enabled", False)
    assert output(first) is None
    position_advances(first)
    wait_for(lambda: host.property("settingsPayload") and
             not json.loads(host.property("settingsPayload"))["wallpaperAudio"]["enabled"],
             "the real Config queues the final saved settings")
    saved = host.property("settingsPayload")
    assert json.loads(saved)["wallpaperAudio"]["volume"] == 64
    bash = shutil.which("bash")
    if os.name == "nt":
        git = shutil.which("git")
        bash = Path(git).parents[1] / "bin/bash.exe" if git else None
    if bash and Path(bash).is_file():
        # The QML Process is stubbed. Run the actual settings writer once, with
        # the exact arguments captured from Config in this fixture.
        command = host.property("settingsCommand").toVariant()
        settings_path = root / "settings.json"
        subprocess.run([str(bash), *command[1:]], check=True)
        saved = settings_path.read_text(encoding="utf-8")

    reloaded_qml = QQmlEngine()
    reloaded_qml.addImportPath(str(root))
    reloaded_component = QQmlComponent(reloaded_qml, QUrl.fromLocalFile(str(root / "Harness.qml")))
    reloaded_host = reloaded_component.create()
    assert reloaded_host is not None, "\n".join(error.toString() for error in reloaded_component.errors())
    QMetaObject.invokeMethod(reloaded_host, "loadSettings", Q_ARG("QVariant", saved))
    assert reloaded_host.property("baseVolume") == 64 and not reloaded_host.property("enabledAudio")
    assert not [message for message in messages if "TypeError:" in message or "ReferenceError:" in message
                or "Binding loop" in message], "\n".join(messages)

print("PASS: Qt media and controls, Config save/reload, audio routing, and simulated PipeWire activity")
