"""Qt object/binding integration with explicit Quickshell stubs.

Requires existing PySide6. Does not start Quickshell, Linux IPC or GPU rendering.
This catches QML type/binding failures and config regressions, not Wayland bugs.
"""
import os
from pathlib import Path
import shutil
import tempfile
import json

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import QUrl, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine

ROOT = Path(__file__).resolve().parents[2]
app = QGuiApplication([])
messages = []
qInstallMessageHandler(lambda kind, context, message: messages.append(message))


def write(root, name, content):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


with tempfile.TemporaryDirectory(prefix="serpantinum-qml-test-") as temp:
    root = Path(temp)
    copied = [
        "singletons/system/GpuCompatibility.qml", "singletons/system/GpuPolicy.js",
        "singletons/theme/ThemeBackend.qml", "guide/GuideTab.qml", "guide/display/DisplayGpuTab.qml",
        "reusables/display/GpuBackendObserver.qml",
        "reusables/display/FluidWave.qml", "reusables/display/LiquidFill.qml",
        "reusables/inputs/Checkbox.qml", "reusables/media/WavySeekBar.qml",
        "reusables/media/Visualizer.qml", "widgets/SelectionOutline.qml",
    ]
    # The real ThemeBackend needs the entire theme subsystem. For this focused
    # integration test we exercise the real GPU manager + tab with a theme stub.
    copied.remove("singletons/theme/ThemeBackend.qml")
    for relative in copied:
        dst = root / relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "src/quickshell" / relative, dst)
    write(root, "qmldir", "singleton Config 1.0 Config.qml\nsingleton Caching 1.0 Caching.qml\nsingleton ThemeBackend 1.0 ThemeBackend.qml\nsingleton I18n 1.0 I18n.qml\nsingleton Spectrum 1.0 Spectrum.qml\nsingleton GpuCompatibility 1.0 singletons/system/GpuCompatibility.qml\n")
    write(root, "reusables/qmldir", "GpuBackendObserver 1.0 display/GpuBackendObserver.qml\n")
    write(root, "Config.qml", '''pragma Singleton
import QtQuick
QtObject {
    property bool dataReady: true
    property var rawSettings: ({theme: {colors: ["#123456"], blurStyle: "liquid"}, widgets: {items: [1, 2]}, wallpaper: "keep.mp4", bar: {position: "top"}, animations: {duration: 900}})
    function getSetting(key, fallback) {
        let result = rawSettings;
        for (let part of key.split(".")) { if (result === undefined || result === null) return fallback; result = result[part]; }
        return result === undefined ? fallback : result;
    }
    function setSetting(key, value) {
        let next = JSON.parse(JSON.stringify(rawSettings)); let target = next;
        let keys = key.split(".");
        for (let i = 0; i < keys.length - 1; i++) { if (!target[keys[i]]) target[keys[i]] = {}; target = target[keys[i]]; }
        target[keys[keys.length - 1]] = value; rawSettings = next;
    }
}''')
    write(root, "Caching.qml", 'pragma Singleton\nimport QtQuick\nQtObject { property string serpantinumDir: ' + json.dumps((ROOT / 'src').as_uri().removeprefix('file://')) + ' }')
    write(root, "Spectrum.qml", 'pragma Singleton\nimport QtQuick\nQtObject { property int barCount: 64; property var barLevels: [] }')
    write(root, "ThemeBackend.qml", '''pragma Singleton
import QtQuick
QtObject {
    property string fontFamily: "sans-serif"
    property color text: "white"
    property color surface0: "#111111"
    property color surface1: "#222222"
    property color surface2: "#333333"
    property color crust: "#000000"
    property color primary: "#cc88ff"
    property int borderRadius: 8
    property color mauve: "#cc88ff"
    property color peach: "#ffcc88"
    property color red: "red"
}''')
    write(root, "I18n.qml", 'pragma Singleton\nimport QtQuick\nQtObject { property string currentLang: "ru"; property int layoutDirection: Qt.LeftToRight; function t(key, fallback) { return fallback; } }')
    write(root, "Quickshell/qmldir", "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n")
    write(root, "Quickshell/Quickshell.qml", 'pragma Singleton\nimport QtQuick\nQtObject { function env(key) { return ""; } function execDetached(args) {} }')
    write(root, "Quickshell/Io/qmldir", "module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n")
    write(root, "Quickshell/Io/Process.qml", 'import QtQuick\nQtObject { property var command: []; property bool running: false; property var stdout; signal exited(int code) }')
    write(root, "Quickshell/Io/StdioCollector.qml", 'import QtQuick\nQtObject { property string text: ""; signal streamFinished() }')
    write(root, "Harness.qml", '''import QtQuick
import "./"
import "guide/display"
import "reusables/display"
import "reusables/inputs"
import "reusables/media"
import "widgets"
Item {
    id: host
    width: 1000; height: 800
    property string result: "pending"
    property int currentTab: 0
    property int currentSubTab: 4
    property var pendingHighlightItem: null
    property string highlightedSettingId: ""
    property int deferredBuilds: 0
    function s(value) { return value; }
    function check(value, message) { if (!value) throw new Error(message); }
    DisplayGpuTab { rootObj: host; tabIndex: 0 }
    FluidWave { width: 120; height: 30; fillLevel: 0.5 }
    LiquidFill { width: 120; height: 30; fillLevel: 0.5 }
    Checkbox { id: checkbox; checked: true }
    WavySeekBar { width: 120; height: 30; value: 50 }
    Visualizer { width: 120; height: 30 }
    SelectionOutline { width: 120; height: 30 }
    Component.onCompleted: Qt.callLater(function() {
        try {
            const initial = JSON.stringify(Config.rawSettings);
            GpuCompatibility.setProfile("Ultra");
            check(GpuCompatibility.effective.profile === "Ultra", "profile binding");
            GpuCompatibility.observeBackend("second-monitor", "Software");
            check(!GpuCompatibility.shadersAllowed, "software fallback");
            check(GpuCompatibility.selectedProfile === "Ultra", "fallback must preserve selected profile");
            GpuCompatibility.forgetBackend("second-monitor");
            check(GpuCompatibility.effective.profile === "Ultra", "fallback recovery");
            GpuCompatibility.setSafeMode(true);
            check(!GpuCompatibility.shadersAllowed, "manual safe mode");
            checkbox.toggle();
            check(!checkbox.checked, "checkbox interaction in fallback");
            GpuCompatibility.setSafeMode(false);
            GpuCompatibility.report = {schema: 1, status: "ok", fingerprint: "amd", gpus: [{model: "AMD", nodes: [], connectors: [], renderNodes: []}], issues: []};
            GpuCompatibility.acceptHardware();
            GpuCompatibility.report = {schema: 1, status: "ok", fingerprint: "nvidia", gpus: [{model: "NVIDIA", nodes: [], connectors: [], renderNodes: []}], issues: []};
            check(GpuCompatibility.hardwareChanged, "GPU replacement detection");
            check(Config.getSetting("graphics.lastHardware", {}).fingerprint === "amd", "replacement must wait for acknowledgement");
            GpuCompatibility.acceptHardware();
            check(!GpuCompatibility.hardwareChanged, "hardware acknowledgement");
            let preserved = JSON.parse(JSON.stringify(Config.rawSettings)); delete preserved.graphics;
            check(JSON.stringify(preserved) === initial, "theme/widgets/wallpaper/layout/animations modified");
            GpuCompatibility.observeShader("test", ShaderEffect.Error, "test failure");
            Qt.callLater(function() {
                try {
                    check(!GpuCompatibility.shadersAllowed, "deferred shader failure");
                    GpuCompatibility.resetShaderErrors();
                    check(GpuCompatibility.shadersAllowed, "shader reset");
                    host.result = "passed";
                } catch(e) { host.result = String(e); }
            });
        } catch(e) { host.result = String(e); }
    })
}''')
    engine = QQmlEngine()
    engine.addImportPath(str(root))
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(root / "Harness.qml")))
    obj = component.create()
    if obj is None:
        raise AssertionError("\n".join(error.toString() for error in component.errors()))
    for _ in range(40):
        app.processEvents()
    result = obj.property("result")
    errors = [m for m in messages if any(s in m for s in ("Error", "Unable to assign", "Binding loop", "Cannot assign", "is not a type", "failed"))]
    assert result == "passed", (result, messages)
    assert not errors, "\n".join(errors)
    print("PASS: real GPU singleton + settings tab instantiate with Qt; profile/fallback recovery, GPU replacement acknowledgement, preservation of unrelated settings. Quickshell is stubbed; no Wayland/render validation.")
    del obj, component, engine
