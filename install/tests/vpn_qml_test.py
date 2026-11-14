"""VPN Control Studio of the network panel, offscreen: VpnService.qml + network/vpn/*.qml +
VpnAppearance.qml + the Settings -> Theme -> VPN tab.

    python3 install/tests/vpn_qml_test.py [--shots DIR]

Loads the real QML (VpnService, VpnAppearance, VpnStudio with its sheets, ThemeVpnTab) with
stub Quickshell modules: the python backend is not run, every Process is a stub whose output
the test supplies. Checks:
  * the subscription link reaches the backend on stdin only (never argv, never the log);
  * the button says "connected" only after the backend's status confirmed it, and goes
    through connecting/disconnecting; a failed connect shows the reason and ends in "error";
  * the exit IP and its country are shown only after the ipcheck through the VPN, are
    cleared on disconnect and on a server change, and the check runs only while the VPN tab
    is open;
  * the server picker shows only the subscription's servers, "Unknown" for no country;
  * subscriptions: add / switch / rename / remove call the right commands;
  * sing-box download: live progress, speed, retry, cancel (nothing installed), success;
  * closed sheets are invisible AND disabled (cannot catch the mouse);
  * the six themes, preview / apply / cancel / reset / save as custom theme; the stored
    appearance holds no link or token;
  * the layouts never overlap the button and the nodes at any size;
  * no QML warnings or binding loops.
With --shots it saves screenshots of every theme and state. Needs PySide6; skipped without it.
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
QS = ROOT / "src/quickshell"

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
if os.name == "nt":
    os.environ.setdefault("QT_QPA_FONTDIR", str(Path(os.environ["WINDIR"]) / "Fonts"))
try:
    from PySide6.QtCore import QMetaObject, QObject, Q_ARG, Q_RETURN_ARG, QUrl, qInstallMessageHandler
    from PySide6.QtGui import QFontDatabase, QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
except ImportError:
    print("SKIP: PySide6 is not installed")
    sys.exit(0)

shots = None
if "--shots" in sys.argv:
    shots = Path(sys.argv[sys.argv.index("--shots") + 1])
    shots.mkdir(parents=True, exist_ok=True)

app = QGuiApplication([])
messages = []
qInstallMessageHandler(lambda kind, context, message: messages.append(message))

icon_family = ""
font_id = QFontDatabase.addApplicationFont(str(ROOT / "src/assets/fonts/SymbolsNerdFontMono-Regular.ttf"))
if font_id >= 0:
    icon_family = QFontDatabase.applicationFontFamilies(font_id)[0]

LANG = os.environ.get("VPN_QML_LANG", "ru")
ALL = json.loads((ROOT / f"src/assets/languages/{LANG}.json").read_text(encoding="utf-8"))
STRINGS = ALL["vpn"]
EN = json.loads((ROOT / "src/assets/languages/en.json").read_text(encoding="utf-8"))["vpn"]


def flatten(d, prefix="vpn."):
    out = {}
    for k, v in d.items():
        if isinstance(v, dict):
            out.update(flatten(v, prefix + k + "."))
        else:
            out[prefix + k] = v
    return out


# ---- i18n: every key used in the QML exists in en and ru ---------------------------------------
assert set(flatten(STRINGS)) == set(flatten(EN)), "en/ru vpn keys differ"
VPN_QML = sorted((QS / "network/vpn").glob("*.qml"))
used = set()
for f in VPN_QML + [QS / "singletons/system/VpnService.qml", QS / "network/NetworkPopup.qml",
                    QS / "guide/theme/ThemeVpnTab.qml"]:
    src = f.read_text(encoding="utf-8")
    prefix = "vpn.studio." if f.name == "ThemeVpnTab.qml" else "vpn."
    used |= {prefix + k for k in re.findall(r'(?<![\w])(?:[a-z]+\.)?tr\("([a-z_.]+)"\s*,', src)}
    used |= {k for k in re.findall(r'I18n\.t\("(vpn\.[a-z_.]+)"', src) if not k.endswith(".")}
    for dyn in re.findall(r'(?<![\w])(?:[a-z]+\.)?tr\("([a-z_.]+\.)"\s*\+', src):
        group = flatten(EN)
        assert any(k.startswith(prefix + dyn) for k in group), f"no keys for the dynamic group {prefix + dyn}"
missing = sorted(k for k in used if k not in flatten(EN))
assert not missing, f"keys used in QML but not in en.json: {missing}"
print(f"PASS: {len(used)} vpn.* keys used in QML exist in en.json and {LANG}.json")


def write(root, name, content):
    target = root / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def build(root):
    shutil.copytree(QS / "network/vpn", root / "network/vpn")
    (root / "singletons/system").mkdir(parents=True)
    (root / "singletons/theme").mkdir(parents=True)
    shutil.copy(QS / "singletons/system/VpnService.qml", root / "singletons/system/VpnService.qml")
    shutil.copy(QS / "singletons/theme/VpnAppearance.qml", root / "singletons/theme/VpnAppearance.qml")
    (root / "guide/theme").mkdir(parents=True)
    shutil.copy(QS / "guide/GuideTab.qml", root / "guide/GuideTab.qml")
    for name in ("ThemeVpnTab.qml", "VpnColorPicker.qml"):
        shutil.copy(QS / "guide/theme" / name, root / "guide/theme" / name)
    write(root, "guide/theme/qmldir", "ThemeVpnTab 1.0 ThemeVpnTab.qml\nVpnColorPicker 1.0 VpnColorPicker.qml\n")
    write(root, "qmldir", "singleton VpnService 1.0 singletons/system/VpnService.qml\n"
                          "singleton VpnAppearance 1.0 singletons/theme/VpnAppearance.qml\n"
                          "singleton Config 1.0 Config.qml\n"
                          "singleton Caching 1.0 Caching.qml\nsingleton I18n 1.0 I18n.qml\n"
                          "singleton Scaler 1.0 Scaler.qml\nsingleton ThemeBackend 1.0 ThemeBackend.qml\n")
    write(root, "Caching.qml", 'pragma Singleton\nimport QtQuick\nQtObject { property string serpantinumDir: "/opt/serpantinum/src" }')
    write(root, "Scaler.qml", "pragma Singleton\nimport QtQuick\nQtObject { function s(v) { return v; } }")
    write(root, "Config.qml", """pragma Singleton
import QtQuick
QtObject {
    property var rawSettings: ({})
    property int writes: 0
    function getSetting(key, fb) { let v = rawSettings[key]; return v === undefined ? fb : JSON.parse(JSON.stringify(v)); }
    function setSetting(key, value) {
        let next = JSON.parse(JSON.stringify(rawSettings));
        next[key] = JSON.parse(JSON.stringify(value));
        rawSettings = next;
        writes++;
    }
}""")
    write(root, "I18n.qml", """pragma Singleton
import QtQuick
QtObject {
    property string currentLang: "%s"
    function t(key, fb) { let v = strings[key]; return v !== undefined ? v : (typeof fb === "string" ? fb : key); }
}""" % LANG)
    write(root, "ThemeBackend.qml", """pragma Singleton
import QtQuick
QtObject {
    property color base: "#1e1e2e"; property color mantle: "#181825"; property color crust: "#11111b"
    property color text: "#cdd6f4"; property color subtext0: "#a6adc8"; property color subtext1: "#bac2de"
    property color surface0: "#313244"; property color surface1: "#45475a"; property color surface2: "#585b70"
    property color overlay0: "#6c7086"; property color overlay1: "#7f849c"; property color overlay2: "#9399b2"
    property color blue: "#89b4fa"; property color green: "#a6e3a1"; property color red: "#f38ba8"
    property color yellow: "#f9e2af"; property color peach: "#fab387"
    property string fontFamily: "Segoe UI"; property string iconFont: "%s"
    property int borderRadius: 18; property real elementOpacity: 0.92; property bool liquidGlass: false
}""" % icon_family)
    write(root, "reusables/qmldir", "WallpaperBlur 1.0 WallpaperBlur.qml\nSliderProgress 1.0 SliderProgress.qml\n")
    write(root, "reusables/WallpaperBlur.qml", "import QtQuick\nItem { property real radius; property real blurStrength: 1; "
                                               "property real rim; property real tint; property real topLeftRadius; "
                                               "property real topRightRadius; property real bottomLeftRadius; "
                                               "property real bottomRightRadius }")
    write(root, "reusables/SliderProgress.qml", """import QtQuick
Rectangle {
    property real from: 0; property real to: 100; property real value: 0; property color gradColor1
    signal moved(real val)
    radius: height / 2; color: "#45475a"
    Rectangle { height: parent.height; radius: height / 2; color: "#89b4fa"
                width: parent.width * Math.max(0, Math.min(1, (parent.value - parent.from) / Math.max(0.0001, parent.to - parent.from))) }
}""")
    write(root, "Quickshell/qmldir", "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n")
    write(root, "Quickshell/Quickshell.qml", "pragma Singleton\nimport QtQuick\nQtObject { property var launched: []; "
                                             "function execDetached(argv) { launched = launched.concat([argv]); } }")
    write(root, "Quickshell/Io/qmldir", "module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n"
                                        "SplitParser 1.0 SplitParser.qml\nsingleton ProcLog 1.0 ProcLog.qml\n")
    write(root, "Quickshell/Io/ProcLog.qml", "pragma Singleton\nimport QtQuick\nQtObject { property var all: []; function add(p) { all = all.concat([p]); } }")
    write(root, "Quickshell/Io/StdioCollector.qml", 'import QtQuick\nQtObject { property string text: ""; signal streamFinished() }')
    write(root, "Quickshell/Io/SplitParser.qml", 'import QtQuick\nQtObject { signal read(string data) }')
    write(root, "Quickshell/Io/Process.qml", """import QtQuick
QtObject {
    id: p
    property var command: []
    property var environment: ({})
    property bool running: false
    property bool stdinEnabled: false
    property bool stdinClosed: false
    property var stdout
    property var written: []
    property var history: []
    property int starts: 0
    property int nextExit: 0
    signal started()
    signal exited(int exitCode, int exitStatus)
    function write(s) { p.written = p.written.concat([s]); }
    Component.onCompleted: ProcLog.add(p)
    onStdinEnabledChanged: if (!stdinEnabled && running) stdinClosed = true
    onRunningChanged: {
        if (running) {
            p.starts++; p.written = []; p.stdinClosed = false;
            p.history = p.history.concat([p.command.slice()]);
            Qt.callLater(function() { p.started(); });
        } else {
            let code = p.nextExit; p.nextExit = 0;
            Qt.callLater(function() { p.exited(code, 0); });
        }
    }
}""")
    write(root, "Harness.qml", """import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "network/vpn"
import "network/vpn/VpnGeometry.js" as Geo
import "guide/theme"
import "."

Window {
    id: win
    width: 720; height: 600
    visible: true
    color: "#0d0d14"

    VpnStudio { id: studio; objectName: "mainStudio"; anchors.fill: parent; active: true }

    Window {
        id: settingsWin
        width: 1100; height: 680
        visible: false
        color: "#11111b"
        Item {
            id: rootObj
            anchors.fill: parent
            property int currentTab: 0
            property int currentSubTab: 4
            property var pendingHighlightItem: null
            property string highlightedSettingId: ""
            property int deferredBuilds: 0
            function s(v) { return v; }
            ThemeVpnTab { id: vpnTab; rootObj: rootObj; tabIndex: 0 }
        }
    }

    function setActive(v) { studio.active = v; VpnService.panelOpen = v; return "ok"; }
    function start() { VpnService.panelOpen = true; VpnService.start(); return "ok"; }
    function procs() {
        let out = [];
        for (let p of ProcLog.all) out.push({ cmd: p.command, running: p.running, stdinEnabled: p.stdinEnabled,
                                               stdinClosed: p.stdinClosed, written: p.written, history: p.history,
                                               env: p.environment });
        return JSON.stringify(out);
    }
    function finish(needle, text, code) {
        for (let p of ProcLog.all) {
            if (p.running && p.command.join(" ").indexOf(needle) !== -1) {
                p.nextExit = code || 0;
                if (p.stdout && p.stdout.streamFinished !== undefined) { p.stdout.text = text; p.stdout.streamFinished(); }
                else if (p.stdout && p.stdout.read !== undefined) {
                    for (let line of text.split("\\n")) if (line !== "") p.stdout.read(line);
                }
                p.running = false;
                return "ok";
            }
        }
        return "ERROR no running process matching " + needle;
    }
    function stream(needle, line) {
        for (let p of ProcLog.all) {
            if (p.running && p.command.join(" ").indexOf(needle) !== -1) { p.stdout.read(line); return "ok"; }
        }
        return "ERROR no running process matching " + needle;
    }
    function svc() {
        return JSON.stringify({ state: VpnService.vpnState, phase: VpnService.phase, busy: VpnService.busy,
                                awaiting: VpnService.awaiting, error: VpnService.error, current: VpnService.current,
                                servers: VpnService.servers.length,
                                countries: VpnService.countries.map(c => [c.code, c.name, c.servers.length, c.best]),
                                pinging: VpnService.pinging, panelOpen: VpnService.panelOpen,
                                exitIp: VpnService.exitIp, ipState: VpnService.ipState,
                                subs: VpnService.subs, activeSub: VpnService.activeSub,
                                sb: { installing: VpnService.sbInstalling, stage: VpnService.sbStage, done: VpnService.sbDone,
                                      total: VpnService.sbTotal, speed: VpnService.sbSpeed, attempt: VpnService.sbAttempt,
                                      error: VpnService.sbError, result: VpnService.sbResult, checksum: VpnService.sbChecksum } });
    }
    function ui() {
        return JSON.stringify({ phaseText: studio.phaseText, message: studio.message, sheet: studio.sheet,
                                ip: studio.nodeInfo("ip"), location: studio.nodeInfo("location"),
                                server: studio.nodeInfo("server"), protocol: studio.nodeInfo("protocol") });
    }
    function call(fn, a, b) {
        switch (fn) {
        case "openSheet": studio.openSheet(a); break;
        case "back": return studio.back() ? "true" : "false";
        case "primary": studio.primary(); break;
        case "nodeClicked": studio.nodeClicked(a); break;
        case "addSub": VpnService.addSub(a, b); break;
        case "useSub": VpnService.useSub(a); break;
        case "renameSub": VpnService.renameSub(a, b); break;
        case "removeSub": VpnService.removeSub(a); break;
        case "select": VpnService.select(a); break;
        case "install": VpnService.installSingbox(); break;
        case "cancelInstall": VpnService.cancelInstall(); break;
        case "useSingbox": VpnService.useSingbox(a); break;
        case "previewTheme": VpnAppearance.previewTheme(a); break;
        case "preview": VpnAppearance.preview(a, b); break;
        case "apply": VpnAppearance.apply(); break;
        case "cancel": VpnAppearance.cancel(); break;
        case "reset": VpnAppearance.reset(); break;
        case "savePreset": return VpnAppearance.saveAsPreset(a);
        case "deletePreset": VpnAppearance.deletePreset(a); break;
        case "showSettings": settingsWin.visible = a === true; break;
        }
        return "ok";
    }
    function look() {
        return JSON.stringify({ style: VpnAppearance.style, themeId: VpnAppearance.themeId, current: VpnAppearance.currentTheme,
                                previewing: VpnAppearance.previewing, themes: VpnAppearance.themes.map(t => t.id),
                                presets: VpnAppearance.presets, stored: Config.rawSettings, writes: Config.writes,
                                sanitized: VpnAppearance.sanitize({ material: "plasma", background: "red", opacity: 7,
                                                                    lineWidth: "x", animate: "yes", radius: -5 }) });
    }
    function geometry() {
        let bad = [];
        let names = ["auto", "centered", "vertical", "horizontal", "compact", "expanded"];
        let styles = ["straight", "curved", "circuit", "flow", "minimal"];
        for (let n of names) for (let w = 360; w <= 1000; w += 80) for (let h = 300; h <= 700; h += 80) {
            let L = Geo.layout(n, w, h, 1);
            if (Geo.overlaps(L)) bad.push([n, w, h, "overlap"]);
            for (let id of Geo.NODE_IDS) {
                let r = L.nodes[id];
                if (r.x < 0 || r.y < 0 || r.x + L.nodeW > w || r.y + L.nodeH > h) bad.push([n, w, h, id, "outside"]);
            }
            for (let st of styles) for (let lk of Geo.links(st, L, 1)) if (!(lk.len > 1)) bad.push([n, w, h, st, lk.id, "short"]);
        }
        return JSON.stringify(bad);
    }
    function launched() { return JSON.stringify(Quickshell.launched); }
    property bool shotDone: false
    function shotTo(path, which) {
        shotDone = false;
        let target = which === "settings" ? settingsWin.contentItem : win.contentItem;
        target.grabToImage(function(r) { r.saveToFile(path); win.shotDone = true; });
        return "ok";
    }
    function isShotDone() { return shotDone ? "true" : "false"; }
}
""")


tmp = Path(tempfile.mkdtemp(prefix="serp-vpn-qml-"))
try:
    build(tmp)
    engine = QQmlEngine()
    engine.addImportPath(str(tmp))
    engine.rootContext().setContextProperty("strings", flatten(ALL, ""))
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(tmp / "Harness.qml")))
    win = component.create()
    assert win is not None, "\n".join(e.toString() for e in component.errors())

    def call(name, *args):
        return QMetaObject.invokeMethod(win, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])

    def j(name, *args):
        v = call(name, *args)
        assert isinstance(v, str) and not v.startswith("ERROR"), (name, v)
        return v if v in ("ok", "true", "false") else json.loads(v)

    def do(fn, a="", b=""):
        return call("call", fn, a, b)

    def finish(needle, data, code=0):
        return j("finish", needle, data if isinstance(data, str) else json.dumps(data), code)

    def pump(seconds=0.05):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            app.processEvents()
            time.sleep(0.005)

    def until(pred, what, timeout=5):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            app.processEvents()
            if pred():
                return
            time.sleep(0.005)
        raise AssertionError(f"timed out: {what}\n" + "\n".join(messages[-15:]))

    def running(needle):
        return [p for p in j("procs") if p["running"] and needle in " ".join(p["cmd"])]

    def answer_status(payload, pred, what, timeout=5):
        """Answer every status run (a stale one is followed by a fresh one) until pred() holds."""
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if running("status --json"):
                finish("status --json", payload)
            pump(0.03)
            if pred():
                return
        raise AssertionError(f"timed out: {what}\n" + "\n".join(messages[-15:]))

    def sheet_state(name):
        o = win.findChild(QObject, "mainStudio").findChild(QObject, "vpnSheet_" + name)
        assert o is not None, name
        return o.property("visible"), o.property("enabled")

    def shot(name, which="studio", settle=0.8):
        if shots is None:
            return
        pump(settle)
        path = shots / f"vpn-{name}.png"
        j("shotTo", str(path), which)
        until(lambda: call("isShotDone") == "true", "screenshot saved")
        print(f"      screenshot: {path}")

    S = flatten(STRINGS, "")
    STATUS_NONE = {"ok": True, "state": "none", "running": False, "hasSource": False, "hasConfig": False,
                   "singbox": True, "proxy": "127.0.0.1:2080", "current": "", "currentServer": None, "count": 0,
                   "delays": {}, "installHint": "sudo dnf install sing-box", "subscription": ""}
    SERVERS = [
        {"tag": "🇩🇪 Frankfurt 1", "name": "🇩🇪 Frankfurt 1", "protocol": "vless", "address": "de1.example.com", "port": 443,
         "country": "DE", "countryName": "Германия", "flag": "🇩🇪"},
        {"tag": "🇩🇪 Berlin 2", "name": "🇩🇪 Berlin 2", "protocol": "trojan", "address": "de2.example.com", "port": 443,
         "country": "DE", "countryName": "Германия", "flag": "🇩🇪"},
        {"tag": "🇳🇱 Amsterdam", "name": "🇳🇱 Amsterdam", "protocol": "vless", "address": "nl.example.com", "port": 443,
         "country": "NL", "countryName": "Нидерланды", "flag": "🇳🇱"},
        {"tag": "Fast node", "name": "Fast node", "protocol": "shadowsocks", "address": "203.0.113.9", "port": 8388,
         "country": "", "countryName": "", "flag": ""},
    ]
    SUB_A = {"id": "aaaaaaaa", "name": "Home VPN", "kind": "url", "host": "sub.example.net", "active": True,
             "lastUpdate": {"time": 1763100000, "ok": True, "servers": 4}}
    passed = []

    # ---- start ------------------------------------------------------------------------------
    j("start")
    until(lambda: running("status --json"), "status requested at start")
    until(lambda: running("subs --json"), "subscriptions listed at start")
    until(lambda: running("update --auto --json"), "auto update at start")
    backend = [p for p in j("procs") if p["cmd"][:1] == ["python3"]]
    assert backend and all(p["env"].get("SERP_VPN_LANG") == LANG for p in backend), "UI language is passed to the backend"
    finish("status --json", STATUS_NONE)
    finish("subs --json", {"active": "", "items": []})
    finish("update --auto", {"ok": True, "skipped": "no_source"})
    until(lambda: j("svc")["state"] == "none" and not j("svc")["busy"], "state none")
    u = j("ui")
    assert u["phaseText"] == S["state.none"] and u["message"]["text"] == S["hint.add"], u
    assert u["ip"]["value"] == "—" and u["location"]["value"] == S["unknown_country"], u
    for name in ("servers", "subs", "conn", "singbox"):
        assert sheet_state(name) == (False, False), (name, sheet_state(name))
    passed.append("start: status, subscriptions, auto update; empty state; every closed sheet invisible and disabled")
    shot("01-empty")

    # the big button opens the subscriptions sheet when there is nothing to connect to
    do("primary")
    until(lambda: sheet_state("subs") == (True, True), "subs sheet opened by the button")
    assert j("ui")["sheet"] == "subs"
    shot("02-subs-empty")

    # ---- add a subscription: the link goes on stdin only --------------------------------
    link = "https://sub.example.net/abc/PRIVATE-TOKEN-123"
    do("addSub", link, "Home VPN")
    until(lambda: running("sub-add"), "sub-add started")
    pump(0.1)
    p = running("sub-add")[0]
    assert link not in " ".join(p["cmd"]) and p["cmd"][2:] == ["sub-add", "--name=Home VPN", "--json"], p["cmd"]
    assert p["written"] == [link + "\n"] and p["stdinClosed"], p
    finish("sub-add", {"ok": True, "added": "aaaaaaaa", "servers": 4, "active": "aaaaaaaa", "items": [SUB_A]})
    until(lambda: j("svc")["subs"] and j("svc")["activeSub"] == "aaaaaaaa", "subscriptions list from the reply")
    until(lambda: running("status --json"), "status after add")
    status_off = dict(STATUS_NONE, state="disconnected", hasSource=True, hasConfig=True, count=len(SERVERS),
                      current=SERVERS[0]["tag"], currentServer=SERVERS[0], subscription="Home VPN",
                      lastUpdate={"time": 1763100000, "ok": True, "servers": 4})
    finish("status --json", status_off)
    until(lambda: running("list --json"), "server list requested")
    finish("list --json", {"ok": True, "servers": SERVERS})
    if running("subs --json"):
        finish("subs --json", {"active": "aaaaaaaa", "items": [SUB_A]})
    until(lambda: j("svc")["servers"] == len(SERVERS), "servers loaded")
    assert link not in "\n".join(messages), "the link must not be logged"
    countries = j("svc")["countries"]
    assert [c[0] for c in countries][-1] == "" and countries[-1][1] == S["unknown_country"], countries
    assert dict((c[0], c[2]) for c in countries)["DE"] == 2
    passed.append("subscription added: link on stdin (EOF), name via --name=, nothing in argv or log; "
                  "servers grouped by country, no country -> \"Unknown\"")

    # ---- the IP is never guessed before connecting ---------------------------------------------
    u = j("ui")
    assert u["ip"]["value"] == "—" and u["ip"]["sub"] == S["ip.after"], u["ip"]
    assert u["location"]["sub"] == S["loc.declared"], u["location"]          # from the name, marked as not verified
    assert not running("ipcheck"), "no IP check while disconnected"
    do("back")

    # ---- connect: connecting until the backend confirms ----------------------------------------
    pings = running("ping --json")
    if pings:
        finish("ping --json", {"ok": True, "delays": {SERVERS[0]["tag"]: 48, SERVERS[2]["tag"]: 95}})
    do("primary")
    until(lambda: running("connect --json"), "connect started")
    assert j("svc")["phase"] == "connecting"
    shot("03-connecting")
    finish("connect --json", {"ok": True})
    pump(0.05)
    assert j("svc")["phase"] == "connecting", "connected must wait for the confirming status"
    status_on = dict(status_off, state="connected", running=True)
    answer_status(status_on, lambda: j("svc")["phase"] == "connected", "connected after the status confirmed it")
    assert j("ui")["phaseText"] == S["state.connected"]
    passed.append("connect: phase connecting -> connected only after the confirming status")

    # exit IP read through the tunnel, then shown with its country
    until(lambda: running("ipcheck --json"), "exit IP checked after connecting", timeout=3)
    assert j("ui")["ip"]["value"] == "…"
    finish("ipcheck --json", {"ok": True, "ip": "203.0.113.50", "country": "DE", "countryName": "Германия",
                              "flag": "🇩🇪", "time": 1763100500, "via": "proxy", "server": SERVERS[0]["tag"]})
    until(lambda: j("svc")["ipState"] == "ok", "exit IP stored")
    u = j("ui")
    assert u["ip"]["value"] == "203.0.113.50" and u["location"]["value"] == "Германия", u
    assert u["location"]["sub"] == S["loc.verified"] and u["location"]["flag"] == "🇩🇪", u["location"]
    passed.append("exit IP and country appear only after ipcheck through the VPN")
    shot("04-connected")

    # ---- server picker; a server change clears the old IP ---------------------------------------
    do("nodeClicked", "server")
    until(lambda: sheet_state("servers") == (True, True), "server picker opened")
    until(lambda: running("ping --json"), "ping while the picker is open")
    finish("ping --json", {"ok": True, "delays": {SERVERS[0]["tag"]: 48, SERVERS[1]["tag"]: 0, SERVERS[2]["tag"]: 95}})
    shot("05-servers")
    do("select", SERVERS[2]["tag"])
    until(lambda: running("select"), "select started")
    assert j("svc")["exitIp"] is None, "old exit IP cleared when the server changes"
    assert j("svc")["phase"] == "connecting"
    finish("select", dict(status_on, current=SERVERS[2]["tag"]))
    answer_status(dict(status_on, current=SERVERS[2]["tag"], currentServer=SERVERS[2]),
                  lambda: j("svc")["phase"] == "connected", "connected after the switch")
    until(lambda: running("ipcheck --json"), "exit IP checked again after the switch", timeout=3)
    finish("ipcheck --json", {"ok": True, "ip": "198.51.100.7", "country": "DE", "countryName": "Германия",
                              "flag": "🇩🇪", "time": 1763100600, "via": "proxy"})
    until(lambda: j("svc")["ipState"] == "ok", "exit IP after the switch")
    loc = j("ui")["location"]
    assert loc["sub"] == S["loc.differs"] and loc["warn"], loc                # NL in the name, DE by the exit IP
    passed.append("server change: old IP cleared, rechecked; a country mismatch is reported, not hidden")
    do("back")

    # ---- the check runs only while the VPN tab is shown ---------------------------------------
    j("setActive", False)
    pump(0.02)
    assert all(not sheet_state(n)[1] for n in ("servers", "subs", "conn", "singbox")), "disabled at once when hidden"
    pump(0.4)
    assert not running("ipcheck") and not running("ping"), "nothing runs while the tab is hidden"
    for name in ("servers", "subs", "conn", "singbox"):
        assert sheet_state(name) == (False, False), name
    j("setActive", True)
    pump(0.1)

    # ---- disconnect -------------------------------------------------------------------------------
    do("primary")
    until(lambda: running("disconnect --json"), "disconnect started")
    assert j("svc")["phase"] == "disconnecting"
    finish("disconnect --json", {"ok": True})
    pump(0.05)
    assert j("svc")["phase"] == "disconnecting"
    answer_status(dict(status_off, current=SERVERS[2]["tag"], currentServer=SERVERS[2]),
                  lambda: j("svc")["phase"] == "disconnected", "disconnected")
    s = j("svc")
    assert s["exitIp"] is None and s["ipState"] == "", s
    assert j("ui")["ip"]["value"] == "—"
    passed.append("disconnect: disconnecting -> disconnected; the exit IP is forgotten")

    # ---- a failed connect: error with the reason, button usable again -------------------------
    do("primary")
    until(lambda: running("connect --json"), "second connect")
    err = {"ok": False, "error": {"code": "start_failed", "message": "sing-box не запустился: порт занят"}}
    finish("connect --json", err, 1)
    until(lambda: j("svc")["phase"] == "error", "error phase")
    answer_status(dict(status_off, current=SERVERS[2]["tag"], currentServer=SERVERS[2]),
                  lambda: not running("status --json"), "status after error")
    pump(0.1)
    s, u = j("svc"), j("ui")
    assert s["phase"] == "error" and not s["busy"], s
    assert u["message"]["level"] == "error" and u["message"]["text"].startswith("sing-box не запустился"), u["message"]
    shot("06-error")
    passed.append("failed connect: phase error with the backend's reason; the button is usable again")

    # a connect that reports ok but the status still says disconnected is NOT shown as connected
    do("primary")
    until(lambda: running("connect --json"), "third connect")
    finish("connect --json", {"ok": True})
    answer_status(dict(status_off, current=SERVERS[2]["tag"], currentServer=SERVERS[2]),
                  lambda: j("svc")["phase"] == "disconnected", "not confirmed -> disconnected")
    passed.append("a connect the status does not confirm never shows \"connected\"")

    # ---- subscriptions: switch, rename, remove ------------------------------------------------
    do("useSub", "bbbbbbbb")
    until(lambda: running("sub-use"), "sub-use")
    assert running("sub-use")[0]["cmd"][2:] == ["sub-use", "bbbbbbbb", "--json"]
    finish("sub-use", {"ok": True, "active": "bbbbbbbb", "items": [dict(SUB_A, active=False),
                       {"id": "bbbbbbbb", "name": "Work", "kind": "links", "count": 2, "active": True}]})
    until(lambda: j("svc")["activeSub"] == "bbbbbbbb", "active subscription switched")
    for needle in ("status --json", "list --json", "subs --json"):
        if running(needle):
            finish(needle, status_off if needle == "status --json" else
                   ({"ok": True, "servers": SERVERS} if needle == "list --json" else {"active": "bbbbbbbb", "items": []}))
    do("renameSub", "bbbbbbbb", "  Работа  ")
    until(lambda: running("sub-rename"), "sub-rename")
    assert running("sub-rename")[0]["cmd"][2:] == ["sub-rename", "bbbbbbbb", "Работа", "--json"]
    finish("sub-rename", {"ok": True, "active": "bbbbbbbb", "items": []})
    until(lambda: not j("svc")["busy"], "rename done")
    for needle in ("status --json", "list --json", "subs --json"):
        if running(needle):
            finish(needle, status_off if needle == "status --json" else
                   ({"ok": True, "servers": SERVERS} if needle == "list --json" else {"active": "bbbbbbbb", "items": []}))
    do("removeSub", "bbbbbbbb")
    until(lambda: running("sub-remove"), "sub-remove")
    finish("sub-remove", {"ok": True, "active": "aaaaaaaa", "items": [SUB_A]})
    until(lambda: not j("svc")["busy"], "remove done")
    for needle in ("status --json", "list --json", "subs --json"):
        if running(needle):
            finish(needle, status_off if needle == "status --json" else
                   ({"ok": True, "servers": SERVERS} if needle == "list --json" else {"active": "aaaaaaaa", "items": [SUB_A]}))
    passed.append("subscriptions: switch / rename / remove run sub-use / sub-rename / sub-remove with the id")

    # ---- sing-box download: progress, retry, cancel, success ------------------------------------
    do("openSheet", "singbox")
    until(lambda: running("singbox-info"), "singbox-info when the sheet opens")
    finish("singbox-info", {"ok": True, "path": "", "source": "", "version": "", "works": False, "candidates": [
        {"path": "/usr/local/bin/sing-box", "system": True}], "tunUsable": False, "installHint": "sudo dnf install sing-box"})
    do("install")
    until(lambda: running("singbox-install"), "install started")
    j("stream", "singbox-install", json.dumps({"event": "stage", "stage": "release"}))
    j("stream", "singbox-install", json.dumps({"event": "stage", "stage": "download", "version": "1.12.9",
                                                "total": 14000000, "checksum": True}))
    j("stream", "singbox-install", json.dumps({"event": "progress", "done": 7000000, "total": 14000000, "speed": 2100000, "attempt": 1}))
    sb = j("svc")["sb"]
    assert sb["installing"] and sb["stage"] == "download" and sb["done"] == 7000000 and sb["speed"] == 2100000 and sb["checksum"], sb
    j("stream", "singbox-install", json.dumps({"event": "retry", "attempt": 2, "of": 4, "wait": 2}))
    assert j("svc")["sb"]["attempt"] == 2
    shot("07-singbox-progress")
    do("cancelInstall")
    until(lambda: not j("svc")["sb"]["installing"], "cancelled")
    sb = j("svc")["sb"]
    assert sb["result"] is None and sb["error"] == S["singbox.cancelled"], sb
    if running("singbox-info"):
        finish("singbox-info", {"ok": True, "path": "", "source": "", "works": False, "candidates": []})
    if running("status --json"):
        finish("status --json", status_off)
    do("install")
    until(lambda: running("singbox-install"), "install again")
    finish("singbox-install", "\n".join(json.dumps(e) for e in (
        {"event": "stage", "stage": "release"},
        {"event": "stage", "stage": "download", "version": "1.12.9", "total": 14000000, "checksum": True},
        {"event": "progress", "done": 14000000, "total": 14000000, "speed": 0, "attempt": 1},
        {"event": "stage", "stage": "verify"}, {"event": "stage", "stage": "extract"}, {"event": "stage", "stage": "test"},
        {"ok": True, "path": "/home/u/.local/share/serpantinum/vpn/bin/sing-box", "version": "1.12.9",
         "verified": True, "source": "api"})))
    until(lambda: j("svc")["sb"]["result"] is not None and not j("svc")["sb"]["installing"], "installed")
    assert j("svc")["sb"]["error"] == "" and j("svc")["sb"]["stage"] == "done"
    until(lambda: running("singbox-info"), "info refreshed after install")
    finish("singbox-info", {"ok": True, "path": "/home/u/.local/share/serpantinum/vpn/bin/sing-box", "source": "managed",
                            "version": "1.12.9", "works": True, "candidates": [], "tunUsable": False,
                            "installHint": "sudo dnf install sing-box"})
    if running("status --json"):
        finish("status --json", status_off)
    shot("08-singbox-done")
    passed.append("sing-box download: live progress/speed/attempt, Cancel installs nothing, success only with the backend's result")

    # a failed install keeps the reason for Retry
    do("install")
    until(lambda: running("singbox-install"), "install third time")
    finish("singbox-install", json.dumps({"ok": False, "error": {"code": "sb_checksum", "message": "Контрольная сумма не совпала"}}), 1)
    until(lambda: not j("svc")["sb"]["installing"], "failed install finished")
    assert j("svc")["sb"]["error"] == "Контрольная сумма не совпала" and j("svc")["sb"]["result"] is None
    for needle in ("singbox-info", "status --json"):
        if running(needle):
            finish(needle, status_off if needle == "status --json" else {"ok": True, "works": True, "candidates": []})
    do("useSingbox", "/usr/local/bin/sing-box")
    until(lambda: running("singbox-use"), "singbox-use")
    assert running("singbox-use")[0]["cmd"][2:] == ["singbox-use", "/usr/local/bin/sing-box", "--json"]
    finish("singbox-use", {"ok": True, "path": "/usr/local/bin/sing-box", "source": "chosen", "works": True})
    until(lambda: not j("svc")["busy"], "use finished")
    for needle in ("singbox-info", "status --json", "list --json"):
        if running(needle):
            finish(needle, status_off if needle == "status --json" else {"ok": True, "works": True, "candidates": [], "servers": SERVERS})
    passed.append("failed download keeps the reason (Retry); choosing an installed sing-box runs singbox-use PATH")

    # Escape closes the open sheet first
    assert j("ui")["sheet"] == "singbox"
    assert do("back") == "true" and do("back") == "false"
    until(lambda: sheet_state("singbox") == (False, False), "sheet closed by Escape")

    # ---- geometry --------------------------------------------------------------------------------
    bad = j("geometry")
    assert not bad, bad[:10]
    passed.append("layouts: no node overlaps the button or another node, all inside, every line drawn (6 layouts x 5 styles x 54 sizes)")

    # ---- appearance: themes, preview / apply / cancel / reset / presets ------------------------------
    lk = j("look")
    assert lk["themes"] == ["obsidian_glass", "liquid_noir", "midnight_blue", "graphite", "soft_neon", "pure_minimal"], lk["themes"]
    san = lk["sanitized"]
    assert san["material"] == "glass" and san["background"] == "#0b0d12" and san["opacity"] == 1 and san["lineWidth"] == 1.4 \
        and san["animate"] is True and san["radius"] == 0, san
    for t in lk["themes"]:
        do("previewTheme", t)
        pump(0.05)
        shot(f"10-theme-{t}", settle=1.0)
    do("cancel")
    lk = j("look")
    assert not lk["previewing"] and lk["writes"] == 0, "previewing writes nothing"
    do("previewTheme", "graphite")
    do("apply")
    lk = j("look")
    assert lk["stored"]["vpnAppearance"] == {"theme": "graphite"} and lk["style"]["lineStyle"] == "circuit", lk["stored"]
    do("preview", "active", "#ff0000")
    assert j("look")["current"] == "custom"
    do("cancel")
    assert j("look")["style"]["active"] != "#ff0000", "cancel drops the preview"
    do("preview", "lineStyle", "flow")
    do("preview", "active", "#00ff88")
    do("apply")
    lk = j("look")
    assert lk["stored"]["vpnAppearance"]["theme"] == "custom" and lk["stored"]["vpnAppearance"]["custom"]["active"] == "#00ff88"
    do("reset")
    assert j("look")["style"]["active"] == "#9fdcff", "reset of a custom look goes back to the default theme"
    do("cancel")
    pid = do("savePreset", "  Мой   неон  ")
    lk = j("look")
    assert lk["presets"][-1]["name"] == "Мой неон" and lk["themeId"] == "user:" + pid, lk["presets"]
    stored_text = json.dumps(lk["stored"], ensure_ascii=False)
    for secret in ("PRIVATE-TOKEN", "sub.example.net", "http", "vless", "127.0.0.1"):
        assert secret not in stored_text, f"appearance must not contain {secret}"
    do("deletePreset", pid)
    assert j("look")["themeId"] == "obsidian_glass"
    passed.append("appearance: 6 themes, preview writes nothing, apply/cancel/reset/save/delete preset; "
                  "sanitize rejects junk; stored data has no link, host or token")

    # ---- settings tab loads and previews ------------------------------------------------------------
    do("showSettings", True)
    do("previewTheme", "soft_neon")
    shot("11-settings-tab", "settings", settle=1.2)
    do("showSettings", False)
    do("cancel")

    shot("12-final")
    bad = [m for m in messages if ("Error" in m or "error" in m or "ReferenceError" in m or "TypeError" in m
                                   or "binding loop" in m.lower() or "is not a type" in m or "Cannot assign" in m
                                   or "Unable to assign" in m) and "QFontEngine" not in m]
    assert not bad, "QML warnings:\n" + "\n".join(bad[:20])
    for line in passed:
        print("PASS:", line)
    print("PASS: no QML errors or binding loops")
finally:
    shutil.rmtree(tmp, ignore_errors=True)
