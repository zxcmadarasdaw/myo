pragma Singleton
import QtQuick
import Quickshell.Io
import "../../"

Item {
    id: root
    visible: false

    readonly property string defaultUrl: "http://127.0.0.1:11434"
    readonly property string baseUrl: normalizeUrl(Config.getSetting("ai.connection.baseUrl", defaultUrl))
    readonly property var selection: Config.getSetting("ai.connection.model", {})
    readonly property string selectedModelId: selection && selection.baseUrl === baseUrl ? (selection.id || "") : ""
    readonly property var selectedModel: models.find(model => model.id === selectedModelId) || null
    property var models: []
    property string catalogStatus: "idle"
    property string catalogError: ""
    property string instructionsError: ""
    property bool instructionsBusy: false
    signal instructionsLoaded(string text)
    signal instructionsSaved()
    signal chatEvent(var event)
    signal historyEvent(var event)
    signal actionEvent(var event)

    property bool workerReady: false
    property int sequence: 0
    property string catalogRequestId: ""
    property var pending: ({})
    property var outgoing: []

    function normalizeUrl(value) {
        const match = /^(https?:\/\/(?:127\.0\.0\.1|localhost|\[::1\]))(?::([0-9]{1,5}))?\/?$/i.exec(String(value).trim());
        if (!match || (match[2] && (Number(match[2]) === 0 || Number(match[2]) > 65535)))
            return "";
        return match[1].toLowerCase() + (match[2] ? ":" + Number(match[2]) : "");
    }

    function refresh(testConnection) {
        if (!baseUrl || catalogStatus === "loading") return;
        catalogStatus = "loading";
        catalogError = "";
        catalogRequestId = send(testConnection ? "probe" : "models", {});
    }

    function selectModel(modelId) {
        if (models.some(model => model.id === modelId))
            Config.setSetting("ai.connection.model", { baseUrl: baseUrl, id: modelId });
    }

    function generate(messages, options, proposeActions) {
        const settings = Config.getSetting("ai.generation", {}) || {};
        return send("chat", {
            model: selectedModelId,
            messages: messages,
            proposeActions: proposeActions === true,
            options: Object.assign({
                temperature: settings.temperature ?? 0.7,
                maxTokens: settings.maxTokens ?? 2048,
                stream: settings.streaming !== false
            }, options || {})
        });
    }

    function cancel(id) {
        if (pending[id] && pending[id].op === "chat")
            write({ id: id, op: "cancel" });
    }

    function loadInstructions() {
        if (instructionsBusy) return;
        instructionsBusy = true;
        instructionsError = "";
        send("load_instructions", {});
    }

    function saveInstructions(text) {
        if (instructionsBusy) return;
        instructionsBusy = true;
        instructionsError = "";
        send("save_instructions", { text: text });
    }

    function history(op, payload) {
        return send("history_" + op, payload || {});
    }

    function actionLog(op, payload) {
        return send("action_" + op, payload || {});
    }

    function send(op, payload) {
        const id = String(++sequence);
        pending[id] = { op: op };
        write(Object.assign({
            id: id, op: op, profile: { provider: "ollama", baseUrl: baseUrl }
        }, payload));
        return id;
    }

    function write(command) {
        const line = JSON.stringify(command) + "\n";
        if (workerReady) {
            worker.write(line);
        } else {
            outgoing.push(line);
            if (!startupTimer.running) {
                startupTimer.start();
                worker.running = true;
            }
        }
    }

    function receive(line) {
        let data;
        try { data = JSON.parse(line); } catch (_) { return; }
        if (!data || typeof data.id !== "string") return;
        const request = pending[data.id];
        if (!request) return;
        const terminal = ["completed", "error", "cancelled"].includes(data.event);
        if (terminal) delete pending[data.id];

        if (request.op === "chat") {
            chatEvent(data);
        } else if (request.op.startsWith("history_")) {
            historyEvent(data);
        } else if (request.op.startsWith("action_")) {
            actionEvent(data);
        } else if (terminal && (request.op === "probe" || request.op === "models")) {
            if (data.id !== catalogRequestId) return;
            if (data.event === "completed") {
                models = data.models;
                catalogStatus = models.length ? "connected" : "empty";
            } else {
                models = [];
                catalogStatus = "error";
                catalogError = data.code || "worker_unavailable";
            }
        } else if (terminal) {
            instructionsBusy = false;
            if (data.event !== "completed") instructionsError = data.code || "worker_unavailable";
            else if (request.op === "load_instructions") instructionsLoaded(data.text);
            else instructionsSaved();
        }
    }

    onBaseUrlChanged: {
        catalogRequestId = "";
        models = [];
        catalogStatus = "idle";
        catalogError = "";
    }

    function workerStopped() {
        workerReady = false;
        startupTimer.stop();
        outgoing = [];
        for (const id of Object.keys(pending))
            receive(JSON.stringify({ id: id, event: "error", code: "worker_unavailable" }));
    }

    Timer {
        id: startupTimer
        interval: 5000
        onTriggered: {
            worker.running = false;
            root.workerStopped();
        }
    }

    Process {
        id: worker
        command: ["python3", Caching.serpantinumDir + "/scripts/ai/worker.py"]
        clearEnvironment: true
        environment: ({ PATH: null, HOME: null, XDG_CONFIG_HOME: null, XDG_STATE_HOME: null })
        stdinEnabled: true
        stdout: SplitParser { onRead: line => root.receive(line) }
        onStarted: {
            startupTimer.stop();
            root.workerReady = true;
            for (const line of root.outgoing) write(line);
            root.outgoing = [];
        }
        onExited: root.workerStopped()
    }
}
