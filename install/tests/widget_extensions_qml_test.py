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
Not covered here (needs Fedora + Hyprland): real PTYs (terminal_pty_test.py
covers them on Linux), layer-shell keyboard focus, compositor hotkeys.
"""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

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

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src/quickshell"
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
    for rel in ("widgets/faces/network", "widgets/faces/filedock", "widgets/faces/terminal"):
        shutil.copytree(SRC / rel, root / rel)

    # ---- root singletons (stubs + the two real ones) -----------------------------
    write(root, "qmldir", "singleton NetStats 1.0 singletons/info/NetStats.qml\n"
                          "singleton TerminalTrust 1.0 singletons/system/TerminalTrust.qml\n"
                          "singleton ProcessExplorerController 1.0 singletons/widgetcontrols/ProcessExplorerController.qml\n")
    singleton(root, ".", "Caching",
              'property string serpantinumDir: "/opt/serpantinum"; '
              'function getStateDir(n) { return "/state/" + n; } '
              'function fileUrl(p) { return "file://" + p; }')
    singleton(root, ".", "Config", "property bool dataReady: true; property var data: ({}); signal settingsLoaded(); "
                                   "function getSetting(k, f) { return data[k] !== undefined ? data[k] : f; } "
                                   "function setSetting(k, v) { let d = Object.assign({}, data); d[k] = v; data = d; }")
    singleton(root, ".", "Scaler", "function s(v) { return v; }")
    singleton(root, ".", "I18n", "function t(key, fallback) { return typeof fallback === 'string' ? fallback : key; }")
    colors = ["base", "mantle", "crust", "text", "subtext0", "subtext1", "surface0", "surface1", "surface2",
              "overlay0", "overlay1", "overlay2", "red", "maroon", "peach", "yellow", "green", "teal",
              "sky", "sapphire", "blue", "lavender", "mauve", "pink", "flamingo", "rosewater"]
    singleton(root, ".", "ThemeBackend",
              " ".join(f'property color {c}: "#{(i * 2654435761) & 0xFFFFFF:06x}";' for i, c in enumerate(colors, 1))
              + ' property string fontFamily: "Sans"; property string iconFont: "Sans"; property int borderRadius: 12;'
                ' property int clampedBorderRadius: 12; property real elementOpacity: 0.8; property bool liquidGlass: false;'
                ' property bool glassActive: false')
    singleton(root, ".", "WidgetSync", "property var calls: []; function setProperty(m, id, p, v) { calls = calls.concat([[m, id, p, v]]); }")
    singleton(root, ".", "AppMatcher", "function resolve(n) { return n; } function entry(n) { return null; }")

    # ---- reusables stubs ---------------------------------------------------------------
    write(root, "reusables/qmldir", "WallpaperBlur 1.0 WallpaperBlur.qml\nGlassFill 1.0 GlassFill.qml\nClickButton 1.0 ClickButton.qml\n")
    write(root, "reusables/WallpaperBlur.qml", "import QtQuick\nItem { property real radius }")
    write(root, "reusables/GlassFill.qml", "import QtQuick\nItem { property bool active: false; property real radius; property color tintColor; property real tintAmount }")
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
    property bool blockLoading: false
    property bool watchChanges: false
    signal loaded()
    signal loadFailed(int error)
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
    function drop(key) { if (made[key]) { made[key].destroy(); delete made[key]; } return "ok"; }
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
    for v in ("Original", "Minimal", "Glass", "Graph", "Cyber", "Compact"):
        url = f"widgets/faces/network/NetworkFace{v}.qml"
        assert j("make", "p" + v, url, False) == "ok"
        assert j("make", "l" + v, url, True) == "ok"
    pump(0.3)
    assert j("get", "lGlass", "isLive") is True and j("get", "pGlass", "isLive") is False
    for v in ("Original", "Minimal", "Glass", "Graph", "Cyber", "Compact"):
        j("drop", "p" + v); j("drop", "l" + v)
    pump(0.1)
    passed.append("Network: 6 variants load as preview and live")

    # ---- File Dock -----------------------------------------------------------------------------
    for v in ("Floating", "Minimal", "Stack", "Expandable", "Grid", "Cyber"):
        assert j("make", "fp" + v, f"widgets/faces/filedock/FileDock{v}.qml", False) == "ok"
    pump(0.2)
    assert j("get", "fpGrid", "count") == 4                       # XDG defaults until edited
    j("call", "fpGrid", "openItem", "[0]")
    assert j("launched") == [], "a preview must not open anything"
    assert j("make", "dock", "widgets/faces/filedock/FileDockGrid.qml", True) == "ok"
    pump(0.2)
    procs_before = len(j("procs"))
    j("call", "dock", "addPath", json.dumps(["/home/u/My Files; rm -rf ~", True]))
    j("call", "dock", "addPath", json.dumps(["relative/path", False]))     # refused: not absolute
    assert j("get", "dock", "count") == 5
    items = json.loads(j("get", "dock", "itemsJson"))
    assert items[-1]["path"] == "/home/u/My Files; rm -rf ~"
    j("call", "dock", "moveItem", "[4, 0]")
    j("call", "dock", "openItem", "[0]")
    assert j("launched") == [["xdg-open", "/home/u/My Files; rm -rf ~"]], j("launched")
    j("call", "dock", "removeAt", "[0]")
    assert j("get", "dock", "count") == 4
    assert all("rm -rf" not in i["path"] for i in json.loads(j("get", "dock", "itemsJson")))
    assert len(j("launched")) == 1, "removing a shortcut must not run anything"
    assert len(j("procs")) == procs_before, "removing a shortcut must not start a process"
    assert any(c[2] == "itemsJson" and c[1] == "w1" for c in j("syncCalls")), "list persisted through WidgetSync"
    for v in ("Floating", "Minimal", "Stack", "Expandable", "Grid", "Cyber"):
        j("drop", "fp" + v)
    j("drop", "dock")
    passed.append("File Dock: 6 variants; shortcuts only; xdg-open with the path as one argument; persisted")

    # ---- Terminal: previews ----------------------------------------------------------------------
    for v in ("Transparent", "Glass", "Cyber", "Minimal", "Card"):
        assert j("make", "tp" + v, f"widgets/faces/terminal/Terminal{v}.qml", False) == "ok"
    pump(0.5)
    for v in ("Transparent", "Glass", "Cyber", "Minimal", "Card"):
        info = j("coreInfo", "tp" + v)
        assert info["status"] == "preview", info
        assert "user@serpantinum" in info["rows"][0] and "user@serpantinum" in info["html"], info["rows"][:2]
        assert info["running"] is False
    j("set", "tpCard", "mode", '"cmatrix"')
    pump(0.5)
    assert j("coreInfo", "tpCard")["status"] == "preview"
    assert not any("serp_pty.py" in " ".join(p["command"]) for p in j("procs")), "previews never start a PTY"
    for v in ("Transparent", "Glass", "Cyber", "Minimal", "Card"):
        j("drop", "tp" + v)
    passed.append("Terminal: 5 variants render previews without starting a process")

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

    noise = ("QQmlComponent: Created graphical object was not placed", "Font family", "propagateSizeHints")
    errors = [m for m in messages if not any(n in m for n in noise)]
    assert not errors, "\n".join(errors)
    for p in passed:
        print("PASS:", p)
    obj.close()
    del obj, component, engine
