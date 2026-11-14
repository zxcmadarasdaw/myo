"""Real Qt media and terminal grid with Quickshell I/O simulated."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import QMetaObject, QUrl, Q_ARG, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine


SOURCE = Path(__file__).resolve().parents[2] / "src/quickshell"
sys.path.insert(0, str(SOURCE.parent / "scripts/themess"))
from schema import configuration

appearance = {"theme": "glass_noir", "layout": "floating", "width": 48, "opacity": 0.9}
assert configuration("fastfetch", {"appearance": appearance}, {}, "Test") == (
    "fastfetchMedia", {"appearance": appearance}
)
for local_setting in ("path", "enabled", "playAudio"):
    try:
        configuration("fastfetch", {"appearance": appearance, local_setting: True}, {}, "Test")
    except ValueError:
        pass
    else:
        raise AssertionError(f"Themess allowed {local_setting}")

app = QGuiApplication([])
messages = []
qInstallMessageHandler(lambda kind, context, message: messages.append(message))


def wait_for(predicate, name):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        app.processEvents()
        if predicate():
            print(f"PASS: {name}")
            return
        time.sleep(0.015)
    raise AssertionError(name + "\n" + "\n".join(messages[-20:]))


def encode(path, *options):
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=s=96x64:r=12",
                    *options, str(path)], check=True)


with tempfile.TemporaryDirectory(prefix="fastfetch-qt-", ignore_cleanup_errors=True) as directory:
    root = Path(directory)

    def write(name, content):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    files = ["FastfetchMediaPane.qml", "TerminalFace.qml", "TerminalStyledFace.qml", "TerminalCore.qml", "TerminalEmulator.js", "qmldir"]
    for name in files:
        directory = "widgets/faces/terminal/"
        write(directory + name, (SOURCE / (directory + name)).read_text(encoding="utf-8"))
    for name in ("singletons/theme/FastfetchMedia.qml", "guide/display/FastfetchMediaSection.qml",
                 "singletons/system/Caching.qml"):
        write(name, (SOURCE / name).read_text(encoding="utf-8"))
    write("qmldir", """singleton FastfetchMedia 1.0 singletons/theme/FastfetchMedia.qml
singleton Caching 1.0 singletons/system/Caching.qml
singleton Config 1.0 Config.qml
singleton GpuCompatibility 1.0 GpuCompatibility.qml
singleton Wallpaper 1.0 Wallpaper.qml
singleton I18n 1.0 I18n.qml
singleton TerminalTrust 1.0 TerminalTrust.qml
singleton Scaler 1.0 Scaler.qml
singleton ThemeBackend 1.0 ThemeBackend.qml
""")
    write("Config.qml", """pragma Singleton
import QtQuick
QtObject {
    property var settings: ({})
    function getSetting(key, fallback) { return settings[key] ?? fallback; }
    function setSetting(key, value) {
        const next = JSON.parse(JSON.stringify(settings));
        let cursor = next;
        const fields = key.split(".");
        for (const field of fields.slice(0, -1)) {
            if (!cursor[field]) cursor[field] = {};
            cursor = cursor[field];
        }
        cursor[fields[fields.length - 1]] = value;
        settings = next;
    }
}
""")
    write("GpuCompatibility.qml", "pragma Singleton\nimport QtQuick\nQtObject { property var effective: ({fallback: false}); property bool shadersAllowed: false; property bool blurAllowed: false }")
    write("Wallpaper.qml", "pragma Singleton\nimport QtQuick\nQtObject { property bool captureLite: false; property bool sessionLocked: false; property var audioEngine: ({audioPlaying: false}) }")
    write("TerminalTrust.qml", "pragma Singleton\nimport QtQuick\nQtObject { function isTrusted(command) { return false; } }")
    write("I18n.qml", "pragma Singleton\nimport QtQuick\nQtObject { function t(key, fallback) { return fallback || key; } }")
    write("Scaler.qml", "pragma Singleton\nimport QtQuick\nQtObject { function s(value) { return value; } }")
    write("ThemeBackend.qml", """pragma Singleton
import QtQuick
QtObject {
    property string fontFamily: "monospace"
    property string iconFont: "sans-serif"
    property real elementOpacity: 0.8
    property int clampedBorderRadius: 8
    property int borderRadius: 8
""" + "\n".join(f'    property color {name}: "#455267"' for name in
                 "text base surface0 surface1 surface2 crust subtext0 subtext1 red peach green yellow blue pink teal mauve".split()) + "\n}")
    write("Quickshell/qmldir", "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n")
    write("Quickshell/Quickshell.qml", "pragma Singleton\nimport QtQuick\nQtObject { function env(key) { return ''; } }")
    write("Quickshell/Io/qmldir", "module Quickshell.Io\nProcess 1.0 Process.qml\nSplitParser 1.0 SplitParser.qml\nStdioCollector 1.0 StdioCollector.qml\n")
    write("Quickshell/Io/Process.qml", """import QtQuick
QtObject {
    property var command: []
    property bool running: false
    property bool stdinEnabled: false
    property var stdout
    property var stderr
    signal exited(int code, int status)
    function write(text) {}
}
""")
    write("Quickshell/Io/SplitParser.qml", "import QtQuick\nQtObject { property string splitMarker; signal read(string data) }")
    write("Quickshell/Io/StdioCollector.qml", "import QtQuick\nQtObject { property string text; signal streamFinished() }")
    write("reusables/qmldir", """WallpaperBlur 1.0 WallpaperBlur.qml
GlassFill 1.0 GlassFill.qml
FillButton 1.0 FillButton.qml
ClickButton 1.0 ClickButton.qml
Toggle 1.0 Toggle.qml
Dropdown 1.0 Dropdown.qml
Draggable 1.0 Draggable.qml
FilePicker 1.0 FilePicker.qml
""")
    write("reusables/WallpaperBlur.qml", "import QtQuick\nItem { property real radius }")
    write("reusables/GlassFill.qml", "import QtQuick\nItem { property real radius; property color tintColor; property bool allowed }")
    write("reusables/FillButton.qml", "import QtQuick\nItem { property string buttonText; signal triggered() }")
    write("reusables/ClickButton.qml", "import QtQuick\nItem { property string buttonText; property int textFontSize; property int cornerRadius; property color accentColor; property color textColor; signal clicked() }")
    write("reusables/Toggle.qml", "import QtQuick\nItem { property bool checked; property color accentColor; property color baseColor; property color handleColor; property color handleOffColor; signal toggled(bool value) }")
    write("reusables/Dropdown.qml", "import QtQuick\nItem { property int currentIndex; property int fontPixelSize; property var options; property color accentColor; property bool isOpen; function closePopup() {} signal selected(int index, string value) }")
    write("reusables/Draggable.qml", "import QtQuick\nItem { property real value; property real from; property real to; property real stepSize; property color backgroundColor; property color accentColor; property color handleColor; property var valueFormatter; signal moved(real value) }")
    write("reusables/FilePicker.qml", "import QtQuick\nItem { property var rootObj; property var nameFilters; property string titleText; function openWithOptionalPath(path) {} signal fileSelected(string path, string name) }")
    write("reusables/guide/SettingsRow.qml", "import QtQuick\nItem { property string title; property string description; property bool wrapText }")
    write("reusables/guide/SettingsGroup.qml", """import QtQuick
Item {
    property bool expanded
    property bool searchable
    property bool isOpen: expanded
    property var effectiveRootObj
    property string title
    property string description
    property string settingId
    property string icon
    property string searchKeywords
    property list<QtObject> subSettings
    function s(value) { return value; }
}
""")
    write("widgets/faces/common/FaceTone.qml", "import QtQuick\nQtObject { property color accent; property color accent2; property color hairline; property color hairlineStrong; property color muted; property color ink }")
    write("widgets/faces/common/LushCard.qml", "import QtQuick\nItem { property real radius; property real bodyOpacity; property real intensity; property bool ornate }")
    write("widgets/faces/common/FaceButton.qml", "import QtQuick\nItem { property bool lush; property bool primary; property color accent; property string text; property string iconFont; property int fontSize; signal clicked() }")
    write("Harness.qml", """import QtQuick
import "."
import "widgets/faces/terminal"
import "guide/display"
Item {
    id: host
    width: 520
    height: 300
    property bool present: true
    property bool showing: true
    property bool showTerminal: false
    readonly property bool ready: pane.item?.ready === true
    readonly property bool failed: pane.item?.failed === true
    readonly property bool playing: pane.item?.playing === true
    readonly property bool animated: pane.item?.animated === true
    readonly property bool vertical: pane.item?.vertical === true
    readonly property real leading: pane.item?.leadingSpace ?? 0
    readonly property real topSpace: pane.item?.topSpace ?? 0
    readonly property bool audio: FastfetchMedia.audioOwner === (pane.item || undefined) && FastfetchMedia.audioOwner !== null
    readonly property string builtCommand: terminal.buildCommand().slice(-1)[0]
    readonly property bool bothTerminalFacesReady: standard.hasFetchMedia && styled.hasFetchMedia
    readonly property string settingsJson: JSON.stringify(Config.settings)
    function set(key, value) { FastfetchMedia.set(key, value); }
    function load(value) { Config.settings = JSON.parse(value); }
    function toggle() { pane.item.togglePlayback(); }
    function wallpaper(value) { Wallpaper.audioEngine = {audioPlaying: value}; }
    Item {
        id: surface
        anchors.fill: parent
        visible: host.showing
        Loader {
            id: pane
            anchors.fill: parent
            active: host.present
            sourceComponent: FastfetchMediaPane { active: FastfetchMedia.enabled }
        }
    }
    TerminalCore { id: terminal; visible: false; mode: "fastfetch"; fetchLayout: host.ready ? FastfetchMedia.layout : "" }
    Item {
        property bool liveDesktopWidget: true
        anchors.fill: parent
        visible: host.showTerminal
        TerminalFace { id: standard; mode: host.showTerminal ? "fastfetch" : "interactive"; appearAnimation: "none" }
        TerminalStyledFace { id: styled; mode: standard.mode }
    }
    FastfetchMediaSection { visible: false }
}
""")

    images = {extension: root / f"test #100% кириллица.{extension}" for extension in ("png", "jpg", "gif", "webp", "mp4", "webm")}
    animated_webp = root / "animated.webp"
    for extension in ("png", "jpg", "webp"):
        encode(images[extension], "-frames:v", "1")
    encode(images["gif"], "-t", "1.5")
    encode(animated_webp, "-t", "1.5", "-c:v", "libwebp_anim", "-loop", "0")
    encode(images["mp4"], "-f", "lavfi", "-i", "sine=frequency=420", "-t", "2", "-c:v", "libx264", "-c:a", "aac")
    encode(images["webm"], "-t", "2", "-c:v", "libvpx-vp9")
    bad = root / "broken.mp4"
    bad.write_bytes(b"not a video")

    qml = QQmlEngine()
    qml.addImportPath(str(root))
    component = QQmlComponent(qml, QUrl.fromLocalFile(str(root / "Harness.qml")))
    host = component.create()
    assert host, "\n".join(error.toString() for error in component.errors())

    def invoke(name, *values):
        QMetaObject.invokeMethod(host, name, *[Q_ARG("QVariant", value) for value in values])

    def set_path(path):
        local = path.as_posix()
        invoke("set", "path", local if local.startswith("/") else "/" + local)

    assert host.property("builtCommand") == "fastfetch"
    invoke("set", "enabled", True)
    for extension in images:
        set_path(images[extension])
        wait_for(lambda: host.property("ready"), extension + " opens in the media pane")
        assert "--logo none" in host.property("builtCommand")
    for path in (images["gif"], animated_webp):
        set_path(path)
        wait_for(lambda: host.property("ready") and host.property("animated") and host.property("playing"),
                 path.suffix + " animation plays")
    invoke("set", "appearance", {"theme": "minimal"})
    assert host.property("builtCommand").endswith("OS:CPU:GPU:Memory")
    host.setProperty("width", 280)
    assert host.property("vertical") and host.property("topSpace") > 0 and host.property("leading") == 0
    host.setProperty("width", 520)
    assert host.property("leading") > 0 and not host.property("vertical")

    set_path(images["mp4"])
    wait_for(lambda: host.property("playing"), "video actually plays")
    assert not host.property("audio")
    invoke("set", "playAudio", True)
    wait_for(lambda: host.property("audio"), "video owns the opt-in audio output")
    invoke("wallpaper", True)
    assert not host.property("audio")
    invoke("set", "mixWallpaperAudio", True)
    assert host.property("audio")
    host.setProperty("showing", False)
    wait_for(lambda: not host.property("playing") and not host.property("audio"), "hidden widget pauses and releases audio")
    host.setProperty("showing", True)
    wait_for(lambda: host.property("playing"), "showing the widget resumes video")
    host.setProperty("present", False)
    wait_for(lambda: not host.property("ready") and not host.property("audio"), "closing destroys renderer and releases audio")
    host.setProperty("present", True)
    invoke("set", "autoplay", False)
    wait_for(lambda: host.property("ready") and not host.property("playing"), "autoplay off")
    invoke("toggle")
    wait_for(lambda: host.property("playing"), "manual playback")
    invoke("set", "loop", False)
    wait_for(lambda: not host.property("playing"), "video plays only once when looping is off")
    set_path(bad)
    wait_for(lambda: host.property("failed") and host.property("builtCommand") == "fastfetch", "damaged file restores standard Fastfetch")
    invoke("set", "path", "https://example.org/video.mp4")
    assert not host.property("ready")
    set_path(images["png"])
    saved = host.property("settingsJson")
    assert json.loads(saved)["fastfetchMedia"]["appearance"]["theme"] == "minimal"
    invoke("load", "{}")
    assert host.property("builtCommand") == "fastfetch"
    invoke("load", saved)
    wait_for(lambda: host.property("ready") and "--logo none" in host.property("builtCommand"), "restored settings re-enable media")
    host.setProperty("present", False)
    host.setProperty("showTerminal", True)
    wait_for(lambda: host.property("bothTerminalFacesReady"), "both desktop terminal implementations load Fastfetch Media")
    errors = [m for m in messages if "TypeError:" in m or "ReferenceError:" in m or "Binding loop" in m]
    assert not errors, "\n".join(errors)
