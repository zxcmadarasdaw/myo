"""Load the workspace settings and bar indicator in Qt with mocked Hyprland IPC."""

import os
from pathlib import Path
from tempfile import TemporaryDirectory

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QUrl, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine

SOURCE = Path(__file__).resolve().parents[2] / "src/quickshell"

with TemporaryDirectory(prefix="workspace-slots-") as directory:
    root = Path(directory)

    def write(name, data):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data, encoding="utf-8")

    def singleton(namespace, name, body):
        path = root / namespace
        write(path / f"{name}.qml", "pragma Singleton\nimport QtQuick\nQtObject { " + body + " }")
        with (path / "qmldir").open("a", encoding="utf-8") as registry:
            registry.write(f"singleton {name} 1.0 {name}.qml\n")

    workspace_slots = "singletons/system/WorkspaceSlots.qml"
    workspace_face = "bar/faces/workspaces/WorkspacesFace.qml"
    for source in (workspace_slots, workspace_face):
        write(source, (SOURCE / source).read_text(encoding="utf-8"))

    write("qmldir", f"singleton WorkspaceSlots 1.0 {workspace_slots}\n")
    singleton("", "Config", "property var rawSettings: ({}); property bool dataReady: false; signal settingsLoaded()")
    singleton("", "Compositor", 'property string name: "hyprland"')
    singleton("bar", "BarModuleRegistry", 'function variantFaceFile(name, style) { return "" }')
    for state in ("NiriState", "MangoState", "SwayState"):
        singleton("", state, """function activeIndexFor(output) { return -1 }
            function subscribe() {}
            function unsubscribe() {}
            property var occupiedMap: ({})
            property var existingMap: ({})
            property var occupiedByOutput: ({})
            property int maxWorkspaceIndex: -1
            property int tagCount: 0""")
    write("reusables/qmldir", "")
    write("Quickshell/qmldir", "module Quickshell\n")
    singleton("Quickshell", "Quickshell", "function execDetached(command) {}")
    write("Quickshell/Hyprland/qmldir", "module Quickshell.Hyprland\n")
    singleton("Quickshell/Hyprland", "Hyprland", """
        property var workspaces: ({values: []})
        property var monitors: ({values: []})
        property var focusedWorkspace: ({id: 2})
        property string dispatched
        signal rawEvent(var event)
        function dispatch(value) { dispatched = value }
        function setActive(a, b) {
            monitors = {values: [{name: "DP-1", activeWorkspace: {id: a}},
                                  {name: "DP-2", activeWorkspace: {id: b}}]}
            focusedWorkspace = {id: b}
        }""")
    write("Quickshell/Io/qmldir", "module Quickshell.Io\nProcess 1.0 Process.qml\n")
    singleton("Quickshell/Io", "CommandLog", "property var commands: []")
    write("Quickshell/Io/Process.qml", """import QtQuick
        Item {
            property var command
            property bool running
            signal exited(int code, int status)
            onRunningChanged: {
                if (!running) return
                CommandLog.commands = CommandLog.commands.concat([command])
                Qt.callLater(() => { running = false; exited(0, 0) })
            }
        }""")
    write("Harness.qml", """import QtQuick
        import Quickshell.Hyprland
        import Quickshell.Io
        import "."
        import "bar/faces/workspaces"
        Item {
            property int count: face.workspaceCount
            property int active: face.activeIndex
            property int numberOfCommands: CommandLog.commands.length
            property string lastCommand: numberOfCommands ? CommandLog.commands[numberOfCommands - 1].join(" ") : ""
            property string dispatched: Hyprland.dispatched
            WorkspacesFace {
                id: face
                module: ({orientation: "horizontal", isCompact: false, moduleActive: true,
                          barWindow: {screen: {name: "DP-1"}}})
            }
            function start() { Hyprland.setActive(1, 2); Config.dataReady = true }
            function clickWorkspace() { face.focusWorkspace(1) }
            function switchWorkspace() { Hyprland.setActive(2, 3) }
            function reload() { Hyprland.rawEvent({name: "configreloaded"}) }
            function configureRanges() {
                Config.rawSettings = {bar: {workspaceCount: 6, workspaces: {perMonitorNumbering: true,
                    monitors: {"DP-1": {first: 5, count: 1}, "DP-2": {first: 6, count: 4}}}}}
                Hyprland.setActive(5, 6)
            }
            function switchCompositor() { Compositor.name = "sway"; reload() }
        }""")

    app = QGuiApplication([])
    messages = []
    qInstallMessageHandler(lambda kind, context, message: messages.append(message))
    engine = QQmlEngine()
    engine.addImportPath(str(root))
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(root / "Harness.qml")))
    harness = component.create()
    assert harness is not None, component.errorString()

    def run(method):
        getattr(harness, method)()
        for _ in range(4):
            app.processEvents()

    assert harness.property("active") == -1
    assert harness.property("numberOfCommands") == 0
    run("start")
    assert harness.property("count") == 8 and harness.property("active") == 0
    assert harness.property("lastCommand").startswith("timeout 5s hyprctl eval _G.serpantinumWorkspaceSlots = { count = 8")
    run("clickWorkspace")
    assert harness.property("dispatched") == "hl.dsp.focus({ workspace = 2 })"
    assert harness.property("active") == 0
    run("switchWorkspace")
    assert harness.property("active") == 1
    assert harness.property("numberOfCommands") == 1
    run("configureRanges")
    assert harness.property("count") == 1 and harness.property("active") == 0
    assert 'count = 6, monitors = { ["DP-1"] = { first = 5, count = 1 }' in harness.property("lastCommand")
    assert harness.property("numberOfCommands") == 2
    run("reload")
    assert harness.property("numberOfCommands") == 3
    run("switchCompositor")
    assert harness.property("count") == 6 and harness.property("numberOfCommands") == 3
    assert not messages, messages

    harness.deleteLater()
    app.processEvents()
    qInstallMessageHandler(None)

print("Workspace bar passed: per-monitor indicator, click dispatch, configuration and reload")
