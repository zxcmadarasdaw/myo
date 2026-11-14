"""Qt test for the widget extensions (Network Monitor Pro, File Dock, Desktop Terminal).

    python3 install/tests/widget_extensions_qml_test.py      (needs PySide6)

The real QML of the new faces and singletons runs under Qt with Quickshell
stubbed (offscreen, no Wayland):
  * NetStats parses /proc/net/dev and /proc/net/route fixtures, computes
    per-interface speed, picks the default-route interface, samples only
    while a consumer is registered, and refuses ping hosts that look like
    options;
  * every Network and File Dock variant loads as a preview and as a live
    widget; File Dock removal only edits the shortcut list (no process is
    started, nothing on disk is touched) and opening goes to xdg-open with
    the path as one argument;
  * every Terminal variant renders its preview without starting anything;
    a live terminal speaks the serp_pty.py protocol (start, output, input,
    resize, missing program), refuses unapproved commands until the user
    approves them, and asks for the keyboard only after a click;
  * TerminalTrust persists approvals.
  * Restrained/Lush looks: every new `minimal`/`lush` key (or `<type>Minimal`
    where `minimal` was taken) is registered in WidgetRegistry.qml with its
    own icon and an I18n label, its file exists, the keys that were there
    before still point to their old files, and no new face overshoots
    (no OutBack/Elastic/Bounce). This part runs without PySide6.
    With PySide6, every new face loads, on a dark and a light theme, at its
    minimum and at a large size, as a preview and as a live widget, and
    previews never start anything.
Not covered here (needs Fedora + Hyprland): real PTYs (terminal_pty_test.py
covers them on Linux), layer-shell keyboard focus, compositor hotkeys.
"""
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src/quickshell"

# ---- Restrained / Lush looks: static checks (no Qt needed) ---------------------------------
# registry type -> (key of the restrained look, its file, key of the lush look, its file)
STYLED_VARIANTS = {
    "visualizer": ("minimal", "visualizer/VisualizerFaceRestrained.qml", "lush", "visualizer/VisualizerFaceLush.qml"),
    "time":       ("clockMinimal", "clock/ClockFaceRestrained.qml", "lush", "clock/ClockFaceLush.qml"),
    "music":      ("musicMinimal", "music/MusicFaceRestrained.qml", "lush", "music/MusicFaceLush.qml"),
    "weather":    ("minimal", "weather/WeatherFaceRestrained.qml", "lush", "weather/WeatherFaceLush.qml"),
    "image":      ("minimal", "image/ImageFaceRestrained.qml", "lush", "image/ImageFaceLush.qml"),
    "user":       ("minimal", "user/UserFaceRestrained.qml", "lush", "user/UserFaceLush.qml"),
    "cpu":        ("minimal", "usage/CpuFaceRestrained.qml", "lush", "usage/CpuFaceLush.qml"),
    "ram":        ("minimal", "usage/RamFaceRestrained.qml", "lush", "usage/RamFaceLush.qml"),
    "temp":       ("minimal", "usage/TempFaceRestrained.qml", "lush", "usage/TempFaceLush.qml"),
    "disk":       ("minimal", "usage/DiskFaceRestrained.qml", "lush", "usage/DiskFaceLush.qml"),
    "battery":    ("minimal", "battery/BatteryFaceRestrained.qml", "lush", "battery/BatteryFaceLush.qml"),
    "github":     ("minimal", "github/GithubFaceRestrained.qml", "lush", "github/GithubFaceLush.qml"),
    "notes":      ("minimal", "notes/NotesFaceRestrained.qml", "lush", "notes/NotesFaceLush.qml"),
    "timer":      ("minimal", "timer/TimerFaceRestrained.qml", "lush", "timer/TimerFaceLush.qml"),
    "text":       ("minimal", "text/TextFaceRestrained.qml", "lush", "text/TextFaceLush.qml"),
    "network":    ("networkMinimal", "network/NetworkFaceRestrained.qml", "lush", "network/NetworkFaceLush.qml"),
    "filedock":   ("filedockMinimal", "filedock/FileDockRestrained.qml", "lush", "filedock/FileDockLush.qml"),
    "terminal":   ("terminalMinimal", "terminal/TerminalRestrained.qml", "lush", "terminal/TerminalLush.qml"),
}
# `minimal` keys that existed before must keep their faces
KEPT_MINIMAL = {
    "time": "clock/ClockFaceMinimal.qml", "music": "music/MusicFaceMinimal.qml",
    "network": "network/NetworkFaceMinimal.qml", "filedock": "filedock/FileDockMinimal.qml",
    "terminal": "terminal/TerminalMinimal.qml",
}
VARIANT_RE = re.compile(r'^\s*"(\w+)":\s*\{\s*file:\s*"([^"]+)",\s*icon:\s*"([^"]*)",\s*label:\s*(.+?)\s*\},?\s*$')


def registry_variants(text, type_name):
    start = text.index(f'\n        "{type_name}": {{')
    block = text.index("variants: {", start)
    out = {}
    for line in text[block:].splitlines()[1:]:
        if re.match(r"^\s{12}\}", line):
            break
        m = VARIANT_RE.match(line)
        assert m, f"{type_name}: unparsed variant line: {line!r}"
        out[m.group(1)] = {"file": m.group(2), "icon": m.group(3), "label": m.group(4)}
    return out


def check_styled_registry():
    text = (SRC / "widgets/WidgetRegistry.qml").read_text(encoding="utf-8")
    faces = SRC / "widgets/faces"
    for type_name, (rkey, rfile, lkey, lfile) in STYLED_VARIANTS.items():
        variants = registry_variants(text, type_name)
        for key, rel, label_key, fallback in ((rkey, rfile, "restrained", "Restrained"), (lkey, lfile, "lush", "Lush")):
            assert key in variants, f"{type_name}: variant {key!r} is not registered"
            entry = variants[key]
            assert entry["file"] == "faces/" + rel, (type_name, key, entry["file"])
            assert (faces / rel).is_file(), f"{type_name}.{key}: {rel} does not exist"
            assert f'I18n.t("widgets.variants.{label_key}", "{fallback}")' in entry["label"], (type_name, key, entry["label"])
        icons = [v["icon"] for v in variants.values() if v["icon"] != "♫"]   # music's old entries share ♫
        assert len(icons) == len(set(icons)), f"{type_name}: icons are not unique: {icons}"
        assert all((faces.parent / v["file"]).is_file() for v in variants.values()), f"{type_name}: a registered file is missing"
        if type_name in KEPT_MINIMAL:
            assert variants["minimal"]["file"] == "faces/" + KEPT_MINIMAL[type_name], (type_name, variants["minimal"])
    for lang, (r, l) in (("en", ("Restrained", "Lush")), ("ru", ("Сдержанный", "Пышный"))):
        names = json.loads((ROOT / f"src/assets/languages/{lang}.json").read_text(encoding="utf-8"))["widgets"]["variants"]
        assert names.get("restrained") == r and names.get("lush") == l, (lang, names.get("restrained"), names.get("lush"))
    # the new looks never overshoot
    new_files = [faces / p for spec in STYLED_VARIANTS.values() for p in (spec[1], spec[3])]
    new_files += list((faces / "common").glob("*.qml")) + [
        faces / "filedock/FileDockStyledFace.qml", faces / "terminal/TerminalStyledFace.qml",
        faces / "notes/NotesStyledBase.qml", faces / "timer/TimerStyledBase.qml",
        faces / "usage/UsageFaceRestrained.qml", faces / "usage/UsageFaceLush.qml"]
    for f in new_files:
        body = f.read_text(encoding="utf-8")
        for bad in ("Easing.OutBack", "Easing.InOutBack", "Easing.OutElastic", "Easing.OutBounce", "SpringAnimation"):
            assert bad not in body, f"{f.relative_to(SRC)} uses {bad}"
    return len(STYLED_VARIANTS) * 2


STYLED_COUNT = check_styled_registry()
print(f"PASS: Restrained/Lush: {STYLED_COUNT} variants registered with files, unique icons and I18n labels; no overshoot")

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
if os.name == "nt":
    os.environ.setdefault("QT_QPA_FONTDIR", str(Path(os.environ["WINDIR"]) / "Fonts"))
try:
    from PySide6.QtCore import QObject, QUrl, Slot, QMetaObject, Q_ARG, Q_RETURN_ARG, QCoreApplication, QEvent, qInstallMessageHandler
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
except ImportError:
    print("SKIP: PySide6 is not installed")
    sys.exit(0)

app = QGuiApplication([])
messages = []
qInstallMessageHandler(lambda kind, context, message: messages.append(message))

DEV_1 = """Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 5000000    100    0    0    0     0          0         0  5000000     100    0    0    0     0       0          0
enp3s0: 1000000   2000    0    0    0     0          0         0   400000    1500    0    0    0     0       0          0
wlan0:   300000    700    0    0    0     0          0         0   100000     600    0    0    0     0       0          0
"""
ROUTE = """Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT
wlan0\t00000000\t0101A8C0\t0003\t0\t0\t600\t00000000\t0\t0\t0
enp3s0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0
"""


def write(root, name, content):
    target = root / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def singleton(root, directory, name, body, imports=""):
    write(root, Path(directory) / f"{name}.qml", f"pragma Singleton\nimport QtQuick\n{imports}\nQtObject {{ {body} }}")
    with (root / directory / "qmldir").open("a", encoding="utf-8") as registry:
        registry.write(f"singleton {name} 1.0 {name}.qml\n")


class Files(QObject):
    """Backs the FileView stub: fixture contents by path, and files it writes."""
    def __init__(self):
        super().__init__()
        self.data = {}

    @Slot(str, result=str)
    def read(self, path):
        return self.data.get(path, "")

    @Slot(str, result=bool)
    def exists(self, path):
        return path in self.data

    @Slot(str, str)
    def save(self, path, text):
        self.data[path] = text


files = Files()
files.data["/proc/net/dev"] = DEV_1
files.data["/proc/net/route"] = ROUTE
files.data["/proc/net/wireless"] = ""

with tempfile.TemporaryDirectory(prefix="widget-ext-qml-") as directory:
    root = Path(directory)
    for rel in ("singletons/info/NetStats.qml", "singletons/system/TerminalTrust.qml",
                "singletons/widgetcontrols/ProcessExplorerController.qml",
                "singletons/widgetcontrols/ScreenToggleController.qml"):
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SRC / rel, root / rel)
    for rel in ("widgets/faces/network", "widgets/faces/filedock", "widgets/faces/terminal",
                "widgets/faces/common", "widgets/faces/clock", "widgets/faces/text", "widgets/faces/visualizer",
                "widgets/faces/image", "widgets/faces/weather", "widgets/faces/battery", "widgets/faces/usage",
                "widgets/faces/music", "widgets/faces/timer", "widgets/faces/user", "widgets/faces/notes",
                "widgets/faces/github"):
        shutil.copytree(SRC / rel, root / rel)
    # real reusables used by the new faces (the rest of reusables/ is stubbed below)
    for rel in ("reusables/display/ImageBox.qml", "reusables/display/BoundedImage.qml",
                "reusables/display/LoaderIcon.qml", "reusables/behavior/SubscriptionGate.qml",
                "reusables/media/Visualizer.qml", "quickactions/actions/NotesFormat.js"):
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SRC / rel, root / rel)

    # ---- root singletons (stubs + the two real ones) -----------------------------
    write(root, "qmldir", "singleton NetStats 1.0 singletons/info/NetStats.qml\n"
                          "singleton TerminalTrust 1.0 singletons/system/TerminalTrust.qml\n"
                          "singleton ProcessExplorerController 1.0 singletons/widgetcontrols/ProcessExplorerController.qml\n")
    singleton(root, ".", "Caching",
              'property string serpantinumDir: "/opt/serpantinum"; property string stateDir: "/state"; '
              'function getStateDir(n) { return "/state/" + n; } '
              'function fileUrl(p) { return "file://" + p; }')
    singleton(root, ".", "Config", "property bool dataReady: true; property var data: ({}); signal settingsLoaded(); "
                                   "property var rawSettings: ({}); "
                                   "function getSetting(k, f) { return data[k] !== undefined ? data[k] : f; } "
                                   "function setSetting(k, v) { let d = Object.assign({}, data); d[k] = v; data = d; }")
    singleton(root, ".", "Scaler", "function s(v) { return v; }")
    singleton(root, ".", "I18n", "function t(key, fallback) { return typeof fallback === 'string' ? fallback : key; }")
    # neutrals follow `light` so the new faces are loaded on a dark and on a light theme
    neutrals = {"base": ("#1e1e2e", "#eff1f5"), "mantle": ("#181825", "#e6e9ef"), "crust": ("#11111b", "#dce0e8"),
                "text": ("#cdd6f4", "#4c4f69"), "subtext0": ("#a6adc8", "#6c6f85"), "subtext1": ("#bac2de", "#5c5f77"),
                "surface0": ("#313244", "#ccd0da"), "surface1": ("#45475a", "#bcc0cc"), "surface2": ("#585b70", "#acb0be")}
    colors = ["overlay0", "overlay1", "overlay2", "red", "maroon", "peach", "yellow", "green", "teal",
              "sky", "sapphire", "blue", "lavender", "mauve", "pink", "flamingo", "rosewater"]
    singleton(root, ".", "ThemeBackend",
              "property bool light: false; "
              + " ".join(f'property color {c}: light ? "{lt}" : "{dk}";' for c, (dk, lt) in neutrals.items())
              + " ".join(f'property color {c}: "#{(i * 2654435761) & 0xFFFFFF:06x}";' for i, c in enumerate(colors, 1))
              + ' property string fontFamily: "Sans"; property string iconFont: "Sans"; property int borderRadius: 12;'
                ' property int clampedBorderRadius: 12; property real elementOpacity: 0.8; property bool liquidGlass: false;'
                ' property bool glassActive: false')
    # singletons read by the Restrained/Lush faces
    singleton(root, ".", "GpuCompatibility", "property bool blurAllowed: false; property bool shadersAllowed: false; "
                                             "property var effective: ({ profile: 'safe', blur: false, shaders: false }); "
                                             "function observeShader(k, s, l) {}")
    singleton(root, ".", "Sounds", "function playSfx(n) {}")
    singleton(root, ".", "Spectrum", "property int barCount: 32; property var barLevels: []; property int consumers: 0; "
                                     "function registerConsumer() { consumers++; } function unregisterConsumer() { consumers--; }")
    singleton(root, ".", "DateTime", 'property var now: new Date(2026, 10, 14, 10, 42); property string hour: "10"; '
                                     'property string minute: "42"; property string amPm: ""; property string dayName: "Saturday"; '
                                     'property string fullDate: "14 November 2026"')
    singleton(root, ".", "Weather", 'property string currentTemp: "21.4"; property string currentIcon: "☀"; '
                                    'property string currentHex: "#f9e2af"; property bool isReady: true; property bool isLoading: false; '
                                    'property var data: ({ city: "Paris", forecast: [{ desc: "Clear sky", max: 23, min: 12 }] })')
    singleton(root, ".", "Location", 'property string city: "Paris"')
    singleton(root, ".", "SysData", "property real cpu: 42; property real ramPercent: 61; property real ramGb: 9.8; "
                                    "property real temp: 57; property real diskPercent: 73; property real diskGb: 340; "
                                    "property real diskTotalGb: 476; property int subs: 0; "
                                    "function subscribe() { subs++; } function unsubscribe() { subs--; }")
    singleton(root, ".", "SystemInfo", 'property string username: "u"; property string hostname: "box"; '
                                       'property string avatarPath: ""; property string uptime: "3h 12m"; property bool isDesktop: false')
    singleton(root, ".", "MprisController", 'property var activePlayer: null; property string trackTitle: ""; '
                                            'property string trackArtist: ""; property string artUrl: ""; '
                                            'property bool isPlaying: false; property real livePosition: 0; property string selectedBus: ""')
    singleton(root, ".", "FocusTimer",
              "property var calls: []; property int activeMode: 0; property bool isTimerRunning: false; "
              "property bool isStopwatchRunning: false; property bool isPomoRunning: false; property real timerRemainingMs: 300000; "
              "property real timerPresetMs: 600000; property real swDisplayMs: 0; property real pomoRemainingMs: 1500000; "
              "property int pomoState: 0; property int pomoWorkLimit: 25; property int pomoShortBreakLimit: 5; "
              "property int pomoLongBreakLimit: 15; "
              "function rec(n, a) { calls = calls.concat([[n].concat(a || [])]); } "
              "function formatTime(ms, x) { let s = Math.floor(ms / 1000); return Math.floor(s / 60) + ':' + ('0' + s % 60).slice(-2); } "
              "function toggleMode(m) { rec('toggleMode', [m]); } function resetTimer() { rec('resetTimer'); } "
              "function stopwatchLapOrReset() { rec('stopwatchLapOrReset'); } function skipPomoPhase() { rec('skipPomoPhase'); } "
              "function setActiveMode(m) { rec('setActiveMode', [m]); activeMode = m; }")
    singleton(root, ".", "FloatingController", "property var calls: []; function showNotes(s) { calls = calls.concat([['showNotes']]); }")
    singleton(root, ".", "WidgetSync", "property var calls: []; function setProperty(m, id, p, v) { calls = calls.concat([[m, id, p, v]]); }")
    singleton(root, ".", "AppMatcher", "function resolve(n) { return n; } function entry(n) { return null; }")

    # ---- reusables stubs ---------------------------------------------------------------
    write(root, "reusables/qmldir", "WallpaperBlur 1.0 WallpaperBlur.qml\nGlassFill 1.0 GlassFill.qml\nClickButton 1.0 ClickButton.qml\n"
                                    "ImageBox 1.0 display/ImageBox.qml\nBoundedImage 1.0 display/BoundedImage.qml\n"
                                    "LoaderIcon 1.0 display/LoaderIcon.qml\nSubscriptionGate 1.0 behavior/SubscriptionGate.qml\n"
                                    "Visualizer 1.0 media/Visualizer.qml\nStyledText 1.0 StyledText.qml\n"
                                    "IconButton 1.0 IconButton.qml\nInput 1.0 Input.qml\nNumberSelector 1.0 NumberSelector.qml\n")
    write(root, "reusables/StyledText.qml", "import QtQuick\nText {}")
    write(root, "reusables/IconButton.qml", """import QtQuick
Item {
    property int size; property int cornerRadius; property string buttonIcon; property string iconFont; property int iconFontSize
    property color accentColor; property color textColor; property real bgOpacity
    implicitWidth: 30; implicitHeight: 30
    signal clicked()
}""")
    write(root, "reusables/Input.qml", """import QtQuick
Item {
    property string text; property string placeholderText; property color accentColor; property color baseColor
    property real bgOpacity; property int cornerRadius; property int fontPixelSize; property bool hasError; property int horizontalPadding
    property bool isBusy; property string leadingIcon; property bool showClearButton; property color subTextColor; property color textColor
    implicitWidth: 120; implicitHeight: 30
    signal accepted()
}""")
    write(root, "reusables/NumberSelector.qml", """import QtQuick
Item {
    property real value; property real from; property real to; property real stepSize; property int decimals
    property color accentColor; property color baseColor; property color buttonColor; property color buttonTextColor
    property color textColor; property int cornerRadius; property int fontPixelSize; property int iconFontSize
    implicitWidth: 120; implicitHeight: 30
}""")
    write(root, "reusables/WallpaperBlur.qml", "import QtQuick\nItem { property real radius }")
    write(root, "reusables/GlassFill.qml", "import QtQuick\nItem { property bool active: false; property real radius; property color tintColor; property real tintAmount; "
                                           "property real shadow; property real press; property real pulse }")
    write(root, "reusables/ClickButton.qml", """import QtQuick
Rectangle {
    property string buttonText; property string subText; property string buttonIcon; property string iconFont
    property int iconFontSize; property int textFontSize; property int horizontalPadding; property int cornerRadius
    property int maxWidth; property int maxTextWidth; property int contentAlignment; property color accentColor
    property color textColor; property bool action_highlight; property string clickSound; property real bgOpacity
    implicitWidth: 80; implicitHeight: 30
    signal clicked()
    signal rightClicked()
}""")

    # ---- Quickshell stubs ------------------------------------------------------------------
    write(root, "Quickshell/qmldir", "module Quickshell\n")
    singleton(root, "Quickshell", "Quickshell",
              'property var launched: []; property var envMap: ({ HOME: "/home/u" }); function env(n) { return envMap[n] || ""; } '
              'function execDetached(argv) { launched = launched.concat([argv]); } '
              'function iconPath(n, f) { return ""; } property var screens: []')
    write(root, "Quickshell/Wayland/qmldir", "module Quickshell.Wayland\nWlrLayer 1.0 WlrLayer.qml\n")
    write(root, "Quickshell/Wayland/WlrLayer.qml", "import QtQuick\nQtObject {}")
    write(root, "Quickshell/Hyprland/qmldir", "module Quickshell.Hyprland\n")
    singleton(root, "Quickshell/Hyprland", "Hyprland", "property var focusedMonitor: null; property var focusedWorkspace: null")
    write(root, "Quickshell/Io/qmldir", "module Quickshell.Io\nProcess 1.0 Process.qml\nSplitParser 1.0 SplitParser.qml\n"
                                        "StdioCollector 1.0 StdioCollector.qml\nFileView 1.0 FileView.qml\n")
    singleton(root, "Quickshell/Io", "ProcLog", "property var all: []; function add(p) { all = all.concat([p]); }")
    write(root, "Quickshell/Io/SplitParser.qml", 'import QtQuick\nQtObject { property string splitMarker: "\\n"; signal read(string data) }')
    write(root, "Quickshell/Io/StdioCollector.qml", 'import QtQuick\nQtObject { property string text: ""; signal streamFinished() }')
    write(root, "Quickshell/Io/Process.qml", """import QtQuick
QtObject {
    id: p
    property var command: []
    property bool running: false
    property bool stdinEnabled: false
    property var stdout
    property var stderr
    property var written: []
    property int starts: 0
    signal exited(int exitCode, int exitStatus)
    function write(s) { p.written = p.written.concat([s]); }
    function emitLine(s) { if (p.stdout) p.stdout.read(s); }
    Component.onCompleted: ProcLog.add(p)
    onRunningChanged: {
        if (running) { p.starts++; p.written = []; }
        else Qt.callLater(function() { if (p) p.exited(0, 0); });   // may be destroyed by then
    }
}""")
    write(root, "Quickshell/Io/FileView.qml", """import QtQuick
QtObject {
    id: f
    property string path: ""
    property bool printErrors: true
    property bool preload: true
    property bool blockLoading: false
    property bool watchChanges: false
    signal loaded()
    signal loadFailed(int error)
    signal fileChanged()
    function text() { return files.read(f.path); }
    function setText(t) { files.save(f.path, t); }
    function reload() { Qt.callLater(function() { if (files.exists(f.path)) f.loaded(); else f.loadFailed(1); }); }
    onPathChanged: reload()
}""")

    from enum import Enum
    from PySide6.QtCore import QEnum, Property
    from PySide6.QtQml import QmlElement, QmlUncreatable, qmlRegisterSingletonInstance
    QML_IMPORT_NAME = "Quickshell.Networking"
    QML_IMPORT_MAJOR_VERSION = 1

    @QmlElement
    @QmlUncreatable("enum only")
    class DeviceType(QObject):
        @QEnum
        class Kind(Enum):
            Wifi = 1
            Wired = 2

    class NetworkingStub(QObject):
        @Property("QVariantList", constant=True)
        def devices(self):
            return []

    networking = NetworkingStub()
    qmlRegisterSingletonInstance(NetworkingStub, "Quickshell.Networking", 1, 0, "Networking", networking)

    # Quickshell.Services.UPower (battery faces): a discharging laptop battery at 64 %
    QML_IMPORT_NAME = "Quickshell.Services.UPower"

    @QmlElement
    @QmlUncreatable("enum only")
    class UPowerDeviceState(QObject):
        @QEnum
        class State(Enum):
            Unknown = 0
            Charging = 1
            Discharging = 2
            Empty = 3
            FullyCharged = 4

    class BatteryStub(QObject):
        @Property(bool, constant=True)
        def ready(self):
            return True

        @Property(bool, constant=True)
        def isLaptopBattery(self):
            return True

        @Property(float, constant=True)
        def percentage(self):
            return 0.64

        @Property(int, constant=True)
        def state(self):
            return 2

        @Property(float, constant=True)
        def timeToEmpty(self):
            return 7200.0

        @Property(float, constant=True)
        def timeToFull(self):
            return 0.0

    class UPowerStub(QObject):
        def __init__(self):
            super().__init__()
            self._device = BatteryStub(self)

        @Property(QObject, constant=True)
        def displayDevice(self):
            return self._device

    upower = UPowerStub()
    qmlRegisterSingletonInstance(UPowerStub, "Quickshell.Services.UPower", 1, 0, "UPower", upower)

    write(root, "Harness.qml", """import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "."
Window {
    id: host
    width: 900; height: 700; visible: true
    Item { id: liveHost; property bool liveDesktopWidget: true; property string widgetId: "w1"; property string widgetMonitor: "DP-1"; width: 560; height: 320 }
    Item { id: previewHost; width: 320; height: 180 }
    property var made: ({})
    function make(key, url, live) {
        let c = Qt.createComponent(url);
        if (c.status !== Component.Ready) return "ERROR " + c.errorString();
        let o = c.createObject(live ? liveHost : previewHost);
        if (!o) return "ERROR create " + url;
        made[key] = o;
        return "ok";
    }
    function drop(key) { if (made[key]) { made[key].destroy(); delete made[key]; } if (hosts[key]) { hosts[key].destroy(); delete hosts[key]; } return "ok"; }
    // Restrained/Lush faces: one host per face, sized, live or not, with face properties
    property var hosts: ({})
    Component { id: hostComp; Item { property bool liveDesktopWidget: false; property string widgetId: "w2"; property string widgetMonitor: "DP-1" } }
    function makeAt(key, url, live, props, w, h) {
        let c = Qt.createComponent(url);
        if (c.status !== Component.Ready) return "ERROR " + c.errorString();
        let hostItem = hostComp.createObject(host.contentItem, { liveDesktopWidget: live, width: w, height: h });
        let o = c.createObject(hostItem, JSON.parse(props));
        if (!o) { hostItem.destroy(); return "ERROR create " + url; }
        made[key] = o;
        hosts[key] = hostItem;
        return "ok";
    }
    function resize(key, w, h) { hosts[key].width = w; hosts[key].height = h; return "ok"; }
    function setLight(on) { ThemeBackend.light = on; return "ok"; }
    function focusCalls() { return JSON.stringify(FocusTimer.calls); }
    function floatingCalls() { return JSON.stringify(FloatingController.calls); }
    function counters() { return JSON.stringify({ spectrum: Spectrum.consumers, sys: SysData.subs }); }
    function get(key, prop) { return JSON.stringify(made[key][prop]); }
    function set(key, prop, value) { made[key][prop] = JSON.parse(value); return "ok"; }
    function call(key, fn, args) { let r = made[key][fn].apply(made[key], JSON.parse(args)); return JSON.stringify(r === undefined ? null : r); }
    function netStats(name) { return JSON.stringify(NetStats.stats(name)); }
    function netRegister(token, ms) { NetStats.register(token, ms, false, ""); return JSON.stringify(NetStats.active); }
    function netUnregister(token) { NetStats.unregister(token); return JSON.stringify(NetStats.active); }
    function netValidHost(h) { return JSON.stringify(NetStats.validHost(h)); }
    function netDefault() { return JSON.stringify(NetStats.defaultInterface); }
    function netNames() { return JSON.stringify(NetStats.interfaceNames()); }
    function launched() { return JSON.stringify(Quickshell.launched); }
    function syncCalls() { return JSON.stringify(WidgetSync.calls); }
    function procs() { return JSON.stringify(ProcLog.all.filter(p => p !== null && p.command !== undefined).map(p => ({ command: p.command, running: p.running, starts: p.starts, written: p.written }))); }
    function ptyOf(key) {
        let core = findCore(made[key]);
        return core;
    }
    function findCore(item) {
        if (!item) return null;
        if (item.cellW !== undefined && item.term !== undefined) return item;
        for (let i = 0; i < item.children.length; i++) { let c = findCore(item.children[i]); if (c) return c; }
        return null;
    }
    function coreInfo(key) {
        let c = findCore(made[key]);
        if (!c) return "null";
        let rows = [];
        for (let i = 0; i < c.rows; i++) rows.push(c.term ? c.term.rowText(c.term.scrollbackLength() + i) : "");
        let html = (c.rowData || []).map(r => r ? r.segs.map(s => s.html).join("") : "").join("\\n");
        return JSON.stringify({ status: c.status, detail: c.statusDetail, rows: rows, html: html, engaged: c.engaged,
                                cols: c.cols, rowsN: c.rows, running: c.running });
    }
    function coreCall(key, fn, args) { let c = findCore(made[key]); let r = c[fn].apply(c, JSON.parse(args)); return JSON.stringify(r === undefined ? null : r); }
    function coreSet(key, prop, value) { let c = findCore(made[key]); c[prop] = JSON.parse(value); return "ok"; }
    function emitToPty(line) {
        for (let p of ProcLog.all) if (p.running && p.command.join(" ").indexOf("serp_pty.py") !== -1) { p.emitLine(line); return "ok"; }
        return "no pty";
    }
    function trusted(cmd) { return JSON.stringify(TerminalTrust.isTrusted(cmd)); }
    function approve(cmd) { TerminalTrust.approve(cmd); return "ok"; }
    function pe(fn, args) { let r = ProcessExplorerController[fn].apply(ProcessExplorerController, JSON.parse(args)); return JSON.stringify(r === undefined ? null : r); }
    function peProp(name) { return JSON.stringify(ProcessExplorerController[name]); }
    function peSet(name, value) { ProcessExplorerController[name] = JSON.parse(value); return "ok"; }
    function setEnv(name, value) { let m = Object.assign({}, Quickshell.envMap); m[name] = value; Quickshell.envMap = m; return "ok"; }
    function clearLaunched() { Quickshell.launched = []; return "ok"; }
    function finishProc(needle, text) {
        for (let p of ProcLog.all) {
            if (p && p.running && p.command.join(" ").indexOf(needle) !== -1) {
                p.stdout.text = text;
                p.stdout.streamFinished();
                p.running = false;
                return "ok";
            }
        }
        return "ERROR no running process matching " + needle;
    }
}""")

    engine = QQmlEngine()
    engine.addImportPath(str(root))
    engine.rootContext().setContextProperty("files", files)
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(root / "Harness.qml")))
    obj = component.create()
    assert obj is not None, "\n".join(error.toString() for error in component.errors())

    def call(name, *args):
        value = QMetaObject.invokeMethod(obj, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])
        return value

    def j(name, *args):
        value = call(name, *args)
        assert isinstance(value, str), (name, value)
        assert not value.startswith("ERROR"), value
        return json.loads(value) if value not in ("ok",) else value

    def pump(seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            app.processEvents()
            # destroy() is deferred; run the deletions as an event loop would
            QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
            time.sleep(0.005)

    def until(predicate, what, timeout=6):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            app.processEvents()
            if predicate():
                return
            time.sleep(0.005)
        raise AssertionError(f"timed out: {what}\n" + "\n".join(messages[-20:]))

    passed = []

    # ---- NetStats ------------------------------------------------------------------------
    assert j("netValidHost", "1.1.1.1") is True and j("netValidHost", "example.org") is True
    assert j("netValidHost", "-f") is False and j("netValidHost", "a b") is False and j("netValidHost", "") is False
    assert j("netRegister", "t1", 200) is True
    until(lambda: "enp3s0" in j("netNames"), "interfaces parsed")
    assert "lo" not in j("netNames")
    files.data["/proc/net/dev"] = DEV_1.replace("enp3s0: 1000000", "enp3s0: 1200000").replace("   400000", "   450000")
    until(lambda: j("netStats", "enp3s0")["rx"] > 0, "rx speed computed")
    eth = j("netStats", "enp3s0")
    assert eth["type"] == "ethernet", eth
    assert eth["rxTotal"] == 1200000 and eth["txTotal"] == 450000, eth
    assert 0 < eth["rx"] <= 200000 / 0.15, eth                   # 200 kB over at least ~0.2 s
    assert eth["tx"] > 0
    assert j("netStats", "wlan0")["type"] == "wifi"
    until(lambda: j("netDefault") == "enp3s0", "default route interface (lowest metric)")
    assert j("netStats", "auto")["name"] == "enp3s0"
    assert j("netUnregister", "t1") is False                      # no consumer: sampling stops
    passed.append("NetStats parsing, speeds, default route, consumer-driven sampling, ping host validation")

    # ---- Network faces ---------------------------------------------------------------------
    NET_VARIANTS = ("Original", "Minimal", "Glass", "Graph", "Cyber", "Compact", "Restrained", "Lush")
    for v in NET_VARIANTS:
        url = f"widgets/faces/network/NetworkFace{v}.qml"
        assert j("make", "p" + v, url, False) == "ok"
        assert j("make", "l" + v, url, True) == "ok"
    pump(0.3)
    assert j("get", "lGlass", "isLive") is True and j("get", "pGlass", "isLive") is False
    assert j("get", "lLush", "isLive") is True and j("get", "pRestrained", "isLive") is False
    for v in NET_VARIANTS:
        j("drop", "p" + v); j("drop", "l" + v)
    pump(0.1)
    passed.append(f"Network: {len(NET_VARIANTS)} variants load as preview and live")

    # ---- File Dock -----------------------------------------------------------------------------
    DOCK_VARIANTS = ("Floating", "Minimal", "Stack", "Expandable", "Grid", "Cyber", "Restrained", "Lush")
    for v in DOCK_VARIANTS:
        assert j("make", "fp" + v, f"widgets/faces/filedock/FileDock{v}.qml", False) == "ok"
    pump(0.2)
    for v in ("Grid", "Restrained", "Lush"):
        assert j("get", "fp" + v, "count") == 4                   # XDG defaults until edited
        j("call", "fp" + v, "openItem", "[0]")
    assert j("launched") == [], "a preview must not open anything"
    for dock_variant in ("Grid", "Lush", "Restrained"):           # the old face and the two new looks
        j("clearLaunched")
        assert j("make", "dock", f"widgets/faces/filedock/FileDock{dock_variant}.qml", True) == "ok"
        pump(0.2)
        procs_before = len(j("procs"))
        j("call", "dock", "addPath", json.dumps(["/home/u/My Files; rm -rf ~", True]))
        j("call", "dock", "addPath", json.dumps(["relative/path", False]))     # refused: not absolute
        assert j("get", "dock", "count") == 5, dock_variant
        items = json.loads(j("get", "dock", "itemsJson"))
        assert items[-1]["path"] == "/home/u/My Files; rm -rf ~"
        j("call", "dock", "moveItem", "[4, 0]")
        j("call", "dock", "openItem", "[0]")
        assert j("launched") == [["xdg-open", "/home/u/My Files; rm -rf ~"]], (dock_variant, j("launched"))
        j("call", "dock", "removeAt", "[0]")
        assert j("get", "dock", "count") == 4
        assert all("rm -rf" not in i["path"] for i in json.loads(j("get", "dock", "itemsJson")))
        assert len(j("launched")) == 1, "removing a shortcut must not run anything"
        assert len(j("procs")) == procs_before, "removing a shortcut must not start a process"
        assert any(c[2] == "itemsJson" and c[1] == "w1" for c in j("syncCalls")), "list persisted through WidgetSync"
        j("drop", "dock")
        pump(0.1)
    for v in DOCK_VARIANTS:
        j("drop", "fp" + v)
    passed.append(f"File Dock: {len(DOCK_VARIANTS)} variants; shortcuts only; xdg-open with the path as one argument; persisted")

    # ---- Terminal: previews ----------------------------------------------------------------------
    TERM_VARIANTS = ("Transparent", "Glass", "Cyber", "Minimal", "Card", "Restrained", "Lush")
    for v in TERM_VARIANTS:
        assert j("make", "tp" + v, f"widgets/faces/terminal/Terminal{v}.qml", False) == "ok"
    pump(0.5)
    for v in TERM_VARIANTS:
        info = j("coreInfo", "tp" + v)
        assert info["status"] == "preview", info
        assert "user@serpantinum" in info["rows"][0] and "user@serpantinum" in info["html"], info["rows"][:2]
        assert info["running"] is False
    j("set", "tpCard", "mode", '"cmatrix"')
    pump(0.5)
    assert j("coreInfo", "tpCard")["status"] == "preview"
    assert not any("serp_pty.py" in " ".join(p["command"]) for p in j("procs")), "previews never start a PTY"
    for v in TERM_VARIANTS:
        j("drop", "tp" + v)
    passed.append(f"Terminal: {len(TERM_VARIANTS)} variants render previews without starting a process")

    # ---- Terminal: live --------------------------------------------------------------------------
    def pty():
        found = [p for p in j("procs") if "serp_pty.py" in " ".join(p["command"]) and p["running"]]
        return found[0] if found else None

    assert j("make", "term", "widgets/faces/terminal/TerminalGlass.qml", True) == "ok"
    until(lambda: pty() is not None, "live terminal starts serp_pty.py")
    cmd = pty()["command"]
    assert cmd[0] == "python3" and cmd[1] == "/opt/serpantinum/scripts/system/serp_pty.py", cmd
    assert "--shell" in cmd and "--cols" in cmd and "--rows" in cmd, cmd
    assert j("get", "term", "wantsKeyboardFocus") is False, "no keyboard before a click"
    j("emitToPty", json.dumps({"t": "started", "pid": 42, "argv": ["bash"]}))
    j("emitToPty", json.dumps({"t": "out", "d": "\x1b[1;32mready\x1b[0m $ "}))
    until(lambda: j("coreInfo", "term")["rows"][0] == "ready $", "output reaches the screen")
    until(lambda: "ready" in j("coreInfo", "term")["html"], "row rendered")
    j("coreCall", "term", "sendText", '["ls -la\\r"]')
    assert {"t": "in", "d": "ls -la\r"} in [json.loads(w) for w in pty()["written"]]
    j("emitToPty", json.dumps({"t": "out", "d": "\x1b[6n"}))   # cursor position request answered
    until(lambda: any(json.loads(w).get("d", "").endswith("R") for w in pty()["written"]), "DSR reply written back")
    j("coreSet", "term", "engaged", "true")
    assert j("get", "term", "wantsKeyboardFocus") is True
    j("set", "term", "paused", "true")
    until(lambda: pty() is None, "paused terminal stops its process")
    j("set", "term", "paused", "false")
    until(lambda: pty() is not None, "unpaused terminal restarts")

    # unapproved command: nothing runs until approved
    j("set", "term", "command", '"htop"')
    until(lambda: j("coreInfo", "term")["status"] == "untrusted", "unapproved start command blocks the start")
    assert pty() is None
    assert j("trusted", "htop") is False
    j("approve", "htop")
    assert j("trusted", "htop") is True
    j("coreCall", "term", "start", "[]")
    until(lambda: pty() is not None, "approved command starts")
    j("emitToPty", json.dumps({"t": "started", "pid": 43, "argv": ["bash"]}))
    until(lambda: {"t": "in", "d": "htop\r"} in [json.loads(w) for w in pty()["written"]], "start command typed into the shell")
    assert json.loads(files.data["/state/terminal/trusted.json"])["commands"] == ["htop"]

    # monitor mode without a command, then a missing program
    j("set", "term", "command", '""')
    j("set", "term", "mode", '"monitor"')
    until(lambda: j("coreInfo", "term")["status"] == "nocommand", "monitor without a command")
    assert pty() is None
    j("set", "term", "mode", '"cava"')
    until(lambda: pty() is not None, "cava mode starts the bridge")
    assert pty()["command"][-4:] == ["--require", "cava", "--cmd", "cava"], pty()["command"]
    j("emitToPty", json.dumps({"t": "missing", "prog": "cava"}))
    until(lambda: j("coreInfo", "term")["status"] == "missing", "missing program reported")
    assert j("coreInfo", "term")["detail"] == "cava"
    j("drop", "term")
    pump(0.3)
    assert pty() is None, "destroying the widget stops the PTY"
    passed.append("Terminal live: protocol, input, DSR reply, focus on click, pause, trust gate, monitor/missing states")

    # the new terminal looks wire the same core: live start, keyboard only after a click, stop on destroy
    for v in ("Restrained", "Lush"):
        assert j("make", "term", f"widgets/faces/terminal/Terminal{v}.qml", True) == "ok"
        until(lambda: pty() is not None, f"Terminal{v}: live terminal starts serp_pty.py")
        assert j("get", "term", "wantsKeyboardFocus") is False, "no keyboard before a click"
        j("coreSet", "term", "engaged", "true")
        assert j("get", "term", "wantsKeyboardFocus") is True
        j("set", "term", "command", '"htop2"')
        until(lambda: j("coreInfo", "term")["status"] == "untrusted", f"Terminal{v}: unapproved command blocks the start")
        j("drop", "term")
        pump(0.3)
        assert pty() is None, f"Terminal{v}: destroying the widget stops the PTY"
    passed.append("Terminal Restrained/Lush live: start, focus on click, trust gate, stop on destroy")

    # ---- Restrained / Lush: every new face, both themes, small and large, preview and live ------
    styled = sorted({p for spec in STYLED_VARIANTS.values() for p in (spec[1], spec[3])})
    launched_before = len(j("launched"))
    procs_before = len(j("procs"))
    loaded = 0
    for light in (False, True):
        j("setLight", light)
        for rel in styled:
            url = "widgets/faces/" + rel
            key = "s_" + rel.replace("/", "_")
            assert j("makeAt", key + "p", url, False, json.dumps({"previewMode": True}), 320, 200) == "ok", rel
            assert j("makeAt", key + "l", url, True, "{}", 420, 260) == "ok", rel
            min_w = max(40, j("get", key + "l", "minWidth"))
            min_h = max(40, j("get", key + "l", "minHeight"))
            pump(0.05)
            j("resize", key + "l", min_w, min_h)       # smallest size the editor allows
            pump(0.05)
            j("resize", key + "l", 1100, 700)          # and a large one
            pump(0.05)
            j("resize", key + "p", min_w, min_h)
            pump(0.05)
            loaded += 2
        pump(0.6)                                      # let the appear animations finish
        for rel in styled:
            key = "s_" + rel.replace("/", "_")
            assert abs(j("get", key + "l", "opacity") - 1) < 1e-6, f"{rel}: appear animation did not finish"
            j("drop", key + "p"); j("drop", key + "l")
        pump(0.1)
    j("setLight", False)
    new_launches = j("launched")[launched_before:]
    assert new_launches == [], f"loading the new faces ran something: {new_launches}"
    new_procs = [p for p in j("procs")[procs_before:] if p["running"]]
    assert not any("serp_pty.py" in " ".join(p["command"]) for p in new_procs), "a styled preview started a PTY"
    assert j("counters") == {"spectrum": 0, "sys": 0}, j("counters")     # subscriptions released on destroy
    passed.append(f"Restrained/Lush: {len(styled)} faces load on dark and light themes, at minimum and large sizes, "
                  f"preview and live ({loaded} instances); nothing launched; subscriptions released")

    # previews ignore input, live faces act
    j("makeAt", "tp", "widgets/faces/timer/TimerFaceLush.qml", False, json.dumps({"previewMode": True}), 360, 280)
    j("call", "tp", "toggle", "[]"); j("call", "tp", "secondary", "[]"); j("call", "tp", "selectMode", "[2]")
    assert j("focusCalls") == [], "a timer preview must not touch FocusTimer"
    j("drop", "tp")
    j("makeAt", "tl", "widgets/faces/timer/TimerFaceRestrained.qml", True, "{}", 360, 280)
    j("call", "tl", "toggle", "[]"); j("call", "tl", "selectMode", "[2]"); j("call", "tl", "secondary", "[]")
    assert j("focusCalls") == [["toggleMode", 0], ["setActiveMode", 2], ["skipPomoPhase"]], j("focusCalls")
    j("drop", "tl")
    files.data["/state/quickactions/notes.json"] = json.dumps([
        {"id": 1, "title": "Groceries", "content": "milk\neggs", "updatedAt": 1, "pinned": False},
        {"id": 2, "title": "Pinned", "content": "top", "updatedAt": 2, "pinned": True}])
    j("makeAt", "nl", "widgets/faces/notes/NotesFaceLush.qml", True, "{}", 320, 300)
    until(lambda: len(j("get", "nl", "sortedNotes")) == 2, "notes face reads notes.json")
    assert [n["title"] for n in j("get", "nl", "sortedNotes")] == ["Pinned", "Groceries"], "pinned first"
    j("call", "nl", "openNotes", "[]")
    assert j("floatingCalls") == [["showNotes"]]
    j("drop", "nl")
    j("makeAt", "np", "widgets/faces/notes/NotesFaceRestrained.qml", False, json.dumps({"previewMode": True}), 320, 300)
    j("call", "np", "openNotes", "[]")
    assert j("floatingCalls") == [["showNotes"]], "a notes preview must not open the panel"
    j("drop", "np")
    pump(0.1)
    passed.append("Restrained/Lush: timer and notes previews ignore input; live faces drive FocusTimer and the notes panel")

    # ---- Process Explorer controller: settings and hotkey --------------------------------------
    assert j("peProp", "hotkey") == "SUPER + SHIFT + P" and j("peProp", "material") == "standard"
    assert j("peProp", "interval") == 2
    for good in ("SUPER + SHIFT + P", "super+alt+F12", "CTRL + mouse_272"):
        assert j("pe", "validHotkey", json.dumps([good])) is True, good
    injection = 'SUPER + P", hl.dsp.exec_cmd("rm -rf ~")) --'
    for bad in (injection, "SUPER + P; os.execute('x')", "", "A" * 65, "SUPER + ", None, 5):
        assert j("pe", "validHotkey", json.dumps([bad])) is False, bad
    assert j("pe", "normalizeHotkey", '["super+shift +  p"]') == "SUPER + SHIFT + p"
    j("clearLaunched")
    j("pe", "setSetting", '["hotkey", "SUPER + ALT + P"]')
    pump(0.1)
    assert j("peProp", "hotkey") == "SUPER + ALT + P"
    assert j("launched") == [], "not on Hyprland: nothing is run"
    j("setEnv", "HYPRLAND_INSTANCE_SIGNATURE", "abc")
    j("pe", "setSetting", '["hotkey", "SUPER + CTRL + P"]')
    pump(0.1)
    assert j("launched") == [], "nothing is bound before the existing binds are known"
    # fresh install: keybinds.lua already binds the default combo -> rebind to the chosen one
    j("finishProc", "hyprctl binds", json.dumps([
        {"modmask": 64, "key": "C", "dispatcher": "exec", "arg": "serpantinum msg toggle clipboard"},
        {"modmask": 65, "key": "P", "dispatcher": "exec", "arg": "serpantinum msg toggle processes"}]))
    pump(0.1)
    launched = j("launched")
    assert len(launched) == 1 and launched[0][:2] == ["hyprctl", "eval"], launched
    lua = launched[0][2]
    assert 'hl.unbind("SUPER + SHIFT + P")' in lua, lua
    assert 'hl.bind("SUPER + CTRL + P", hl.dsp.exec_cmd("serpantinum msg toggle processes"))' in lua, lua
    j("pe", "setSetting", json.dumps(["hotkey", injection]))     # invalid: falls back to the default combo
    pump(0.1)
    assert all("rm -rf" not in " ".join(a) for a in j("launched")), j("launched")
    assert j("peProp", "hotkey") == "SUPER + SHIFT + P"
    # updated install: keybinds.lua kept from before, no bind exists -> the combo is bound at runtime, once
    assert j("pe", "hasProcessesBind", '["not json"]') is False
    assert j("pe", "hasProcessesBind", json.dumps([json.dumps([{"arg": "serpantinum msg toggle processes"}])])) is True
    j("clearLaunched")
    j("peSet", "bindsChecked", "false")
    j("pe", "ensureBound", "[]")
    j("finishProc", "hyprctl binds", json.dumps([{"modmask": 64, "key": "C", "arg": "serpantinum msg toggle clipboard"}]))
    pump(0.1)
    launched = j("launched")
    assert launched == [["hyprctl", "eval", 'hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("serpantinum msg toggle processes"))']], launched
    passed.append("Process Explorer: updated installs without the keybinds.lua line get the hotkey bound at runtime, once")
    j("pe", "setSetting", '["material", "neon"]')
    j("pe", "setSetting", '["interval", 99]')
    assert j("peProp", "material") == "neon" and j("peProp", "interval") == 10
    j("pe", "setSetting", '["material", "chrome"]')
    assert j("peProp", "material") == "standard"
    passed.append("Process Explorer: hotkey validation (no Lua injection), hyprctl rebind only on Hyprland, settings clamped")

    noise = ("QQmlComponent: Created graphical object was not placed", "Font family", "propagateSizeHints",
             "QFontEngineFT: Failed to create FreeType font engine")   # icon glyphs without Nerd Fonts on the test machine
    errors = [m for m in messages if not any(n in m for n in noise)]
    assert not errors, "\n".join(errors)
    for p in passed:
        print("PASS:", p)
    obj.close()
    del obj, component, engine
