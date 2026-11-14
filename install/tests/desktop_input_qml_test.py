"""Qt lifecycle regression tests; no compositor/Wayland input is simulated.

Runs the production Main state machine, Guide transition functions/animations,
and WidgetRedactor owner lifecycle. Window transport and unrelated UI/services
are replaced with fixtures. --baseline reads those sources from the pre-fix commit, to
demonstrate the regressions before the patch.
"""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
from PySide6.QtCore import QUrl, QMetaObject, Q_ARG, Q_RETURN_ARG, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickWindow

ROOT = Path(__file__).resolve().parents[2]
BASELINE = "--baseline" in sys.argv
BASELINE_REV = "7fef490da1b750baba2855feeef5a297d478e8ca"
app = QGuiApplication([])
messages = []
qInstallMessageHandler(lambda kind, ctx, msg: messages.append(msg))
failures = []


def source(name):
    path = "src/quickshell/" + name
    if BASELINE:
        return subprocess.check_output(["git", "show", BASELINE_REV + ":" + path], cwd=ROOT).decode("utf-8")
    return (ROOT / path).read_text(encoding="utf-8")


def block(text, marker):
    """Extract a balanced production QML/JS block, including its declaration."""
    start = text.index(marker)
    brace = text.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


def pump(seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        app.processEvents()
        time.sleep(0.005)


def call(obj, name, *args):
    return QMetaObject.invokeMethod(obj, name, Q_RETURN_ARG("QVariant"),
                                  *[Q_ARG("QVariant", arg) for arg in args])


def check(value, label):
    print(("PASS: " if value else "FAIL: ") + label)
    if not value:
        failures.append(label)


with tempfile.TemporaryDirectory(prefix="desktop-input-") as directory:
    root = Path(directory)

    def write(name, text):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def singleton(name, body):
        write(name + ".qml", "pragma Singleton\nimport QtQuick\nQtObject { " + body + " }")
        with (root / "qmldir").open("a") as f:
            f.write(f"singleton {name} 1.0 {name}.qml\n")

    singleton("Quickshell", '''property var screens: [{name:"DP-1",width:1920,height:1080}, {name:"DP-2",width:1920,height:1080}];
        function env(k) { return ""; } function execDetached(args) {}''')
    singleton("Config", 'property var rawSettings: ({}); signal settingsLoaded()')
    singleton("Caching", 'property string runDir: ""')
    singleton("Hyprland", 'property var focusedMonitor: null; property var focusedWorkspace: null')
    singleton("DashboardController", 'function hide() {}')
    singleton("Updater", 'function checkUpdate() {}')
    singleton("Themess", 'property bool writingStores: false; property bool widgetEditorOpen: false')
    singleton("WidgetSync", '''property var states: ({});
        function setRedactMode(mon, active) { let next=Object.assign({},states); next[mon]=active; states=next; }
        function clear() { states=({}); }''')
    singleton("Intersection", 'enum Mode { Combine, Xor }')
    write("Region.qml", '''import QtQuick
        QtObject { property Item item; property int intersection: Intersection.Combine;
        property real x: 0; property real y: 0; property real width: 0; property real height: 0;
        default property list<QtObject> regions; }''')
    write("FileView.qml", '''import QtQuick
        QtObject { property string path; property bool blockWrites; function setText(text) {} }''')
    write("IpcHandler.qml", 'import QtQuick\nItem { property string target }')
    write("notifications/NotificationPopups.qml", 'import QtQuick\nItem {}')
    write("WindowRegistry.js", source("WindowRegistry.js"))

    # Guide: actual transitions and visibility cleanup, with unrelated search UI stubbed.
    guide = source("guide/GuidePopup.qml")
    parts = [block(guide, "function " + name + "(") for name in
             ("startExit", "closePopup", "dismissHost", "resetAndPlayIntro")]
    if "function cancelExit(" in guide:
        parts.append(block(guide, "function cancelExit("))
    parts += [block(guide, "onVisibleChanged:"),
              block(guide, "ParallelAnimation {\n        id: shellStartupSequence"),
              block(guide, "SequentialAnimation {\n        id: closeSequence")]
    guide_fixture = '''import QtQuick
        import ".."
        Item { id: root
        property var exitCallback: null
        property real introBase: 0; property real introSidebar: 0
        property real introContent: 0; property real introTabs: 0
        property int searchLoadCursor: 0; property var pendingHighlightItem: null
        property bool searchActive: false; property string searchQuery: ""
        property int searchSelectedIndex: -1
        function closeSearch() {} function releaseTab(i) {} function settleTab() {}
        function clearSearchHaystacks() {} function rebuildSearchIndex() {}
        Item { id: contentArea; property var searchInput: null }
        function interrupt() { closeSequence.stop(); }
    '''
    for timer in ("searchIndexStartTimer", "focusTimer", "tabSettleTimer", "searchLoadTimer",
                  "highlightTimer", "searchClearTimer", "searchRebuildTimer"):
        guide_fixture += f"Timer {{ id: {timer}; interval: 10000 }}\n"
    write("guide/GuidePopup.qml", guide_fixture + "\n".join(parts) + "\n}")

    main = source("Main.qml")
    main = re.sub(r"^import Quickshell.*\n", "", main, flags=re.M)
    main = main.replace("PanelWindow {", "Item {", 1)
    main = main.replace(block(main, "anchors {"), "", 1)
    main = re.sub(r"^    WlrLayershell\..*\n|^    exclusionMode:.*\n|^    color:.*\n", "", main, flags=re.M)
    main = main.replace("focusable:", "property bool focusable:", 1)
    main = main.replace("mask: Region", "property QtObject inputMask: Region", 1)
    fixture_api = '''
        property var screen: Quickshell.screens[0]
        width: 1920; height: 1080
        function command(name) { switchWidget(name, ""); }
        function settings(action) { handleEmbeddedSettings(action, ""); }
        function snapshot() {
            let guide = widgetCache.guide;
            return JSON.stringify({visible:isVisible, closing:isClosing, target:targetActive,
                alpha:guide ? guide.introBase : -1, input:isVisible && (inputMask.item !== null || inputMask.intersection !== Intersection.Combine)});
        }
        function interruptExit() { widgetCache.guide.interrupt(); }
        function closeButton() { widgetCache.guide.closePopup(); }
    '''
    write("Main.qml", main[:main.rfind("}")] + fixture_api + "}\n")

    # Redactor: retain the entire owner + Loader lifecycle, substitute only the
    # large visual PanelWindow with its production monitor resolution/binding.
    editor = source("widgets/WidgetRedactor.qml")
    panel = block(editor, "PanelWindow {")
    monitor = block(panel, "property string monitorName:")
    screen = block(panel, "property var targetScreen:")
    safe = re.search(r"readonly property string safeMonitorName:.*", panel)[0]
    changed = "onSafeMonitorNameChanged: root.syncEditMonitor()" if "onSafeMonitorNameChanged:" in panel else ""
    replacement = '''Item { id: redactorWindow
        property QtObject redactorMode: QtObject { property string selectedId: "" }
        property var activeWidgetsModel: null
    ''' + monitor + screen + safe + "\n" + changed
    if BASELINE:
        replacement += '''
        Component.onCompleted: Qt.callLater(() => WidgetSync.setRedactMode(safeMonitorName, true))
        Component.onDestruction: WidgetSync.setRedactMode(safeMonitorName, false)
        '''
    replacement += "}"
    editor = editor.replace(panel, replacement)
    editor = re.sub(r"^import (?:Quickshell.*|\".*)\n", "", editor, flags=re.M)
    editor = editor.replace("Scope {", "Item {", 1)
    editor = editor[:editor.rfind("}")] + '''
        function states() { return JSON.stringify(WidgetSync.states); }
        function resetStates() { WidgetSync.clear(); }
    }'''
    write("Editor.qml", editor)

    engine = QQmlEngine()
    engine.addImportPath(str(root))
    components = []

    def create(name):
        comp = QQmlComponent(engine, QUrl.fromLocalFile(str(root / name)))
        components.append(comp)
        obj = comp.create()
        if obj is None:
            raise AssertionError("\n".join(e.toString() for e in comp.errors()) + "\n" + "\n".join(messages))
        return obj

    import json
    host = create("Main.qml")
    window = QQuickWindow()
    window.resize(1920, 1080)
    host.setParentItem(window.contentItem())
    window.show()
    pump(.05)
    snap = lambda: json.loads(call(host, "snapshot"))
    call(host, "settings", "open")
    pump(.55)
    check(snap()["alpha"] > .99 and snap()["input"], "settings open and accept input: " + str(snap()))
    call(host, "settings", "close")
    check(not snap()["input"], "close releases mask before animation finishes")
    pump(.07)
    call(host, "settings", "open")
    pump(.65)
    check(snap()["visible"] and snap()["alpha"] > .99, "close/reopen restores visible settings: " + str(snap()))
    call(host, "settings", "close")
    pump(.55)
    check(not snap()["visible"] and not snap()["input"], "normal close leaves no input surface")
    call(host, "settings", "open")
    pump(.5)
    call(host, "settings", "close")
    call(host, "interruptExit")
    pump(.55)
    check(not snap()["visible"] and not snap()["input"], "interrupted exit falls back to host cleanup")
    call(host, "settings", "open")
    pump(.5)
    call(host, "closeButton")
    pump(.6)
    check(not snap()["visible"], "close button works after an interrupted callback")
    for _ in range(8):
        call(host, "settings", "open")
        pump(.025)
        call(host, "settings", "close")
        pump(.025)
    pump(.65)
    check(not snap()["visible"] and not snap()["input"], "rapid settings toggles settle closed")
    # Registry points at a deliberately missing component in this fixture.
    call(host, "command", "network")
    pump(.15)
    if not BASELINE:
        check(snap()["target"] == "hidden", "component error aborts without a busy retry loop")
    call(host, "command", "hidden")

    editor = create("Editor.qml")
    call(editor, "resetStates")
    call(editor, "open", "DP-2", "")
    pump(.05)
    check(json.loads(call(editor, "states")).get("DP-2"), "editor acquires selected monitor")
    call(editor, "close")
    pump(.05)
    check(not any(json.loads(call(editor, "states")).values()), "close releases original monitor before clearing target")
    call(editor, "resetStates")
    call(editor, "open", "DP-1", "")
    pump(.05)
    call(editor, "open", "DP-2", "")
    pump(.05)
    states = json.loads(call(editor, "states"))
    check(not states.get("DP-1") and states.get("DP-2"), "monitor switch transfers editor ownership")
    call(editor, "close")
    call(editor, "resetStates")
    for _ in range(10):
        call(editor, "open", "DP-2", "")
        call(editor, "close")
    pump(.1)
    check(not any(json.loads(call(editor, "states")).values()), "immediate editor open/close cannot rearm input later")
    if not BASELINE:
        shell = source("Shell.qml")
        main_wiring = block(shell, "Main {").replace("Main {", "Main { id: shellMain;", 1)
        editor_wiring = block(shell, "WidgetRedactor {").replace("WidgetRedactor {", "Editor {", 1)
        write("ShellFixture.qml", '''import QtQuick
            Item { ''' + main_wiring + editor_wiring + '''
            function startEdit() { widgetRedactor.open("DP-2", ""); }
            function openSettings() { shellMain.handleEmbeddedSettings("open", ""); }
            function closeSettings() { shellMain.handleEmbeddedSettings("close", ""); }
            function editing() { return widgetRedactor.isActive; }
            function hidden() { return !shellMain.isVisible && !widgetRedactor.isActive; }
            }''')
        engine.clearComponentCache()
        shell_obj = create("ShellFixture.qml")
        shell_obj.setParentItem(window.contentItem())
        call(shell_obj, "startEdit")
        pump(.02)
        check(call(shell_obj, "editing"), "shell can enter desktop edit mode")
        call(shell_obj, "openSettings")
        pump(.05)
        check(not call(shell_obj, "editing"), "opening settings releases an existing editor")
        call(shell_obj, "closeSettings")
        pump(.6)
        check(call(shell_obj, "hidden"), "closing settings during transition leaves editor and settings closed")
        shell_obj.deleteLater()
        pump(.02)
        # Exercise production mask bindings with Region transport stubbed.
        for name, ident, opened in (("launcher/Launcher.qml", "launcherWindow", "isVisible"),
                                   ("clipboard/Clipboard.qml", "clipboardWindow", "isVisible"),
                                   ("calendar/Dashboard.qml", "dashboardWindow", "isOpen"),
                                   ("processexplorer/ProcessExplorer.qml", "win", "open")):
            mask = block(source(name), "mask: Region").replace("mask:", "property QtObject inputMask:", 1)
            write("Mask.qml", '''import QtQuick
                Item { id: ''' + ident + "; width: 1920; height: 1080; property bool " + opened + ''': true
                Item { id: topBarHole; width: 1920; height: 48 }
                ''' + mask + '''
                function hasInput() { return inputMask.item !== null || inputMask.intersection !== Intersection.Combine || inputMask.width > 0; }
                }''')
            engine.clearComponentCache()
            obj = create("Mask.qml")
            check(call(obj, "hasInput"), name + " accepts input while open")
            obj.setProperty(opened, False)
            check(not call(obj, "hasInput"), name + " releases input while visuals linger")
            obj.deleteLater()
            pump(.01)

        widget = source("widgets/Widget.qml")
        mask = block(widget, "mask: Region").replace("mask:", "property QtObject inputMask:", 1)
        focus = widget[widget.index("readonly property bool effectiveKeyboardFocus:"):widget.index("property real animX:")]
        write("WidgetMask.qml", '''import QtQuick
            Item { id: root; property bool isRedacting: false; property real wOpacity: 1
            property bool wantsKeyboardFocus: true; property real auraMargin: 8
            property real screenBoxWidth: 300; property real screenBoxHeight: 200
            property bool musicDrawerEnabled: false; property real musicStripHeight: musicDrawerEnabled ? 24 : 0
            Item { id: faceLoader; property var item: null }
            ''' + focus + mask + '''
            function hit(x,y) { return inputMask.regions.some(r => x >= r.x && y >= r.y && x < r.x+r.width && y < r.y+r.height); }
            }''')
        engine.clearComponentCache()
        obj = create("WidgetMask.qml")
        check(call(obj, "hit", 10, 10) and not call(obj, "hit", 2, 2), "widget face clickable; decorative aura passes clicks")
        obj.setProperty("wOpacity", 0)
        check(not call(obj, "hit", 10, 10) and not obj.property("effectiveKeyboardFocus"), "invisible widget releases pointer and keyboard")
        obj.setProperty("musicDrawerEnabled", True)
        check(call(obj, "hit", 10, 210), "music drawer strip keeps its separate hit target")
        obj.setProperty("isRedacting", True)
        check(not call(obj, "hit", 10, 210), "editor disables live widget input")
        obj.deleteLater()
        pump(.01)
    errors = [m for m in messages if "ReferenceError" in m or "TypeError" in m or "Binding loop" in m]
    check(not errors, "no QML runtime errors: " + "; ".join(errors[:4]))
    if failures:
        print("\n".join(messages[:25]))
    host.deleteLater()
    editor.deleteLater()
    pump(.05)
    window.close()
    del engine

print(f"{'BASELINE' if BASELINE else 'PATCHED'}: {len(failures)} failures; Qt only, no Wayland/Hyprland")
sys.exit(bool(failures))
