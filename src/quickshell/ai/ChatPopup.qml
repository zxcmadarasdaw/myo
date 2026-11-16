import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import "../"
import "ChatMarkdown.js" as Markdown

Item {
    id: popup
    visible: false
    signal closeRequested()
    signal navigateRequested(string target, string tab)

    readonly property bool compact: width < Scaler.s(610)
    property bool showConversations: false
    readonly property var messages: visible && AiChat.active ? AiChat.active.messages : []
    readonly property var colors: ({
        base: ThemeBackend.base, primary: ThemeBackend.primary, muted: ThemeBackend.subtext1,
        green: ThemeBackend.green, peach: ThemeBackend.peach
    })
    readonly property var matches: {
        if (!visible) return [];
        const search = conversationSearch.text.trim().toLowerCase();
        if (!search) return AiChat.conversations;
        return AiChat.conversations.filter(chat => chat.title.toLowerCase().includes(search)
            || chat.messages.some(message => message.content.toLowerCase().includes(search)));
    }
    property var drafts: ({})
    property string draftOwner: ""

    function t(key) { return I18n.t("guide.ai." + key); }
    function s(value) { return Scaler.s(value); }
    function actionText(action, label) {
        const description = t("action_" + action.id);
        return label ? description + " · " + label : description;
    }
    function errorText(code) {
        return I18n.t("guide.ai.error_" + code, t("error_provider_error"));
    }

    function memoryText(memory) {
        if (!memory) return "";
        if (memory.status !== "available") return t("memory_unavailable");
        return I18n.t("guide.ai.memory_sample", {
            used: memory.usedGiB, total: memory.totalGiB, percent: memory.percent
        });
    }

    function updateComposer() {
        if (composer.length) drafts[draftOwner] = composer.text;
        else delete drafts[draftOwner];
        draftOwner = AiChat.activeId;
        composer.text = drafts[draftOwner] || "";
        Qt.callLater(transcript.positionViewAtEnd);
    }

    function submit() {
        const owner = draftOwner;
        if (!AiChat.send(composer.text)) return;
        delete drafts[owner];
        composer.clear();
        Qt.callLater(transcript.positionViewAtEnd);
    }

    function copy(text) {
        clipboard.text = text;
        clipboard.selectAll();
        clipboard.copy();
        clipboard.clear();
    }

    onVisibleChanged: if (visible) {
        AiChat.activate();
        Qt.callLater(function() {
            transcript.positionViewAtEnd();
            if (composer.visible) composer.forceActiveFocus();
        });
    }
    Component.onCompleted: updateComposer()
    Connections {
        target: AiChat
        function onActiveIdChanged() { popup.updateComposer(); }
        function onConversationsCleared() {
            popup.drafts = ({});
            composer.clear();
        }
    }
    Connections {
        target: AiActions
        function onNavigateRequested(target, tab) { popup.navigateRequested(target, tab); }
    }

    TextEdit { id: clipboard; visible: false; textFormat: TextEdit.PlainText }

    component Caption: Text {
        Layout.fillWidth: true
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: popup.s(13)
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
    }

    Rectangle {
        anchors.fill: parent
        color: ThemeBackend.base
        radius: popup.s(18)
        clip: true

        Controls.Pane {
            anchors.fill: parent
            padding: popup.s(12)
            background: null
            font.family: ThemeBackend.fontFamily
            font.pixelSize: popup.s(13)
            palette.window: ThemeBackend.base
            palette.windowText: ThemeBackend.text
            palette.button: ThemeBackend.surface0
            palette.buttonText: ThemeBackend.text
            palette.base: ThemeBackend.surface0
            palette.text: ThemeBackend.text
            palette.placeholderText: ThemeBackend.subtext1
            palette.highlight: ThemeBackend.primary
            palette.highlightedText: ThemeBackend.base

            ColumnLayout {
                anchors.fill: parent
                spacing: popup.s(8)

                RowLayout {
                    Layout.fillWidth: true
                    Controls.Button {
                        visible: popup.compact
                        text: popup.t(popup.showConversations ? "back_to_chat" : "conversations")
                        onClicked: popup.showConversations = !popup.showConversations
                    }
                    Caption {
                        text: "Serpantinum AI"
                        font.bold: true
                        font.pixelSize: popup.s(18)
                    }
                    Controls.Button {
                        text: popup.t("action_log")
                        enabled: !AiActions.busy
                        onClicked: {
                            AiActions.loadJournal();
                            journal.open();
                        }
                    }
                    Controls.ToolButton {
                        text: "×"
                        Accessible.name: popup.t("close_chat")
                        onClicked: popup.closeRequested()
                    }
                }

                RowLayout {
                    spacing: popup.s(10)
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        objectName: "aiConversationPane"
                        visible: !popup.compact || popup.showConversations
                        Layout.preferredWidth: popup.s(210)
                        Layout.fillWidth: popup.compact
                        Layout.fillHeight: true
                        radius: popup.s(12)
                        color: ThemeBackend.surface0

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: popup.s(8)
                            Controls.Button {
                                Layout.fillWidth: true
                                text: popup.t("new_chat")
                                onClicked: {
                                    AiChat.newConversation();
                                    popup.showConversations = false;
                                    Qt.callLater(function() { composer.forceActiveFocus(); });
                                }
                            }
                            Controls.TextField {
                                id: conversationSearch
                                objectName: "aiChatSearch"
                                Layout.fillWidth: true
                                placeholderText: popup.t("search_chats")
                                Accessible.name: placeholderText
                                selectByMouse: true
                            }
                            ListView {
                                id: sidebar
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: popup.s(4)
                                clip: true
                                model: popup.matches.length
                                Controls.ScrollBar.vertical: Controls.ScrollBar {}
                                delegate: RowLayout {
                                    required property int index
                                    readonly property var chat: popup.matches[index]
                                    width: sidebar.width
                                    Controls.ItemDelegate {
                                        id: chatButton
                                        Layout.fillWidth: true
                                        text: chat && chat.title ? chat.title : popup.t("untitled_chat")
                                        highlighted: chat && chat.id === AiChat.activeId
                                        contentItem: Text {
                                            text: chatButton.text
                                            color: ThemeBackend.text
                                            font: chatButton.font
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                            textFormat: Text.PlainText
                                        }
                                        onClicked: if (chat) {
                                            AiChat.activeId = chat.id;
                                            popup.showConversations = false;
                                        }
                                    }
                                    Controls.ToolButton {
                                        text: "×"
                                        Accessible.name: popup.t("delete_chat")
                                        onClicked: if (chat) {
                                            removeDialog.conversationId = chat.id;
                                            removeDialog.open();
                                        }
                                    }
                                }
                            }
                            Caption {
                                visible: !popup.matches.length
                                text: popup.t(conversationSearch.text.trim() ? "no_chats_match" : "no_chats")
                                color: ThemeBackend.subtext1
                            }
                        }
                    }

                    ColumnLayout {
                        visible: !popup.compact || !popup.showConversations
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: popup.s(7)

                        RowLayout {
                            Layout.fillWidth: true
                            Controls.ComboBox {
                                Layout.fillWidth: true
                                model: AiService.models
                                textRole: "name"
                                enabled: count > 0
                                currentIndex: AiService.models.findIndex(model => model.id === AiService.selectedModelId)
                                displayText: currentIndex >= 0 ? currentText
                                    : popup.t(enabled ? "choose_model" : "no_models")
                                Accessible.name: popup.t("models")
                                onActivated: index => AiService.selectModel(AiService.models[index].id)
                            }
                            Controls.Button {
                                enabled: Config.dataReady && AiService.baseUrl && AiService.catalogStatus !== "loading"
                                text: popup.t("refresh_models")
                                onClicked: AiService.refresh(false)
                            }
                        }
                        Caption {
                            visible: !AiService.selectedModel || AiService.catalogStatus === "error"
                            text: AiService.catalogStatus === "error" ? popup.errorText(AiService.catalogError)
                                : (AiService.catalogStatus === "empty" || AiService.catalogStatus === "loading"
                                    ? popup.t("status_" + AiService.catalogStatus) : popup.t("choose_model"))
                            color: ThemeBackend.subtext1
                        }
                        Caption {
                            visible: AiChat.historyError !== ""
                            text: popup.t("error_history_error")
                            color: ThemeBackend.peach
                        }

                        ListView {
                            id: transcript
                            objectName: "aiTranscript"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: popup.s(8)
                            model: popup.messages.length
                            onCountChanged: Qt.callLater(positionViewAtEnd)
                            onContentHeightChanged: {
                                if (stickToEnd) Qt.callLater(positionViewAtEnd);
                            }
                            property bool stickToEnd: true
                            onMovementEnded: stickToEnd = atYEnd
                            Controls.ScrollBar.vertical: Controls.ScrollBar {}
                            delegate: Rectangle {
                                required property int index
                                readonly property var message: popup.messages[index] || ({})
                                width: Math.max(0, transcript.width - popup.s(9))
                                height: bubble.implicitHeight + popup.s(18)
                                radius: popup.s(10)
                                color: message.role === "user" ? ThemeBackend.surface1 : ThemeBackend.surface0

                                ColumnLayout {
                                    id: bubble
                                    anchors.fill: parent
                                    anchors.margins: popup.s(9)
                                    spacing: popup.s(4)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Caption {
                                            text: message.role === "user" ? popup.t("you") : (message.model || "Serpantinum AI")
                                            font.bold: true
                                        }
                                        Controls.ToolButton {
                                            text: popup.t("copy_message")
                                            visible: !!message.content
                                            onClicked: popup.copy(message.content)
                                        }
                                    }
                                    Caption {
                                        objectName: "aiMemorySample"
                                        visible: !!message.memory
                                        text: popup.memoryText(message.memory)
                                        color: ThemeBackend.primary
                                    }
                                    TextEdit {
                                        Layout.fillWidth: true
                                        readOnly: true
                                        selectByMouse: true
                                        wrapMode: TextEdit.Wrap
                                        color: ThemeBackend.text
                                        selectionColor: ThemeBackend.primary
                                        selectedTextColor: ThemeBackend.base
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: popup.s(14)
                                        textFormat: message.role === "assistant" ? TextEdit.RichText : TextEdit.PlainText
                                        text: message.role === "assistant"
                                            ? Markdown.render(message.content || "", popup.colors) : (message.content || "")
                                    }
                                    Caption {
                                        visible: ["generating", "stopped", "error"].includes(message.status)
                                        text: message.status === "error" ? popup.errorText(message.error)
                                            : popup.t("message_" + message.status)
                                        color: ThemeBackend.subtext1
                                    }
                                }
                            }
                        }

                        Caption {
                            visible: !popup.messages.length
                            text: popup.t("empty_chat")
                            color: ThemeBackend.subtext1
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Rectangle {
                            id: actionCard
                            readonly property var item: AiActions.proposal
                            visible: !!item && item.conversationId === AiChat.activeId
                            Layout.fillWidth: true
                            implicitHeight: approval.implicitHeight + popup.s(14)
                            radius: popup.s(10)
                            color: ThemeBackend.surface0
                            ColumnLayout {
                                id: approval
                                anchors.fill: parent
                                anchors.margins: popup.s(7)
                                Caption {
                                    text: actionCard.item ? (actionCard.item.undo ? popup.t("action_undo") + " · " : "")
                                        + popup.actionText(actionCard.item.action, actionCard.item.label) : ""
                                    font.bold: true
                                }
                                RowLayout {
                                    Layout.alignment: Qt.AlignRight
                                    Controls.Button {
                                        text: popup.t("action_decline")
                                        onClicked: AiActions.dismiss(AiChat.activeId)
                                    }
                                    Controls.Button {
                                        text: popup.t("action_confirm")
                                        enabled: !!actionCard.item && !AiActions.busy
                                        onClicked: if (actionCard.item) AiActions.confirm(actionCard.item.token)
                                    }
                                }
                            }
                        }
                        Caption {
                            visible: AiActions.feedback !== "" && AiActions.feedbackConversation === AiChat.activeId
                            text: AiActions.feedback ? popup.t("action_status_" + AiActions.feedback) : ""
                            color: ThemeBackend.subtext1
                        }
                        Controls.ScrollView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: popup.s(76)
                            clip: true
                            Controls.TextArea {
                                id: composer
                                objectName: "aiComposer"
                                placeholderText: popup.t("write_prompt")
                                Accessible.name: placeholderText
                                wrapMode: TextEdit.Wrap
                                textFormat: TextEdit.PlainText
                                Keys.onReturnPressed: event => {
                                    if ((event.modifiers & Qt.ControlModifier) && !composer.inputMethodComposing) {
                                        popup.submit();
                                        event.accepted = true;
                                    } else event.accepted = false;
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Caption {
                                color: ThemeBackend.subtext1
                                text: popup.t(composer.length > AiChat.maxPrompt ? "prompt_limit"
                                    : (!AiChat.canAddTurn ? "chat_limit" : "send_shortcut"))
                            }
                            Controls.Button {
                                text: popup.t("repeat")
                                enabled: AiChat.canRegenerate
                                onClicked: {
                                    transcript.stickToEnd = true;
                                    AiChat.regenerate();
                                }
                            }
                            Controls.Button {
                                text: popup.t(AiChat.generating ? "stop" : "send")
                                enabled: AiChat.generating || (AiChat.canSend && composer.text.trim() && composer.length <= AiChat.maxPrompt)
                                onClicked: {
                                    if (AiChat.generating) AiChat.stop();
                                    else popup.submit();
                                }
                            }
                        }
                    }
                }
            }

            Controls.Dialog {
                id: removeDialog
                property string conversationId: ""
                anchors.centerIn: parent
                title: popup.t("delete_chat")
                modal: true
                standardButtons: Controls.Dialog.Ok | Controls.Dialog.Cancel
                onAccepted: {
                    AiChat.deleteConversation(conversationId);
                    delete popup.drafts[conversationId];
                }
                width: Math.min(parent.width - popup.s(24), popup.s(380))
                implicitHeight: popup.s(170)
                contentItem: Caption { text: popup.t("confirm_delete_chat") }
            }
            Controls.Dialog {
                id: journal
                anchors.centerIn: parent
                width: Math.min(parent.width - popup.s(24), popup.s(530))
                height: Math.min(parent.height - popup.s(24), popup.s(410))
                implicitHeight: popup.s(410)
                title: popup.t("action_log")
                modal: true
                standardButtons: Controls.Dialog.Close
                contentItem: ListView {
                    id: journalList
                    clip: true
                    spacing: popup.s(7)
                    model: AiActions.records.length
                    Controls.ScrollBar.vertical: Controls.ScrollBar {}
                    Caption {
                        width: journalList.width - popup.s(12)
                        visible: !journalList.count
                        text: AiActions.journalLoading ? popup.t("action_log_loading")
                            : (AiActions.feedback === "log_error" ? popup.t("action_status_log_error") : popup.t("action_log_empty"))
                    }
                    delegate: RowLayout {
                        required property int index
                        readonly property var record: AiActions.records[index]
                        width: journalList.width - popup.s(12)
                        ColumnLayout {
                            Layout.fillWidth: true
                            Caption {
                                text: record ? (record.undo ? popup.t("action_undo") + " · " : "")
                                    + popup.actionText(record, String(record.target ?? "")) : ""
                            }
                            Caption {
                                text: record ? new Date(record.at).toLocaleString()
                                    + " · " + popup.t("action_status_" + record.outcome) : ""
                                color: ThemeBackend.subtext1
                            }
                        }
                        Controls.Button {
                            text: popup.t("action_undo")
                            visible: !!record && !!AiActions.undoRecords[record.recordId]
                            enabled: AiActions.enabledByUser && !AiActions.busy
                            onClicked: {
                                if (!AiChat.activeId) AiChat.newConversation();
                                AiActions.requestUndo(record.recordId, AiChat.activeId);
                                journal.close();
                            }
                        }
                    }
                }
            }
        }
    }
}
