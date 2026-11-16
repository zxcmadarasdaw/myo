pragma Singleton
import QtQuick
import "../../"

Item {
    id: root
    visible: false

    property var conversations: []
    property string activeId: ""
    readonly property var active: conversations.find(chat => chat.id === activeId) || null
    readonly property bool generating: generation !== null
    readonly property bool activeGenerating: generating && generation.conversationId === activeId
    readonly property bool historyEnabled: Config.dataReady && Config.getSetting("ai.privacy.localHistory", false) === true
    readonly property bool historyBusy: historyTask !== null
    readonly property int maxPrompt: 12000
    readonly property bool canAddTurn: generating || !active
        || (active.messages.length < 126 && JSON.stringify(active).length < 185000)
    readonly property bool canSend: Config.dataReady && !generating && AiService.selectedModel !== null && canAddTurn
    readonly property bool canRegenerate: !generating && AiService.selectedModel !== null && active !== null
        && active.messages.length > 1 && active.messages[active.messages.length - 1].role === "assistant"

    property bool activated: false
    property var generation: null
    property string historyError: ""
    property var historyQueue: []
    property var historyTask: null
    property int historyEpoch: 0
    property var deletedIds: ({})

    signal historyCleared()
    signal conversationsCleared()

    function activate() {
        if (!activated) {
            activated = true;
            if (historyEnabled) enqueueHistory("load");
        }
        if (Config.dataReady && AiService.catalogStatus === "idle") AiService.refresh(false);
    }

    onHistoryEnabledChanged: {
        if (!activated) return;
        historyEpoch++;
        if (historyEnabled) enqueueHistory("load");
        else historyQueue = historyQueue.filter(task => task.op === "clear" || task.op === "delete");
    }

    function newConversation() {
        const chat = {
            id: Date.now().toString(36) + "-" + Math.random().toString(36).slice(2),
            title: "", messages: [], updatedAt: Date.now()
        };
        conversations = [chat].concat(conversations);
        activeId = chat.id;
        return chat;
    }

    function updateChat(chat, messages, updatedAt) {
        const updated = Object.assign({}, chat, { messages: messages, updatedAt: updatedAt });
        conversations = conversations.map(item => item.id === chat.id ? updated : item);
        return updated;
    }

    function contextFor(messages) {
        let context = [];
        let remaining = 48000;
        for (let index = messages.length - 1; index >= 0 && context.length < 64; --index) {
            const message = messages[index];
            if (message.role === "assistant" && message.status !== "complete") continue;
            if (message.content.length > remaining) break;
            remaining -= message.content.length;
            context.unshift({ role: message.role, content: message.content });
        }
        if (context.length > 1 && context[0].role === "assistant") context.shift();
        return context;
    }

    function send(text) {
        const prompt = text.trim();
        if (!canSend || !prompt || prompt.length > maxPrompt) return false;
        const chat = active || newConversation();
        const titled = chat.title ? chat : Object.assign({}, chat, { title: prompt.split(/\s+/).join(" ").slice(0, 72) });
        start(titled, chat.messages.concat({ role: "user", content: prompt, status: "complete" }));
        return true;
    }

    function regenerate() {
        if (canRegenerate) start(active, active.messages.slice(0, -1));
    }

    function start(chat, messages) {
        AiActions.dismiss("");
        const model = AiService.selectedModelId;
        const id = AiService.generate(contextFor(messages), {}, AiActions.enabledByUser);
        const updated = updateChat(chat, messages.concat({
            role: "assistant", content: "", status: "generating", model: model
        }), Math.max(Date.now(), chat.updatedAt + 1));
        generation = { id: id, conversationId: chat.id, buffer: "",
            remaining: Math.max(0, Math.min(64000, 275000 - JSON.stringify(updated).length)) };
        remember(updated);
    }

    function flush(event) {
        if (!generation) return;
        const request = generation;
        const chat = conversations.find(item => item.id === request.conversationId);
        if (!chat) return;
        const messages = chat.messages.slice();
        const message = Object.assign({}, messages[messages.length - 1]);
        message.content += request.buffer;
        if (request.memory) message.memory = request.memory;
        request.buffer = "";
        if (event) {
            message.status = event.event === "completed" ? "complete"
                : (event.event === "cancelled" ? "stopped" : "error");
            if (event.code) message.error = event.code;
            if (event.model) message.model = event.model;
            if (event.event === "completed" && (event.actionProposal || event.actionRejected)) {
                message.content = message.content.replace(/(?:^|\n)```serpantinum-action[ \t]*\r?\n[^\r\n]{1,500}\r?\n```[ \t]*\s*$/, "").replace(/\s+$/, "");
                if (event.actionProposal) AiActions.prepare(event.actionProposal, chat.id);
                else AiActions.report(chat.id, "invalid");
            }
            generation = null;
            streamBatch.stop();
        }
        messages[messages.length - 1] = message;
        const updated = updateChat(chat, messages, event ? Math.max(Date.now(), chat.updatedAt + 1) : chat.updatedAt);
        if (event) remember(updated);
    }

    function stop() {
        if (!generation) return;
        AiService.cancel(generation.id);
        flush({ event: "cancelled" });
    }

    function receive(event) {
        if (!generation || event.id !== generation.id || event.event === "started") return;
        if (event.event === "system_facts") {
            generation.memory = event.memory;
            flush(null);
        } else if (event.event === "delta") {
            const length = JSON.stringify(event.text).length - 2;
            if (length > generation.remaining) {
                generation.buffer += event.text.slice(0, Math.floor(generation.remaining / 6));
                AiService.cancel(generation.id);
                flush({ event: "error", code: "response_limit" });
            } else {
                generation.buffer += event.text;
                generation.remaining -= length;
                if (!streamBatch.running) streamBatch.start();
            }
        } else {
            flush(event);
        }
    }

    function forgetGeneration(conversationId) {
        if (generation && (!conversationId || generation.conversationId === conversationId)) {
            AiService.cancel(generation.id);
            generation = null;
            streamBatch.stop();
        }
    }

    function deleteConversation(id) {
        if (!conversations.some(chat => chat.id === id)) return;
        forgetGeneration(id);
        AiActions.dismiss(id);
        deletedIds[id] = true;
        conversations = conversations.filter(chat => chat.id !== id);
        if (activeId === id) activeId = conversations.length ? conversations[0].id : "";
        historyQueue = historyQueue.filter(task => task.op !== "save" || task.payload.conversation.id !== id);
        enqueueHistory("delete", { conversationId: id });
    }

    function clearHistory() {
        forgetGeneration("");
        AiActions.dismiss("");
        historyEpoch++;
        historyQueue = [];
        conversations = [];
        deletedIds = ({});
        activeId = "";
        conversationsCleared();
        historyError = "";
        enqueueHistory("clear");
    }

    function remember(chat) {
        if (!historyEnabled || !chat.messages.length) return;
        const snapshot = Object.assign({}, chat, {
            messages: chat.messages.map(message => message.status === "generating"
                ? Object.assign({}, message, { status: "stopped" }) : message)
        });
        historyQueue = historyQueue.filter(task => task.op !== "save" || task.payload.conversation.id !== chat.id);
        enqueueHistory("save", { conversation: snapshot });
    }

    function enqueueHistory(op, payload) {
        historyQueue.push({ op: op, payload: payload, epoch: historyEpoch, rows: [] });
        pumpHistory();
    }

    function pumpHistory() {
        if (historyTask || !historyQueue.length) return;
        const task = historyQueue.shift();
        task.id = AiService.history(task.op, task.payload);
        historyTask = task;
    }

    function receiveHistory(event) {
        const task = historyTask;
        if (!task || task.id !== event.id || event.event === "started") return;
        if (event.event === "history_item") {
            task.rows.push(event.conversation);
            return;
        }
        if (event.event === "completed") {
            if (task.op === "load" && historyEnabled && task.epoch === historyEpoch) {
                const current = conversations;
                const stored = task.rows.filter(chat => !deletedIds[chat.id] && !current.some(item => item.id === chat.id));
                conversations = current.concat(stored).sort((left, right) => right.updatedAt - left.updatedAt);
                if (!activeId && conversations.length) activeId = conversations[0].id;
                for (const chat of current) remember(chat);
            } else if (task.op === "clear") {
                historyError = "";
                historyCleared();
            }
        } else {
            historyError = event.code || "history_error";
        }
        historyTask = null;
        Qt.callLater(pumpHistory);
    }

    Timer { id: streamBatch; interval: 45; onTriggered: root.flush(null) }
    Connections {
        target: AiService
        function onChatEvent(event) { root.receive(event); }
        function onHistoryEvent(event) { root.receiveHistory(event); }
    }
    Connections {
        target: Config
        function onDataReadyChanged() {
            if (root.activated && Config.dataReady && AiService.catalogStatus === "idle") AiService.refresh(false);
        }
    }
}
