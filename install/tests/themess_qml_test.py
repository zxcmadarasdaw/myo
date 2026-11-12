"""Qt smoke test for the real Themess settings tab and GIF layer.

Quickshell interfaces are stubbed. The Process bridge invokes the real Python
helper against a disposable user profile.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
if os.name == "nt":
    os.environ.setdefault("QT_QPA_FONTDIR", str(Path(os.environ["WINDIR"]) / "Fonts"))
from PySide6.QtCore import QObject, QUrl, Slot, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine

ROOT = Path(__file__).resolve().parents[2]
GIF = ROOT / "themess/MrRobot/wallpapers/mr-robot.gif"
app = QGuiApplication([])
messages = []
qInstallMessageHandler(lambda kind, context, message: messages.append(message))


def write(root, name, content):
    target = root / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def singleton(root, directory, name, body):
    write(root, directory / f"{name}.qml", f"pragma Singleton\nimport QtQuick\nQtObject {{ {body} }}")
    with (root / directory / "qmldir").open("a", encoding="utf-8") as registry:
        registry.write(f"singleton {name} 1.0 {name}.qml\n")


with tempfile.TemporaryDirectory(prefix="themess-qml-") as directory:
    root = Path(directory)
    for name in ("guide/GuideTab.qml", "guide/ThemessTab.qml", "wallpaper/WallpaperGif.qml",
                 "singletons/system/Themess.qml", "guide/themess/ThemessPreview.qml"):
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "src/quickshell" / name, target)

    app_src = root / "app/src"
    shutil.copytree(ROOT / "src/scripts/themess", app_src / "scripts/themess", ignore=shutil.ignore_patterns("__pycache__"))
    package = app_src.parent / "themess/Bundled"
    package.mkdir(parents=True)
    (package / "dock.json").write_text('{"enabled": false}', encoding="utf-8")
    external = root / "import folder # 100%"
    external.mkdir()
    (external / "theme.json").write_text(
        '{"version":1,"name":"Imported","author":"Test author","description":"Test package",'
        '"components":{"widgets":"widgets.json","materials":"materials.json"}}', encoding="utf-8")
    (external / "widgets.json").write_text(
        '[{"id":"clock","type":"time","variant":"lockscreen","anchor":"top left","x":20,"y":30,"w":280,"h":100}]',
        encoding="utf-8")
    (external / "materials.json").write_text('{"elementOpacity":87}', encoding="utf-8")
    profile = root / "home"
    settings = profile / ".config/serpantinum/settings.json"
    settings.parent.mkdir(parents=True)
    original = b'{"dock":{"enabled":true},"general":{"language":"en"}}'
    settings.write_bytes(original)

    class ProcessBridge(QObject):
        @Slot("QVariantList", result=str)
        def run(self, args):
            env = dict(os.environ, HOME=str(profile), USERPROFILE=str(profile),
                       QS_SETTINGS=str(settings), QS_STATE_DIR="", QS_CACHE_DIR="",
                       QS_CACHE_WALLPAPER="", QS_STATE_THEMESS="")
            proc = subprocess.run([sys.executable, *args[1:]], capture_output=True,
                                  text=True, encoding="utf-8", env=env, timeout=20)
            return proc.stdout or json.dumps({"errors": [proc.stderr]})

    bridge = ProcessBridge()
    write(root, "reusables/qmldir", "GlassFill 1.0 GlassFill.qml\n")
    write(root, "reusables/GlassFill.qml", 'import QtQuick\nItem { property bool active: false; property real radius; property color tintColor; property real tintAmount }')
    write(root, "qmldir", "singleton Themess 1.0 singletons/system/Themess.qml\n")
    singleton(root, Path("."), "Caching", 'property string serpantinumDir: ' + json.dumps(app_src.as_posix()))
    singleton(root, Path("."), "Config", "property bool dataReady: true; property bool isWriting: false; property int reloads: 0; function reloadFromDisk() { reloads++; } function getSetting(key, fallback) { return fallback; }")
    singleton(root, Path("."), "Scaler", "function s(value) { return value; }")
    singleton(root, Path("."), "I18n", "function t(key, fallback) { return fallback; }")
    singleton(root, Path("."), "ThemeBackend",
              'property string fontFamily: "Sans"; property color text: "white"; '
              'property int borderRadius: 12; property color mantle: "#111111"; property color base: "#222222"; '
              'property color surface0: "#282828"; property color surface1: "#333333"; property color mauve: "#cba6f7"; property color red: "red"; property color yellow: "yellow"; property color subtext1: "#eeeeee"')
    singleton(root, Path("."), "Wallpaper", 'property var engines: ({"DP-1": true})')
    singleton(root, Path("."), "CanvasState", 'function cameraFor(screen) { return screen === "DP-1"; }')
    (root / "widgets").mkdir()
    (root / "bar").mkdir()
    singleton(root, Path("widgets"), "WidgetRegistry", 'property var types: ({time: {name: "Clock"}}); function typeList() { return [{id: "time"}]; } function variantList(id) { return [{id: "lockscreen"}]; } function parseAnchors(widget) { return widget.anchor ? {h:"left",v:"top"} : null; }')
    singleton(root, Path("bar"), "BarModuleRegistry", 'function moduleIds() { return ["left"]; } property var menuItemIds: ["settings"]; function variantList(id) { return []; }')
    write(root, "Quickshell/qmldir", "module Quickshell\n")
    singleton(root, Path("Quickshell"), "Quickshell", 'property var screens: [{name: "DP-1"}]')
    write(root, "Quickshell/Io/qmldir", "module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n")
    write(root, "Quickshell/Io/StdioCollector.qml", 'import QtQuick\nQtObject { property string text: "" }')
    write(root, "Quickshell/Io/Process.qml", '''import QtQuick
QtObject {
    id: process
    property var command: []
    property bool running: false
    property var stdout
    property var stderr
    signal started()
    signal exited(int code)
    onRunningChanged: {
        if (!running) return;
        started();
        Qt.callLater(function() {
            process.stdout.text = bridge.run(process.command);
            process.running = false;
            process.exited(0);
        });
    }
}''')
    write(root, "Harness.qml", '''import QtQuick
import QtQuick.Window
import "."
import "guide"
import "wallpaper"
Window {
    id: host
    width: 900
    height: 750
    visible: true
    property int currentTab: 0
    property var pendingHighlightItem: null
    property string highlightedSettingId: ""
    property int deferredBuilds: 0
    property bool detailsOpen: gallery.showDetails
    property string operation: Themess.operation
    property bool busy: Themess.busy
    property var packages: Themess.packages
    property var active: Themess.active
    property var errors: Themess.errors
    property var result: Themess.result
    property int reloads: Config.reloads
    property bool gifAdvanced: gif.item !== null && gif.item.currentFrame > 0
    function inspect() { gallery.openDetails(Themess.packages.find(item => item.name === "Imported"), true); }
    function apply() { Themess.requestApply(Themess.packages.find(item => item.name === "Imported"), "DP-1"); }
    function restore() { Themess.run("restore", "DP-1"); }
    function remove() { Themess.run("remove", "DP-1", Themess.folder); }
    function refresh() { gallery.refresh(); }
    ThemessTab { id: gallery; rootObj: host; tabIndex: 0 }
    WallpaperGif { id: gif; imageUrl: ''' + json.dumps(GIF.as_uri()) + '''; playing: true }
}''')
    engine = QQmlEngine()
    engine.addImportPath(str(root))
    engine.rootContext().setContextProperty("bridge", bridge)
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(root / "Harness.qml")))
    obj = component.create()
    assert obj is not None, "\n".join(error.toString() for error in component.errors())

    def until(predicate):
        deadline = time.monotonic() + 8
        while not predicate() and time.monotonic() < deadline:
            app.processEvents()
            time.sleep(0.01)
        assert predicate(), (obj.property("operation"), obj.property("busy"), messages)

    until(lambda: not obj.property("busy") and obj.property("operation") == "catalog")
    assert len(obj.property("packages").toVariant()) == 1
    search = obj.findChild(QObject, "themessSearch")
    cards = obj.findChild(QObject, "themessCards")
    search.setProperty("text", "missing package")
    until(lambda: cards.property("count") == 0)
    search.setProperty("text", "bundled")
    until(lambda: cards.property("count") == 1)
    button = obj.findChild(QObject, "themessImport")
    picker = obj.findChild(QObject, "themessFolderDialog")
    assert button is not None and picker is not None
    button.clicked.emit()
    until(lambda: picker.property("visible"))
    picker.setProperty("selectedFolder", QUrl.fromLocalFile(str(external)))
    picker.accept()
    until(lambda: not obj.property("busy") and len(obj.property("packages").toVariant()) == 2)
    assert obj.property("detailsOpen")
    assert settings.read_bytes() == original

    obj.inspect()
    until(lambda: not obj.property("busy") and obj.property("operation") == "preview")
    report = obj.property("result").toVariant()
    assert report["widgets"][0]["wVariant"] == "lockscreen"
    assert report["appearance"]["theme"]["elementOpacity"] == 87
    assert settings.read_bytes() == original

    (external / "materials.json").write_text('{"elementOpacity":86}', encoding="utf-8")
    obj.apply()
    until(lambda: not obj.property("busy") and obj.property("operation") == "scan")
    assert "changed" in obj.property("errors").toVariant()[0]
    assert settings.read_bytes() == original
    obj.refresh()
    until(lambda: not obj.property("busy") and obj.property("operation") == "catalog")
    obj.apply()
    until(lambda: not obj.property("busy") and obj.property("operation") == "apply")
    assert obj.property("active").toVariant()["name"] == "Imported"
    assert json.loads(settings.read_bytes())["theme"]["elementOpacity"] == 86
    obj.restore()
    until(lambda: not obj.property("busy") and obj.property("operation") == "restore")
    assert settings.read_bytes() == original
    assert obj.property("reloads") == 2

    obj.remove()
    until(lambda: not obj.property("busy") and len(obj.property("packages").toVariant()) == 1)
    assert (external / "widgets.json").is_file()
    until(lambda: obj.property("gifAdvanced"))
    assert not messages, "\n".join(messages)
    print("PASS: Themess gallery, folder picker, import, preview, real apply/restore, reference removal and GIF")
    obj.close()
    del obj, component, engine
