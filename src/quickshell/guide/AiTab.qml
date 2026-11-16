import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import "../"

GuideTab {
    id: tab

    readonly property string savedUrl: AiService.baseUrl
    readonly property bool ready: Config.dataReady
    readonly property bool canRefresh: ready && savedUrl !== ""
        && AiService.normalizeUrl(baseUrl.text) === savedUrl && AiService.catalogStatus !== "loading"
    readonly property var filteredModels: {
        const query = modelSearch.text.trim().toLowerCase();
        return AiService.models.filter(model => model.name.toLowerCase().includes(query));
    }
    property bool editingInstructions: false
    property bool instructionsSaved: false
    property bool historyWasCleared: false

    function t(key) { return I18n.t("guide.ai." + key); }
    function s(value) { return rootObj.s(value); }

    function saveUrl() {
        const value = AiService.normalizeUrl(baseUrl.text);
        if (ready && value)
            Config.setSetting("ai.connection.baseUrl", value);
    }

    function errorText(code) {
        const key = "error_" + code;
        const message = t(key);
        return message === "guide.ai." + key ? t("error_provider_error") : message;
    }

    Connections {
        target: AiService
        function onInstructionsLoaded(text) {
            if (!tab.isCurrent) return;
            instructions.text = text;
            tab.editingInstructions = true;
        }
        function onInstructionsSaved() { tab.instructionsSaved = true; }
    }
    Connections {
        target: AiChat
        function onHistoryCleared() { tab.historyWasCleared = true; }
    }

    function numberSetting(key, fallback, min, max) {
        const value = Config.getSetting(key, fallback);
        return typeof value === "number" && isFinite(value) ? Math.max(min, Math.min(max, value)) : fallback;
    }

    function saveTemperature(value) {
        if (ready)
            Config.setSetting("ai.generation.temperature", Number(value.toFixed(2)));
    }

    component Copy: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: tab.s(13)
    }

    component Hint: Copy {
        color: ThemeBackend.subtext1
        font.pixelSize: tab.s(12)
    }

    component Section: Rectangle {
        id: card
        property string heading
        default property alias fields: fieldsLayout.data
        Layout.fillWidth: true
        implicitHeight: fieldsLayout.implicitHeight + tab.s(32)
        radius: tab.s(12)
        color: ThemeBackend.surface0

        ColumnLayout {
            id: fieldsLayout
            anchors.fill: parent
            anchors.margins: tab.s(16)
            spacing: tab.s(8)

            Copy {
                text: card.heading
                font.pixelSize: tab.s(16)
                font.bold: true
            }
        }
    }

    Controls.Pane {
        anchors.fill: parent
        padding: 0
        background: null
        font.family: ThemeBackend.fontFamily
        font.pixelSize: tab.s(13)
        palette.window: ThemeBackend.surface0
        palette.windowText: ThemeBackend.text
        palette.button: ThemeBackend.surface1
        palette.buttonText: ThemeBackend.text
        palette.base: ThemeBackend.base
        palette.text: ThemeBackend.text
        palette.placeholderText: ThemeBackend.subtext1
        palette.highlight: ThemeBackend.primary
        palette.highlightedText: ThemeBackend.base

        Flickable {
            anchors.fill: parent
            anchors.margins: tab.s(12)
            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar {}

            ColumnLayout {
                id: body
                width: Math.min(parent.width - tab.s(12), tab.s(780))
                spacing: tab.s(12)

                Copy {
                    text: "Serpantinum AI"
                    font.pixelSize: tab.s(24)
                    font.bold: true
                }
                Controls.Button {
                    text: tab.t("open_chat")
                    onClicked: Quickshell.execDetached(["serpantinum", "msg", "open", "ai"])
                }

                Section {
                    heading: tab.t("connection")

                    Copy { text: tab.t("provider") }
                    Controls.ComboBox {
                        objectName: "aiProvider"
                        model: [tab.t("ollama")]
                        Accessible.name: tab.t("provider")
                    }

                    Copy { text: tab.t("base_url") }
                    RowLayout {
                        Layout.fillWidth: true
                        Controls.TextField {
                            id: baseUrl
                            objectName: "aiBaseUrl"
                            Layout.fillWidth: true
                            enabled: tab.ready
                            text: tab.savedUrl
                            placeholderText: AiService.defaultUrl
                            maximumLength: 128
                            selectByMouse: true
                            Accessible.name: tab.t("base_url")
                            onAccepted: tab.saveUrl()
                        }
                        Controls.Button {
                            objectName: "aiSaveUrl"
                            text: tab.t("save")
                            enabled: tab.ready && AiService.normalizeUrl(baseUrl.text) !== "" && AiService.normalizeUrl(baseUrl.text) !== tab.savedUrl
                            onClicked: tab.saveUrl()
                        }
                    }
                    Hint {
                        text: tab.t("local_url")
                        color: baseUrl.text && !AiService.normalizeUrl(baseUrl.text) ? ThemeBackend.red : ThemeBackend.subtext1
                    }

                    Copy { text: tab.t("api_key") }
                    Controls.TextField {
                        enabled: false
                        echoMode: TextInput.Password
                        Layout.fillWidth: true
                        placeholderText: tab.t("no_key")
                        Accessible.name: tab.t("api_key")
                    }

                    Controls.Button {
                        objectName: "aiProbe"
                        text: tab.t("test_connection")
                        enabled: tab.canRefresh
                        onClicked: AiService.refresh(true)
                    }
                    Hint {
                        objectName: "aiConnectionStatus"
                        color: AiService.catalogStatus === "error" ? ThemeBackend.red : ThemeBackend.subtext1
                        text: AiService.catalogStatus === "error" ? tab.errorText(AiService.catalogError)
                            : tab.t("status_" + AiService.catalogStatus)
                    }
                }

                Section {
                    heading: tab.t("models")

                    Controls.TextField {
                        id: modelSearch
                        objectName: "aiModelSearch"
                        Layout.fillWidth: true
                        enabled: AiService.models.length > 0
                        placeholderText: tab.t("search_models")
                        Accessible.name: tab.t("search_models")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Controls.ComboBox {
                            objectName: "aiModelPicker"
                            Layout.fillWidth: true
                            enabled: tab.filteredModels.length > 0
                            model: tab.filteredModels
                            textRole: "name"
                            currentIndex: tab.filteredModels.findIndex(model => model.id === AiService.selectedModelId)
                            displayText: currentIndex >= 0 ? currentText
                                : tab.t(AiService.models.length ? (enabled ? "choose_model" : "no_matches") : "no_models")
                            onActivated: index => AiService.selectModel(tab.filteredModels[index].id)
                            Accessible.name: tab.t("models")
                        }
                        Controls.Button {
                            text: tab.t("refresh_models")
                            enabled: tab.canRefresh
                            onClicked: AiService.refresh(false)
                        }
                    }
                    Hint {
                        objectName: "aiModelDetails"
                        readonly property var model: AiService.selectedModel
                        text: model ? [
                            model.family, model.parameter_size, model.quantization_level,
                            model.size > 0 ? (model.size / 1073741824).toFixed(2) + " GiB" : ""
                        ].filter(Boolean).join(" · ") || model.id
                            : tab.t(AiService.selectedModelId && AiService.catalogStatus === "connected"
                                ? "model_missing" : "model_details")
                    }
                }

                Section {
                    heading: tab.t("generation")

                    Copy { text: tab.t("temperature") + " · " + temperature.value.toFixed(2) }
                    Controls.Slider {
                        id: temperature
                        objectName: "aiTemperature"
                        Layout.fillWidth: true
                        enabled: tab.ready
                        from: 0
                        to: 2
                        stepSize: 0.05
                        snapMode: Controls.Slider.SnapAlways
                        value: tab.numberSetting("ai.generation.temperature", 0.7, from, to)
                        Accessible.name: tab.t("temperature")
                        onMoved: { if (!pressed) tab.saveTemperature(value); }
                        onPressedChanged: { if (!pressed) tab.saveTemperature(value); }
                    }

                    Copy { text: tab.t("max_tokens") }
                    Controls.SpinBox {
                        objectName: "aiMaxTokens"
                        enabled: tab.ready
                        editable: true
                        from: 1
                        to: 32768
                        value: Math.round(tab.numberSetting("ai.generation.maxTokens", 2048, from, to))
                        Accessible.name: tab.t("max_tokens")
                        onValueModified: Config.setSetting("ai.generation.maxTokens", value)
                    }
                    Controls.CheckBox {
                        objectName: "aiStreaming"
                        enabled: tab.ready
                        text: tab.t("streaming")
                        checked: Config.getSetting("ai.generation.streaming", true) !== false
                        onClicked: Config.setSetting("ai.generation.streaming", checked)
                    }

                    Copy { text: tab.t("system_instructions") }
                    Controls.Button {
                        visible: !tab.editingInstructions
                        enabled: !AiService.instructionsBusy
                        text: tab.t("edit_instructions")
                        onClicked: AiService.loadInstructions()
                    }
                    Controls.TextArea {
                        id: instructions
                        Layout.fillWidth: true
                        visible: tab.editingInstructions
                        enabled: !AiService.instructionsBusy
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        placeholderText: tab.t("instructions_placeholder")
                        Accessible.name: tab.t("system_instructions")
                        onTextChanged: tab.instructionsSaved = false
                    }
                    Controls.Button {
                        visible: tab.editingInstructions
                        enabled: !AiService.instructionsBusy && instructions.length <= 4096
                        text: tab.t("save")
                        onClicked: AiService.saveInstructions(instructions.text)
                    }
                    Hint {
                        visible: AiService.instructionsError !== "" || tab.instructionsSaved
                        text: AiService.instructionsError ? tab.errorText(AiService.instructionsError) : tab.t("instructions_saved")
                    }
                }

                Section {
                    heading: tab.t("privacy")

                    Controls.CheckBox {
                        objectName: "aiLocalHistory"
                        enabled: tab.ready
                        text: tab.t("local_history")
                        checked: Config.getSetting("ai.privacy.localHistory", false) === true
                        onClicked: Config.setSetting("ai.privacy.localHistory", checked)
                    }
                    Hint { text: tab.t("history_storage") }
                    Controls.Button {
                        text: tab.t("clear_history")
                        enabled: tab.ready && !AiChat.historyBusy
                        onClicked: clearHistoryDialog.open()
                    }
                    Hint {
                        visible: AiChat.historyError !== "" || tab.historyWasCleared
                        text: AiChat.historyError ? tab.t("error_history_error") : tab.t("history_cleared")
                    }
                    Copy { text: tab.t("permissions") }
                    Controls.CheckBox {
                        text: tab.t("allow_action_proposals")
                        enabled: tab.ready
                        checked: AiActions.enabledByUser
                        onClicked: Config.setSetting("ai.privacy.actionsEnabled", checked)
                    }
                    Hint { text: tab.t("confirm_actions_hint") }
                    Controls.CheckBox { text: tab.t("share_context"); enabled: false }
                    Hint { text: tab.t("local_only") }
                }
            }
        }
        Controls.Dialog {
            id: clearHistoryDialog
            anchors.centerIn: parent
            title: tab.t("clear_history")
            modal: true
            standardButtons: Controls.Dialog.Ok | Controls.Dialog.Cancel
            onAccepted: {
                tab.historyWasCleared = false;
                AiChat.clearHistory();
            }
            width: Math.min(parent.width - tab.s(24), tab.s(380))
            implicitHeight: tab.s(170)
            contentItem: Copy { text: tab.t("confirm_clear_history") }
        }
    }
}
