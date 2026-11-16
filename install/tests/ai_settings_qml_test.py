"""Exercise the AI UI and confirmed actions with shell and transport fixtures."""

import json
import os
import shutil
from pathlib import Path
from tempfile import TemporaryDirectory

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtCore import Q_ARG, Q_RETURN_ARG, QObject, QMetaObject, QUrl, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickWindow

ROOT = Path(__file__).resolve().parents[2]


def run_test(root):
    guide = root / "guide"
    guide.mkdir()
    for name in ["AiTab.qml", "GuideTab.qml"]:
        shutil.copyfile(ROOT / "src/quickshell/guide" / name, guide / name)
    service = root / "singletons/system"
    service.mkdir(parents=True)
    for name in ("AiService.qml", "AiChat.qml", "AiActions.qml"):
        shutil.copyfile(ROOT / "src/quickshell/singletons/system" / name, service / name)
    shutil.copytree(ROOT / "src/quickshell/ai", root / "ai")

    (root / "qmldir").write_text(
        "singleton Config 1.0 Config.qml\nsingleton I18n 1.0 I18n.qml\n"
        "singleton ThemeBackend 1.0 ThemeBackend.qml\nsingleton Caching 1.0 Caching.qml\n"
        "singleton AiService 1.0 singletons/system/AiService.qml\n"
        "singleton AiChat 1.0 singletons/system/AiChat.qml\n"
        "singleton AiActions 1.0 singletons/system/AiActions.qml\n"
        "singleton Compositor 1.0 Compositor.qml\n"
        "singleton Scaler 1.0 Scaler.qml\n", encoding="utf-8"
    )
    (root / "Compositor.qml").write_text(
        'pragma Singleton\nimport QtQuick\nQtObject { property string name: "hyprland" }\n', encoding="utf-8"
    )
    (root / "Scaler.qml").write_text(
        "pragma Singleton\nimport QtQuick\nQtObject { function s(value) { return value; } }\n", encoding="utf-8"
    )
    (root / "Caching.qml").write_text(
        'pragma Singleton\nimport QtQuick\nQtObject { property string serpantinumDir: "/unused" }\n', encoding="utf-8"
    )
    io = root / "Quickshell/Io"
    io.mkdir(parents=True)
    (io / "qmldir").write_text(
        "module Quickshell.Io\nProcess 1.0 Process.qml\nSplitParser 1.0 SplitParser.qml\n", encoding="utf-8"
    )
    (io / "SplitParser.qml").write_text("import QtQuick\nQtObject { signal read(string line) }\n", encoding="utf-8")
    (root / "Quickshell/qmldir").write_text(
        "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\nsingleton DesktopEntries 1.0 DesktopEntries.qml\n",
        encoding="utf-8"
    )
    (root / "Quickshell/DesktopEntries.qml").write_text("""pragma Singleton
import QtQuick
QtObject {
    id: entries
    property int launches: 0
    property var applications: ({values: [{id: "firefox", name: "Firefox", execString: "firefox", noDisplay: false,
        execute: function() { entries.launches++; }}]})
    function byId(id) { return applications.values.find(app => app.id === id) || null; }
}
""", encoding="utf-8")
    hypr = root / "Quickshell/Hyprland"
    hypr.mkdir()
    (hypr / "qmldir").write_text("module Quickshell.Hyprland\nsingleton Hyprland 1.0 Hyprland.qml\n", encoding="utf-8")
    (hypr / "Hyprland.qml").write_text("""pragma Singleton
import QtQuick
QtObject {
    property var workspaces: ({values: [
        {id: 1, monitor: {name: "DP-1"}}, {id: 2, monitor: {name: "DP-1"}}, {id: 3, monitor: {name: "DP-2"}}
    ]})
    property var focusedWorkspace: workspaces.values[0]
    function dispatch(command) {
        const match = /^hl[.]dsp[.]focus[(][{] workspace = ([0-9]+) [}][)]$/.exec(command);
        if (!match) throw new Error("invalid dispatch");
        focusedWorkspace = workspaces.values.find(workspace => workspace.id === Number(match[1]));
    }
}
""", encoding="utf-8")
    (root / "Quickshell/Quickshell.qml").write_text(
        "pragma Singleton\nimport QtQuick\nQtObject { function execDetached(command) {} }\n", encoding="utf-8"
    )
    (io / "Process.qml").write_text("""import QtQuick
import "../../"
QtObject {
    property var command
    property var environment
    property bool clearEnvironment
    property bool stdinEnabled
    property bool running: false
    property var stdout
    signal started()
    signal exited(int code)
    onRunningChanged: if (running) Qt.callLater(started)
    function write(line) {
        const task = JSON.parse(line);
        Config.requests = Config.requests.concat([task]);
        if (task.op === "probe" || task.op === "models") Qt.callLater(function() {
            const models = task.profile.baseUrl.endsWith(":12434")
                ? [{ id: "test:one", name: "Test One", family: "test-family" }, { id: "test:two", name: "Test Two" }]
                : [];
            stdout.read(JSON.stringify({id: task.id, event: "completed", models: models}));
        });
        if (task.op.startsWith("history_")) Qt.callLater(function() {
            stdout.read(JSON.stringify({id: task.id, event: "completed"}));
        });
        if (task.op.startsWith("action_")) Qt.callLater(function() {
            stdout.read(JSON.stringify({id: task.id, event: "completed", colors: {base: "#222222"},
                entries: [], entry: {recordId: task.id, id: task.action?.id, target: task.action?.target}}));
        });
    }
}
""", encoding="utf-8")
    (root / "Config.qml").write_text("""pragma Singleton
import QtQuick
QtObject {
    property bool dataReady: true
    property bool isWriting: false
    property var saved: ({})
    property var requests: []
    signal settingsWriteFinished(bool success)
    function reloadFromDisk() {}
    function areEqual(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
    function getSetting(key, fallback) { return key in saved ? JSON.parse(JSON.stringify(saved[key])) : fallback; }
    function setSetting(key, value) {
        saved = Object.assign({}, saved, { [key]: value });
        if (key === "theme") Qt.callLater(function() { settingsWriteFinished(true); });
    }
}
""", encoding="utf-8")

    dictionaries = {}
    for language in ("en", "ru"):
        locale = json.loads((ROOT / "src/assets/languages" / f"{language}.json").read_text(encoding="utf-8"))
        assert locale["guide"]["tabs"]["ai"] == "AI"
        dictionaries[language] = locale["guide"]["ai"]
    assert dictionaries["en"].keys() == dictionaries["ru"].keys()
    (root / "I18n.qml").write_text("""pragma Singleton
import QtQuick
QtObject {
    property string currentLang: "en"
    readonly property var translations: (""" + json.dumps(dictionaries) + """)
    function t(key, args) {
        let message = translations[currentLang][key.slice(9)] || key;
        if (args && typeof args === "object")
            for (const name in args) message = message.replace("{" + name + "}", args[name]);
        return message;
    }
}
""", encoding="utf-8")
    (root / "ThemeBackend.qml").write_text("""pragma Singleton
import QtQuick
QtObject {
    property string fontFamily: "sans-serif"
    property color text: "#eeeeee"
    property color subtext1: "#bbbbbb"
    property color surface0: "#242424"
    property color surface1: "#333333"
    property color base: "#111111"
    property color primary: "#809cff"
    property color red: "#ee4444"
    property color green: "#55dd88"
    property color peach: "#ffbb88"
}
""", encoding="utf-8")
    (root / "Harness.qml").write_text("""import QtQuick
import Quickshell
import Quickshell.Hyprland
import "."
import "guide"
import "ai"
import "ai/ChatMarkdown.js" as Markdown
Item {
    id: host
    width: 900
    height: 720
    property int currentTab: 1
    property int currentSubTab: 0
    property int deferredBuilds: 0
    property var pendingHighlightItem: null
    property string highlightedSettingId: ""
    readonly property string settings: JSON.stringify(Config.saved)
    readonly property string markdown: Markdown.render(
        "# Header\\n**bold**\\n~~~python\\nreturn 42\\n~~~\\n<img src='https://example.invalid/x'>",
        {base: "#000000", green: "#00ff00", muted: "#cccccc", peach: "#ffaa99", primary: "#809cff"})
    property bool closeSeen: false
    property string navTarget: ""
    readonly property string actionStatus: AiActions.feedback
    readonly property int focusedSpace: Hyprland.focusedWorkspace.id
    readonly property int launchCount: DesktopEntries.launches
    readonly property int chatMatches: popup.matches.length
    readonly property int sentRequests: Config.requests.length
    readonly property bool workerStarted: AiService.workerReady
    function s(value) { return value; }
    function useRussian() { I18n.currentLang = "ru"; }
    function emitChat(event, text) {
        const id = AiChat.generation.id;
        AiService.receive(JSON.stringify({id: id, event: event, text: text}));
    }
    function verifyChat() {
        Config.setSetting("ai.privacy.localHistory", false);
        AiService.models = [{id: "test:model", name: "Test"}];
        AiService.selectModel("test:model");
        const before = Config.requests.length;
        if (!AiChat.send("First prompt")) return "send";
        const firstId = AiChat.activeId;
        AiService.receive(JSON.stringify({id: AiChat.generation.id, event: "system_facts",
            memory: {status: "available", usedGiB: 2, totalGiB: 8, percent: 25}}));
        if (!AiChat.generating || AiChat.active.messages[1].memory.percent !== 25) return "facts are not terminal";
        if (popup.memoryText(AiChat.active.messages[1].memory) !== "RAM at request time: 2 of 8 GiB used (25%)")
            return "trusted facts are formatted for display";
        if (popup.memoryText({status: "unavailable"}) !== "RAM measurement unavailable on this system.")
            return "missing memory is not a zero";
        emitChat("delta", "chunk ");
        AiChat.newConversation();
        if (AiChat.active.messages.length) return "isolated threads";
        emitChat("delta", "two");
        emitChat("completed", "");
        AiChat.activeId = firstId;
        if (AiChat.active.messages[1].content !== "chunk two") return "stream routed to original thread";
        if (!AiChat.canRegenerate) return "retry enabled";
        AiChat.regenerate();
        if (AiChat.active.messages.length !== 2) return "retry message count";
        emitChat("delta", "partial");
        const stoppedId = AiChat.generation.id;
        AiChat.stop();
        if (AiChat.active.messages[1].status !== "stopped" || AiChat.active.messages[1].content !== "partial")
            return "cancel retains unfinished response";
        AiService.receive(JSON.stringify({id: stoppedId, event: "delta", text: "late"}));
        if (AiChat.active.messages[1].content !== "partial") return "ignore stopped deltas";
        if (Config.requests.slice(before).some(task => task.op.startsWith("history_"))) return "no storage while off";
        return "ok";
    }
    function clearDuringResponse() {
        if (!AiChat.send("Clear me")) return false;
        const id = AiChat.generation.id;
        AiChat.clearHistory();
        AiService.receive(JSON.stringify({id: id, event: "completed", text: "late"}));
        return !AiChat.conversations.length && !AiChat.generating;
    }
    function verifyStreamBatch() {
        if (!AiChat.send("Stream batching")) return false;
        const initial = AiChat.active;
        for (let index = 0; index < 256; index++) emitChat("delta", "x");
        if (AiChat.active !== initial || AiChat.active.messages.slice(-1)[0].content !== "") return false;
        emitChat("completed", "");
        return AiChat.active.messages.slice(-1)[0].content === "x".repeat(256);
    }
    function copyAnswer() { popup.copy("## raw markdown"); }
    function offerAction(id, target) {
        if (!AiChat.activeId) AiChat.newConversation();
        AiActions.prepare(target === null ? {id: id} : {id: id, target: target}, AiChat.activeId);
        return !!AiActions.proposal;
    }
    function tabKitCheck() {
        if (!AiChat.send("Open the settings")) return false;
        AiService.receive(JSON.stringify({id: AiChat.generation.id, event: "completed",
            actionProposal: {id: "open_settings"}}));
        return AiActions.proposal?.action.id === "open_settings" && !navTarget;
    }
    function confirmAction() {
        const token = AiActions.proposal?.token || 0;
        return AiActions.confirm(token) && !AiActions.confirm(token);
    }
    function offerUndo() {
        if (!AiActions.records.length) return false;
        AiActions.requestUndo(AiActions.records[0].recordId, AiChat.activeId);
        return !!AiActions.proposal;
    }
    function changeWorkspace() { Hyprland.focusedWorkspace = Hyprland.workspaces.values[1]; }
    function changePalette() { Config.setSetting("theme", {activePreset: "Changed", fontFamily: "Preserve"}); }
    function changePaletteDuringApproval() { Config.setSetting("theme", {activePreset: "Newer", fontFamily: "Preserve"}); }
    function changeFont() {
        Config.setSetting("theme", Object.assign({}, Config.getSetting("theme", {}), {fontFamily: "New font"}));
    }
    function disableActions() { Config.setSetting("ai.privacy.actionsEnabled", false); }
    AiTab { rootObj: host; tabIndex: 1 }
    ChatPopup {
        id: popup
        objectName: "aiChatPopup"
        width: 780
        height: 620
        onCloseRequested: host.closeSeen = true
        onNavigateRequested: (target, tab) => host.navTarget = target + ":" + tab
    }
}
""", encoding="utf-8")

    engine = QQmlEngine()
    engine.addImportPath(str(root))
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(root / "Harness.qml")))
    host = component.create()
    assert host is not None, "\n".join(error.toString() for error in component.errors())
    window = QQuickWindow()
    window.resize(900, 720)
    host.setParentItem(window.contentItem())
    window.show()
    QGuiApplication.processEvents()

    def control(name):
        item = host.findChild(QObject, name)
        assert item is not None, name
        return item

    def prefs():
        return json.loads(host.property("settings"))

    assert prefs() == {}, "opening the tab must not write settings"
    assert not host.property("workerStarted") and host.property("sentRequests") == 0
    url = control("aiBaseUrl")
    assert url.property("text") == "http://127.0.0.1:11434"
    for invalid in ("https://example.org", "http://localhost:70000", "http://abc:secret@localhost", "http://localhost/?token=secret"):
        url.setProperty("text", invalid)
        assert not control("aiSaveUrl").property("enabled")
        assert QMetaObject.invokeMethod(url, "accepted")
        assert prefs() == {}

    url.setProperty("text", "http://[::1]:12434/")
    assert QMetaObject.invokeMethod(url, "accepted")
    assert prefs()["ai.connection.baseUrl"] == "http://[::1]:12434"

    for name, prop, value, signal in (
        ("aiTemperature", "value", 1.2, "moved"),
        ("aiMaxTokens", "value", 4096, "valueModified"),
        ("aiStreaming", "checked", False, "clicked"),
        ("aiLocalHistory", "checked", True, "clicked"),
    ):
        item = control(name)
        item.setProperty(prop, value)
        assert QMetaObject.invokeMethod(item, signal)
    assert prefs() == {
        "ai.connection.baseUrl": "http://[::1]:12434",
        "ai.generation.temperature": 1.2,
        "ai.generation.maxTokens": 4096,
        "ai.generation.streaming": False,
        "ai.privacy.localHistory": True,
    }

    assert QMetaObject.invokeMethod(control("aiProbe"), "clicked")
    QGuiApplication.processEvents()
    QGuiApplication.processEvents()
    assert control("aiConnectionStatus").property("text") == dictionaries["en"]["status_connected"]
    picker = control("aiModelPicker")
    assert picker.property("count") == 2 and picker.property("currentIndex") == -1
    control("aiModelSearch").setProperty("text", "one")
    assert picker.property("count") == 1
    assert QMetaObject.invokeMethod(picker, "activated", Q_ARG(int, 0))
    assert prefs()["ai.connection.model"] == {"baseUrl": "http://[::1]:12434", "id": "test:one"}
    assert control("aiModelDetails").property("text") == "test-family"
    url.setProperty("text", "http://localhost:11434")
    assert QMetaObject.invokeMethod(url, "accepted")
    assert picker.property("count") == 0
    assert QMetaObject.invokeMethod(control("aiProbe"), "clicked")
    QGuiApplication.processEvents()
    assert control("aiConnectionStatus").property("text") == dictionaries["en"]["status_empty"]

    popup = control("aiChatPopup")
    popup.setProperty("visible", True)
    QGuiApplication.processEvents()
    result = QMetaObject.invokeMethod(host, "verifyChat", Q_RETURN_ARG("QVariant"))
    assert result == "ok", result
    transcript = control("aiTranscript")
    assert transcript.property("count") == 2
    composer = control("aiComposer")
    pane = control("aiConversationPane")
    assert pane.property("visible") and composer.property("visible")
    search = control("aiChatSearch")
    search.setProperty("text", "partial")
    assert host.property("chatMatches") == 1
    search.setProperty("text", "unmatched")
    assert host.property("chatMatches") == 0
    search.setProperty("text", "")
    markup = host.property("markdown")
    assert "<h1>Header</h1>" in markup and "<b>bold</b>" in markup
    assert "<pre" in markup and ">return</span>" in markup
    assert "&lt;img" in markup and "<img" not in markup
    assert QMetaObject.invokeMethod(host, "copyAnswer")
    assert QGuiApplication.clipboard().text() == "## raw markdown"
    popup.setProperty("visible", False)
    assert transcript.property("count") == 0 and host.property("chatMatches") == 0
    popup.setProperty("visible", True)
    assert transcript.property("count") == 2
    assert QMetaObject.invokeMethod(host, "clearDuringResponse", Q_RETURN_ARG("QVariant"))
    assert transcript.property("count") == 0
    popup.setProperty("visible", False)
    assert QMetaObject.invokeMethod(host, "verifyStreamBatch", Q_RETURN_ARG("QVariant"))
    assert transcript.property("count") == 0
    popup.setProperty("visible", True)
    assert transcript.property("count") == 2
    QGuiApplication.processEvents()
    popup.setProperty("width", 470)
    assert popup.property("compact")
    assert not pane.property("visible") and composer.property("visible")
    popup.setProperty("showConversations", True)
    assert pane.property("visible") and not composer.property("visible")
    popup.setProperty("showConversations", False)
    assert QMetaObject.invokeMethod(popup, "closeRequested") and host.property("closeSeen")

    def call(name, *args):
        return QMetaObject.invokeMethod(host, name, Q_RETURN_ARG("QVariant"), *[Q_ARG("QVariant", arg) for arg in args])

    def drain():
        for _ in range(5):
            QGuiApplication.processEvents()

    assert call("tabKitCheck") and not host.property("navTarget")
    assert call("confirmAction")
    assert not host.property("navTarget")
    drain()
    assert host.property("navTarget") == "guide:general"
    assert not call("offerAction", "execute_shell", "test")
    assert not call("offerAction", "switch_workspace", 3)
    assert call("offerAction", "switch_workspace", 2)
    assert QMetaObject.invokeMethod(host, "changeWorkspace")
    assert not call("confirmAction") and host.property("actionStatus") == "stale"
    assert call("offerAction", "switch_workspace", 1) and call("confirmAction")
    drain()
    assert host.property("focusedSpace") == 1 and host.property("actionStatus") == "applied"
    assert call("offerUndo") and call("confirmAction")
    drain()
    assert host.property("focusedSpace") == 2 and host.property("actionStatus") == "undone"
    assert call("offerAction", "launch_app", "Firefox") and host.property("launchCount") == 0
    assert call("confirmAction")
    drain()
    assert host.property("launchCount") == 1
    assert call("offerAction", "set_theme", "Tokyo")
    assert QMetaObject.invokeMethod(host, "changePalette")
    assert not call("confirmAction") and host.property("actionStatus") == "stale"
    assert call("offerAction", "set_theme", "Nord") and call("confirmAction")
    assert QMetaObject.invokeMethod(host, "changePaletteDuringApproval")
    drain()
    assert prefs()["theme"]["activePreset"] == "Newer" and host.property("actionStatus") == "stale"
    assert call("offerAction", "set_theme", "Tokyo") and call("confirmAction")
    drain()
    assert prefs()["theme"]["activePreset"] == "Tokyo" and prefs()["theme"]["fontFamily"] == "Preserve"
    assert call("offerUndo")
    assert QMetaObject.invokeMethod(host, "changeFont")
    assert call("confirmAction")
    drain()
    assert prefs()["theme"] == {"activePreset": "Newer", "fontFamily": "New font"}
    assert call("offerAction", "open_wallpaper_hub", None)
    assert QMetaObject.invokeMethod(host, "disableActions")
    assert not call("confirmAction") and not call("offerAction", "open_settings", None)

    assert QMetaObject.invokeMethod(host, "useRussian")
    assert control("aiProvider").property("currentText") == dictionaries["ru"]["ollama"]
    host.deleteLater()
    QGuiApplication.processEvents()
    window.close()


if __name__ == "__main__":
    app = QGuiApplication([])
    messages = []
    def record_message(kind, context, message):
        if not message.startswith("QFontDatabase: Cannot find font directory"):
            messages.append(message)

    qInstallMessageHandler(record_message)
    try:
        with TemporaryDirectory(prefix="serpantinum-ai-settings-") as temp:
            run_test(Path(temp))
    except Exception:
        if messages:
            print("\n".join(messages))
        raise
    assert not messages, "\n".join(messages)
    print("PASS: AI settings, chat, permissions, confirmed actions, stale checks and undo")
