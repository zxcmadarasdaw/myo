"""VPN block of the network panel: VpnService.qml + network/VpnBlock.qml, offscreen.

    python3 install/tests/vpn_qml_test.py [--shots DIR]

Loads the real VpnService singleton and the real VpnBlock with stub Quickshell
modules (the python backend is not run: every Process is a stub whose output the
test supplies). Checks that the link reaches the backend on stdin only, the state
texts, that ping runs only while the panel is open and stops when it closes, that
choosing a server selects and connects, the country grouping and the install hint.
With --shots it saves screenshots of the block (empty, connected + server list,
sing-box missing). Needs PySide6; skipped without it.
"""
import json
import os
from pathlib import Path
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
    from PySide6.QtCore import QMetaObject, Q_ARG, Q_RETURN_ARG, QUrl, qInstallMessageHandler
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
STRINGS = json.loads((ROOT / f"src/assets/languages/{LANG}.json").read_text(encoding="utf-8"))["vpn"]
EN = json.loads((ROOT / "src/assets/languages/en.json").read_text(encoding="utf-8"))["vpn"]


def flatten(d, prefix="vpn."):
    out = {}
    for k, v in d.items():
        if isinstance(v, dict):
            out.update(flatten(v, prefix + k + "."))
        else:
            out[prefix + k] = v
    return out


assert set(flatten(STRINGS)) == set(flatten(EN)), "en/ru vpn keys differ"
used = set()
for f in (QS / "network/VpnBlock.qml", QS / "singletons/system/VpnService.qml"):
    import re
    src = f.read_text(encoding="utf-8")
    used |= {"vpn." + k for k in re.findall(r'(?:block\.)?tr\("([a-z_.]+)"', src)}
    used |= set(re.findall(r'I18n\.t\("(vpn\.[a-z_.]+)"', src))
missing = sorted(k for k in used if k not in flatten(EN))
assert not missing, f"keys used in QML but not in en.json: {missing}"
print(f"PASS: {len(used)} vpn.* keys used in QML exist in en.json and {LANG}.json")


def write(root, name, content):
    target = root / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def build(root):
    shutil.copy(QS / "network/VpnBlock.qml", root / "network_VpnBlock.tmp")
    (root / "network").mkdir()
    shutil.move(str(root / "network_VpnBlock.tmp"), root / "network/VpnBlock.qml")
    write(root, "network/qmldir", "VpnBlock 1.0 VpnBlock.qml\n")
    (root / "singletons/system").mkdir(parents=True)
    shutil.copy(QS / "singletons/system/VpnService.qml", root / "singletons/system/VpnService.qml")
    write(root, "qmldir", "singleton VpnService 1.0 singletons/system/VpnService.qml\n"
                          "singleton Caching 1.0 Caching.qml\nsingleton I18n 1.0 I18n.qml\n"
                          "singleton Scaler 1.0 Scaler.qml\nsingleton ThemeBackend 1.0 ThemeBackend.qml\n")
    write(root, "Caching.qml", 'pragma Singleton\nimport QtQuick\nQtObject { property string serpantinumDir: "/opt/serpantinum/src" }')
    write(root, "Scaler.qml", "pragma Singleton\nimport QtQuick\nQtObject { function s(v) { return v; } }")
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
    property int borderRadius: 18; property real elementOpacity: 0.92
}""" % icon_family)
    write(root, "reusables/qmldir", "WallpaperBlur 1.0 WallpaperBlur.qml\n")
    write(root, "reusables/WallpaperBlur.qml", "import QtQuick\nItem { property real topLeftRadius; property real topRightRadius; "
                                               "property real bottomLeftRadius; property real bottomRightRadius }")
    write(root, "Quickshell/qmldir", "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n")
    write(root, "Quickshell/Quickshell.qml", "pragma Singleton\nimport QtQuick\nQtObject { property var launched: []; "
                                             "function execDetached(argv) { launched = launched.concat([argv]); } }")
    write(root, "Quickshell/Io/qmldir", "module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n"
                                        "singleton ProcLog 1.0 ProcLog.qml\n")
    write(root, "Quickshell/Io/ProcLog.qml", "pragma Singleton\nimport QtQuick\nQtObject { property var all: []; function add(p) { all = all.concat([p]); } }")
    write(root, "Quickshell/Io/StdioCollector.qml", 'import QtQuick\nQtObject { property string text: ""; signal streamFinished() }')
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
import "network"
import "."

Window {
    id: win
    width: 720; height: 714
    visible: true
    color: "#0d0d14"

    Item {
        id: popup
        anchors.fill: parent
        property real introState: 1.0
        property real exitOpacity: 1.0
        function s(v) { return v; }
        function animWin(t, a, b) { if (t <= a) return 0.0; if (t >= b) return 1.0; return (t - a) / (b - a); }
        function easeOut(t) { let c = Math.max(0, Math.min(1, t)); return 1 - Math.pow(1 - c, 3); }

        // stand-in for the unchanged Internet card, at the margin NetworkPopup gives it
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: block.cardHeight + block.gap
            radius: 18
            color: Qt.alpha("#1e1e2e", 0.92)
            Text { anchors.centerIn: parent; text: "Internet card (unchanged)"; color: "#585b70"; font.pixelSize: 18 }
        }

        VpnBlock { id: block; anchors.fill: parent; z: 20; window: popup }
    }

    function setVisible(v) { popup.visible = v; return "ok"; }
    function start() { VpnService.start(); return "ok"; }
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
                if (p.stdout) { p.stdout.text = text; p.stdout.streamFinished(); }
                p.running = false;
                return "ok";
            }
        }
        return "ERROR no running process matching " + needle;
    }
    function svc() {
        return JSON.stringify({ state: VpnService.vpnState, busy: VpnService.busy, error: VpnService.error,
                                current: VpnService.current, servers: VpnService.servers.length,
                                countries: VpnService.countries.map(c => [c.code, c.servers.length, c.best]),
                                pinging: VpnService.pinging, panelOpen: VpnService.panelOpen });
    }
    function ui() {
        return JSON.stringify({ stateText: block.stateText, detail: block.detailText, listOpen: block.listOpen,
                                problem: block.problemText, warning: block.detailIsWarning,
                                forceOff: block.showForceOff, tun: block.tun, forcing: VpnService.forcing,
                                checks: VpnService.checks.length });
    }
    function setMode(m) { VpnService.setMode(m); return "ok"; }
    function disconnect() { VpnService.disconnect(); return "ok"; }
    function forceOff() { VpnService.forceOff(); return "ok"; }
    function setSource(t) { VpnService.setSource(t); return "ok"; }
    function select(t) { VpnService.select(t); return "ok"; }
    function openList() { block.openList(); return "ok"; }
    function closeList() { block.listOpen = false; return "ok"; }
    function launched() { return JSON.stringify(Quickshell.launched); }
    function copyHint() { VpnService.copyText(VpnService.installHint); return "ok"; }
    property bool shotDone: false
    function shotTo(path) {
        shotDone = false;
        win.contentItem.grabToImage(function(r) { r.saveToFile(path); win.shotDone = true; });
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
    engine.rootContext().setContextProperty("strings", flatten(STRINGS))
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(tmp / "Harness.qml")))
    win = component.create()
    assert win is not None, "\n".join(e.toString() for e in component.errors())

    def call(name, *args):
        return QMetaObject.invokeMethod(win, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", a) for a in args])

    def j(name, *args):
        v = call(name, *args)
        assert isinstance(v, str) and not v.startswith("ERROR"), (name, v)
        return v if v == "ok" else json.loads(v)

    def finish(needle, text, code=0):
        return j("finish", needle, text, code)

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

    def shot(name):
        if shots is None:
            return
        pump(0.6)                                   # let open/colour animations settle
        path = shots / f"vpn-{name}.png"
        j("shotTo", str(path))
        until(lambda: call("isShotDone") == "true", "screenshot saved")
        print(f"      screenshot: {path}")

    STATUS_NONE = {"ok": True, "state": "none", "running": False, "hasSource": False, "hasConfig": False,
                   "singbox": True, "proxy": "127.0.0.1:2080", "current": "", "currentServer": None, "count": 0,
                   "delays": {}, "installHint": "sudo dnf install sing-box"}
    SERVERS = [
        {"tag": "🇩🇪 Frankfurt 1", "name": "🇩🇪 Frankfurt 1", "protocol": "vless", "address": "de1.example.com", "port": 443,
         "country": "DE", "countryName": "Германия", "flag": "🇩🇪"},
        {"tag": "🇩🇪 Berlin 2", "name": "🇩🇪 Berlin 2", "protocol": "trojan", "address": "de2.example.com", "port": 443,
         "country": "DE", "countryName": "Германия", "flag": "🇩🇪"},
        {"tag": "🇳🇱 Amsterdam", "name": "🇳🇱 Amsterdam", "protocol": "vless", "address": "nl.example.com", "port": 443,
         "country": "NL", "countryName": "Нидерланды", "flag": "🇳🇱"},
        {"tag": "🇫🇮 Helsinki HY2", "name": "🇫🇮 Helsinki HY2", "protocol": "hysteria2", "address": "fi.example.com", "port": 8443,
         "country": "FI", "countryName": "Финляндия", "flag": "🇫🇮"},
        {"tag": "Fast node", "name": "Fast node", "protocol": "shadowsocks", "address": "203.0.113.9", "port": 8388,
         "country": "", "countryName": "", "flag": ""},
    ]
    passed = []

    # ---- start: status + silent auto update -------------------------------------------
    j("start")
    until(lambda: running("status --json"), "status requested at start")
    until(lambda: running("update --auto --json"), "auto update at start")
    backend = [p for p in j("procs") if p["cmd"][:1] == ["python3"]]
    assert backend and all(p["env"].get("SERP_VPN_LANG") == LANG for p in backend), "UI language is passed to the backend"
    finish("status --json", json.dumps(STATUS_NONE))
    finish("update --auto", json.dumps({"ok": True, "skipped": "no_source"}))
    until(lambda: j("svc")["state"] == "none", "state none")
    until(lambda: not j("svc")["busy"], "auto update finished")
    assert j("ui")["stateText"] == STRINGS["state"]["none"], j("ui")
    passed.append("start: status + auto update; empty state text")
    shot("1-empty")

    # ---- the link goes on stdin, never into argv ----------------------------------------
    link = "https://sub.example.net/abc/PRIVATE-TOKEN-123"
    j("setSource", link)
    until(lambda: running("set-source"), "set-source started")
    pump(0.1)
    p = running("set-source")[0]
    assert link not in " ".join(p["cmd"]), p["cmd"]
    assert p["written"] == [link + "\n"], p["written"]
    assert p["stdinClosed"], "stdin is closed after the link (EOF for the script)"
    assert link not in "\n".join(messages), "the link must not be logged"
    finish("set-source", json.dumps({"ok": True, "servers": len(SERVERS)}))
    until(lambda: running("status --json"), "status after save")
    status_off = dict(STATUS_NONE, state="disconnected", hasSource=True, hasConfig=True, count=len(SERVERS),
                      current=SERVERS[0]["tag"], currentServer=SERVERS[0])
    finish("status --json", json.dumps(status_off))
    until(lambda: running("list --json"), "server list requested")
    finish("list --json", json.dumps({"ok": True, "servers": SERVERS}))
    until(lambda: j("svc")["servers"] == len(SERVERS), "servers loaded")
    countries = j("svc")["countries"]
    assert [c[0] for c in countries] == ["DE", "NL", "FI", ""] or [c[0] for c in countries][-1] == "", countries
    assert dict((c[0], c[1]) for c in countries)["DE"] == 2
    passed.append("link sent on stdin (EOF after it), not in argv or log; servers grouped by country")

    # ---- ping only while the panel is open ----------------------------------------------
    pings_open = running("ping --json")
    assert pings_open, "ping starts while the panel is open"
    j("setVisible", False)
    until(lambda: not running("ping --json"), "ping stopped when the panel closed")
    assert j("svc")["panelOpen"] is False
    starts_before = sum(1 for p in j("procs") for h in p["history"] if "ping" in h)
    pump(0.3)
    assert sum(1 for p in j("procs") for h in p["history"] if "ping" in h) == starts_before, "no ping while closed"
    j("setVisible", True)
    until(lambda: running("ping --json"), "ping again when reopened")
    delays = {SERVERS[0]["tag"]: 48, SERVERS[1]["tag"]: 0, SERVERS[2]["tag"]: 95, SERVERS[3]["tag"]: 230, SERVERS[4]["tag"]: 610}
    finish("ping --json", json.dumps({"ok": True, "delays": delays}))
    until(lambda: dict((c[0], c[2]) for c in j("svc")["countries"])["DE"] == 48, "best ping per country")
    passed.append("ping runs only while the panel is open and stops when it closes")

    # ---- choosing a server selects, then connects ---------------------------------------
    j("select", SERVERS[2]["tag"])
    until(lambda: running("select"), "select started")
    p = running("select")[0]
    assert p["cmd"][2:] == ["select", SERVERS[2]["tag"], "--json"], p["cmd"]
    finish("select", json.dumps(dict(status_off, current=SERVERS[2]["tag"])))
    until(lambda: running("connect --json"), "connect after choosing a server while disconnected")
    finish("connect --json", json.dumps({"ok": True}))
    until(lambda: running("status --json"), "status after connect")
    status_on = dict(status_off, state="connected", running=True, current=SERVERS[2]["tag"], currentServer=SERVERS[2], delays=delays)
    finish("status --json", json.dumps(status_on))
    until(lambda: j("svc")["state"] == "connected", "connected")
    assert j("ui")["stateText"] == STRINGS["state"]["connected"]
    assert "127.0.0.1:2080" in j("ui")["detail"]
    passed.append("choosing a server selects it and connects; connected state shows the proxy")
    j("openList")
    pump(0.1)
    shot("2-connected-list")
    j("closeList")

    # ---- errors are shown, not thrown ---------------------------------------------------
    j("setSource", "happ://crypt3/xyz")
    until(lambda: running("set-source"), "second set-source")
    err = {"ok": False, "error": {"code": "happ_encrypted", "message": "Ссылки happ:// зашифрованы приложением Happ."}}
    finish("set-source", json.dumps(err), 1)
    until(lambda: j("svc")["error"].startswith("Ссылки happ://"), "error message shown")
    assert j("ui")["detail"].startswith("Ссылки happ://")
    passed.append("backend error message shown in the block")

    # ---- sing-box missing: state + copyable install command ------------------------------
    until(lambda: running("status --json"), "status after error")
    status_missing = dict(STATUS_NONE, state="missing", hasSource=True, count=len(SERVERS), current=SERVERS[0]["tag"],
                          currentServer=SERVERS[0], singbox=False,
                          installHint="sudo dnf config-manager addrepo --from-repofile=https://sing-box.app/sing-box.repo && sudo dnf install sing-box",
                          error="sing-box не установлен. Установите: sudo dnf install sing-box")
    finish("status --json", json.dumps(status_missing))
    until(lambda: j("svc")["state"] == "missing", "missing state")
    j("copyHint")
    assert j("launched")[-1][:2] == ["wl-copy", "--"] and "dnf install sing-box" in j("launched")[-1][2]
    assert j("ui")["stateText"] == STRINGS["state"]["missing"]
    passed.append("sing-box missing: state text and the install command can be copied")
    j("openList")
    pump(0.1)
    shot("3-singbox-missing")
    j("closeList")

    # ---- stage 2: TUN mode, conflict warnings, hung service and force off -----------------
    if running("status --json"):
        finish("status --json", json.dumps(status_missing))
    j("setMode", "tun")
    until(lambda: running("mode tun --json"), "mode switch started")
    finish("mode tun --json", json.dumps({"ok": True}))
    until(lambda: running("status --json"), "status after mode switch")
    checks = [{"code": "conflict_tailscale", "level": "warn",
               "message": "Запущен Tailscale. При включённом TUN Tailscale и MagicDNS могут перестать работать; выключите что-то одно."},
              {"code": "dns_dot", "level": "info",
               "message": "systemd-resolved использует DNS-over-TLS: такие запросы идут через туннель, но к вашему обычному DNS-серверу."}]
    status_tun = dict(status_on, mode="tun", tunInstalled=True, tunState="active", tunActive=True, checks=checks)
    finish("status --json", json.dumps(status_tun))
    until(lambda: j("ui")["tun"] and j("svc")["state"] == "connected", "TUN connected")
    u = j("ui")
    assert u["stateText"] == STRINGS["state"]["connected"] and u["checks"] == 2, u
    assert u["warning"] and u["detail"].startswith("Запущен Tailscale"), u
    assert not u["forceOff"], "no emergency button while the service is fine"
    passed.append("TUN mode: mode switch runs `mode tun`, conflict warning shown in the card")
    j("openList")
    pump(0.1)
    shot("4-tun-warnings")
    j("closeList")

    j("disconnect")
    until(lambda: running("disconnect --json"), "disconnect started")
    assert j("ui")["forceOff"], "force off offered while a TUN disconnect is in progress"
    j("forceOff")
    until(lambda: running("force-off --json"), "force-off started")
    assert not running("disconnect --json"), "the hanging action is stopped first"
    assert j("ui")["forcing"] and j("ui")["detail"] == STRINGS["busy"]["force"], j("ui")
    finish("force-off --json", json.dumps(dict(status_tun, ok=True, state="disconnected", running=False,
                                                tunState="inactive", tunActive=False, forced={"kill": "ok"})))
    until(lambda: running("status --json"), "status after force off")
    finish("status --json", json.dumps(dict(status_tun, state="disconnected", running=False, tunState="inactive",
                                            tunActive=False, checks=[])))
    until(lambda: j("svc")["state"] == "disconnected", "off after force off")
    u, s = j("ui"), j("svc")
    assert not u["forcing"] and not u["forceOff"] and s["error"] == "" and not s["busy"], (u, s)
    passed.append("hung TUN disconnect: force off stops the action, runs force-off, no false error")

    bad = [m for m in messages if ("Error" in m or "error" in m or "ReferenceError" in m or "TypeError" in m
                                   or "binding loop" in m.lower()) and "QFontEngine" not in m]
    assert not bad, "QML warnings:\n" + "\n".join(bad[:20])
    for line in passed:
        print("PASS:", line)
    print("PASS: no QML errors or binding loops")
finally:
    shutil.rmtree(tmp, ignore_errors=True)
