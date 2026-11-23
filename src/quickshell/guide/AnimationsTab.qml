import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../"
import "../reusables/guide"

GuideTab {
    id: root

    readonly property string script: Caching.serpantinumDir + "/scripts/system/hypr_animations.py"
    readonly property bool hyprland: Boolean(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"))
    readonly property var leaves: ["open", "close", "move", "focus", "workspace", "special"]
    property var catalog: null
    property var saved: null
    property var draft: null
    property string leaf: "open"
    property string operation: "load"
    property string status: ""
    property bool failed: false
    property var windows: []
    property var demonstration: null
    property real progress: 1
    readonly property var effect: (draft || (catalog && catalog.presets.classic))?.effects[leaf]
    readonly property bool dirty: JSON.stringify(saved) !== JSON.stringify(draft)

    function tr(key, fallback) { return I18n.t("guide.animations." + key, fallback); }
    function copy(value) { return JSON.parse(JSON.stringify(value)); }
    function label(value) {
        const labels = {
            classic: "Classic", smooth: "Smooth", dynamic: "Dynamic", minimal: "Minimal",
            cinematic: "Cinematic", custom: "Custom", fade: "Fade", scale: "Scale",
            zoom: "Zoom", slide: "Slide", slidevert: "Vertical slide", slidefade: "Slide + fade",
            slidefadevert: "Vertical slide + fade", pop: "Pop", linear: "Linear", off: "Off",
            auto: "Automatic", left: "Left", right: "Right", top: "Top", bottom: "Bottom",
            default: "Defaults", open: "Open windows", close: "Close windows",
            move: "Move and resize", focus: "Focus change", workspace: "Workspaces",
            special: "Special workspaces"
        };
        return tr(value, labels[value] || value);
    }
    function customize() {
        const state = copy(draft || catalog.presets.classic);
        state.preset = "custom";
        return state;
    }
    function change(key, value) {
        const state = customize();
        const effect = state.effects[leaf];
        effect[key] = value;
        if (key === "style") {
            if (value === "pop") effect.curve = "pop";
            if (value === "smooth") effect.curve = "smooth";
            if (value === "zoom") effect.strength = 55;
            if (value === "scale") effect.strength = 20;
        }
        draft = state;
    }
    function saveRule(value, match, style) {
        const state = customize();
        const index = state.rules.findIndex(rule => rule.match === match && rule.value === value);
        const rule = { value: value, match: match, style: style };
        if (index < 0) state.rules.push(rule);
        else state.rules[index] = rule;
        draft = state;
    }
    function run(action, args) {
        operation = action;
        status = "";
        failed = false;
        backend.command = ["python3", script, action].concat(args || []);
        backend.running = true;
    }
    function playPreview() {
        visual.stop();
        demonstration = Object.assign({ leaf: leaf }, effect);
        progress = 0;
        visual.restart();
    }

    Component.onCompleted: run("load")
    Process {
        id: backend
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: function(code) {
            if (code !== 0) {
                root.failed = true;
                root.status = errors.text.trim() || root.tr("failed", "Could not update animation settings.");
                return;
            }
            try {
                const result = JSON.parse(output.text);
                if (root.operation === "clients") {
                    root.windows = result;
                    if (!result.length) root.status = root.tr("no_windows", "No open windows found.");
                    return;
                }
                if (root.operation === "load") root.catalog = result;
                root.saved = result.current;
                root.draft = root.copy(result.current);
                if (root.operation === "apply") root.status = root.tr("applied", "Applied to Hyprland.");
            } catch (error) {
                root.failed = true;
                root.status = String(error);
            }
        }
    }

    component Choice: ComboBox {
        property var values: []
        property string selected: ""
        model: values.map(value => root.label(value))
        currentIndex: values.indexOf(selected)
        Layout.preferredWidth: 190
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: root.rootObj.s(18)
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            width: parent.width
            spacing: 10
            enabled: !backend.running
            LayoutMirroring.enabled: I18n.rtl
            LayoutMirroring.childrenInherit: true

            SettingsRow {
                title: root.tr("profile", "Window animation profile")
                description: root.hyprland ? root.tr("intro", "Applies to application windows and workspaces.")
                    : root.tr("requires_hyprland", "Applying window animations requires a running Hyprland session.")
                icon: "󰕧"
                wrapText: true
                Choice {
                    enabled: root.catalog !== null
                    values: ["default", "classic", "smooth", "dynamic", "minimal", "cinematic", "custom"]
                    selected: root.draft ? root.draft.preset : "default"
                    onActivated: function(index) {
                        const value = values[index];
                        root.draft = value === "default" ? null
                            : value === "custom" ? root.customize() : root.copy(root.catalog.presets[value]);
                    }
                }
            }

            SettingsGroup {
                visible: root.catalog !== null
                title: root.tr("effects", "Window and workspace effects")
                icon: "󰖲"
                subSettings: [
                    SettingsRow {
                        title: root.tr("event", "Event")
                        Choice {
                            values: root.leaves
                            selected: root.leaf
                            onActivated: function(index) { root.leaf = values[index]; }
                        }
                    },
                    SettingsRow {
                        title: root.tr("style", "Effect")
                        Choice {
                            values: root.catalog?.styles[root.leaf] || []
                            selected: root.effect?.style || ""
                            onActivated: function(index) { root.change("style", values[index]); }
                        }
                    },
                    SettingsRow {
                        title: root.tr("duration", "Duration (ms)")
                        enabled: root.effect?.style !== "off"
                        SpinBox {
                            from: 50
                            to: 2000
                            stepSize: 10
                            editable: true
                            value: root.effect?.duration || 500
                            onValueModified: root.change("duration", value)
                        }
                    },
                    SettingsRow {
                        title: root.tr("curve", "Easing")
                        enabled: root.effect?.style !== "off"
                        Choice {
                            values: root.catalog?.curves || []
                            selected: root.effect?.curve || ""
                            onActivated: function(index) { root.change("curve", values[index]); }
                        }
                    },
                    SettingsRow {
                        visible: ["scale", "zoom", "pop", "smooth"].includes(root.effect?.style) && root.leaf !== "move"
                            || ["workspace", "special"].includes(root.leaf) && (root.effect?.style || "").startsWith("slide")
                            || root.leaf === "focus" && root.effect?.style === "fade"
                        title: root.leaf === "focus" ? root.tr("dim", "Dim inactive windows (%)") : root.tr("strength", "Intensity (%)")
                        SpinBox {
                            from: 0
                            to: root.leaf === "focus" ? 75 : 100
                            editable: true
                            value: root.effect?.strength || 0
                            onValueModified: root.change("strength", value)
                        }
                    },
                    SettingsRow {
                        visible: ["open", "close"].includes(root.leaf) && root.effect?.style === "slide"
                        title: root.tr("direction", "Direction")
                        Choice {
                            values: root.catalog?.sides || []
                            selected: root.effect?.direction || ""
                            onActivated: function(index) { root.change("direction", values[index]); }
                        }
                    }
                ]
            }

            Rectangle {
                id: stage
                visible: root.catalog !== null
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                radius: ThemeBackend.clampedBorderRadius
                color: ThemeBackend.surface0
                clip: true

                readonly property var sample: root.demonstration
                readonly property bool outgoing: sample?.leaf === "close"
                readonly property bool moving: sample?.leaf === "move" && sample?.style !== "off"
                readonly property bool sliding: (sample?.style || "").startsWith("slide") || moving
                readonly property bool translucent: !!sample && (["open", "close"].includes(sample.leaf)
                    || sample.style.includes("fade"))
                readonly property real remaining: outgoing ? root.progress : 1 - root.progress
                readonly property string direction: sample?.style.includes("vert") ? "bottom" : sample?.direction || "auto"

                Rectangle {
                    width: Math.min(180, stage.width / 2) * (stage.moving ? 1 - 0.25 * stage.remaining : 1)
                    height: 100
                    anchors.centerIn: parent
                    radius: ThemeBackend.clampedBorderRadius
                    color: ThemeBackend.base
                    border.color: ThemeBackend.mauve
                    opacity: !stage.sample || stage.sample.style === "off" ? 1
                        : stage.sample.leaf === "focus" ? 1 - stage.remaining * stage.sample.strength / 100
                        : stage.translucent ? 1 - stage.remaining : 1
                    scale: stage.sample && ["open", "close"].includes(stage.sample.leaf)
                        && ["scale", "zoom", "pop", "smooth"].includes(stage.sample.style)
                        ? Math.max(0.05, 1 - stage.remaining * stage.sample.strength / 100) : 1
                    transform: Translate {
                        x: !stage.sliding || ["top", "bottom"].includes(stage.direction) ? 0
                            : stage.remaining * stage.width * (stage.direction === "left" ? -0.4 : 0.4)
                        y: !stage.sliding || !["top", "bottom"].includes(stage.direction) ? 0
                            : stage.remaining * stage.height * (stage.direction === "top" ? -0.8 : 0.8)
                    }
                    Label {
                        anchors.centerIn: parent
                        text: root.tr("sample", "Application window")
                        font.family: ThemeBackend.fontFamily
                        color: ThemeBackend.text
                    }
                }
            }

            NumberAnimation {
                id: visual
                target: root
                property: "progress"
                from: 0
                to: 1
                duration: root.demonstration?.duration || 500
                easing.type: root.demonstration?.curve === "linear" ? Easing.Linear
                    : root.demonstration?.curve === "pop" ? Easing.OutBack
                    : root.demonstration?.curve === "smooth" ? Easing.InOutCubic : Easing.OutCubic
            }

            Flow {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    enabled: root.catalog !== null
                    text: root.tr("preview", "Preview effect")
                    onClicked: root.playPreview()
                }
                Button {
                    enabled: root.hyprland && !root.dirty
                    text: root.tr("real_window", "Open test window")
                    onClicked: { testWindow.show(); testWindow.raise(); testWindow.requestActivate(); }
                }
                Button {
                    enabled: root.hyprland && root.dirty
                    highlighted: true
                    text: root.tr("apply", "Apply")
                    onClicked: root.run("apply", [JSON.stringify(root.draft)])
                }
                Button {
                    enabled: root.dirty
                    text: root.tr("discard", "Discard changes")
                    onClicked: root.draft = root.copy(root.saved)
                }
                Button {
                    enabled: root.draft !== null && JSON.stringify(root.effect) !==
                        JSON.stringify(root.catalog?.presets.classic.effects[root.leaf])
                    text: root.tr("reset_effect", "Reset this effect")
                    onClicked: {
                        const state = root.customize();
                        state.effects[root.leaf] = root.copy(root.catalog.presets.classic.effects[root.leaf]);
                        root.draft = state;
                    }
                }
                Button {
                    enabled: root.draft !== null
                    text: root.tr("reset", "Restore defaults")
                    onClicked: root.draft = null
                }
            }

            Label {
                visible: root.status !== "" || backend.running
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: backend.running ? root.tr("working", "Working…") : root.status
                color: root.failed ? ThemeBackend.red : ThemeBackend.text
            }

            SettingsGroup {
                visible: root.catalog !== null
                icon: "󰀻"
                title: root.tr("applications", "Application rules")
                description: root.tr("rule_limits", "Each application can override one style for both opening and closing. Timing and easing follow the global settings.")
                wrapText: true
                subSettings: [
                    SettingsRow {
                        title: root.tr("installed", "Installed application")
                        ComboBox {
                            id: apps
                            model: DesktopEntries.applications.values
                            currentIndex: -1
                            textRole: "name"
                            Layout.preferredWidth: 210
                            delegate: ItemDelegate {
                                required property var modelData
                                required property int index
                                width: apps.width
                                highlighted: apps.highlightedIndex === index
                                contentItem: RowLayout {
                                    Image {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        source: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    Label { Layout.fillWidth: true; text: modelData.name; elide: Text.ElideRight }
                                }
                            }
                            onActivated: function(index) {
                                const app = model[index];
                                windowClass.text = String(app.startupWmClass || app.id || "").replace(/\.desktop$/, "");
                            }
                        }
                    },
                    SettingsRow {
                        title: root.tr("open_windows", "Open windows")
                        searchKeywords: "Wayland XWayland class initialClass"
                        ComboBox {
                            id: liveApps
                            model: root.windows.map(window => (window.class || window.initialClass) + (window.title ? " · " + window.title : ""))
                            enabled: count > 0
                            Layout.preferredWidth: 150
                            onActivated: function(index) {
                                const window = root.windows[index];
                                windowClass.text = matchType.currentIndex === 1 ? window.initialClass : window.class;
                            }
                        }
                        Button {
                            enabled: root.hyprland
                            text: root.tr("refresh", "Refresh")
                            onClicked: root.run("clients")
                        }
                    },
                    SettingsRow {
                        title: root.tr("window_class", "Window class")
                        TextField {
                            id: windowClass
                            placeholderText: "org.mozilla.firefox"
                            maximumLength: 200
                            Layout.preferredWidth: 190
                        }
                        ComboBox {
                            id: matchType
                            model: ["class", "initialClass"]
                            Layout.preferredWidth: 110
                        }
                    },
                    SettingsRow {
                        title: root.tr("rule_style", "Application effect")
                        ComboBox {
                            id: ruleStyle
                            model: (root.catalog?.ruleStyles || []).map(style => root.label(style))
                        }
                        Button {
                            enabled: windowClass.text.trim().length > 0 && ruleStyle.currentIndex >= 0
                            text: root.tr("save_rule", "Add or update rule")
                            onClicked: root.saveRule(windowClass.text.trim(), root.catalog.matches[matchType.currentIndex],
                                root.catalog.ruleStyles[ruleStyle.currentIndex])
                        }
                    },
                    Repeater {
                        model: root.draft?.rules || []
                        delegate: SettingsRow {
                            required property var modelData
                            required property int index
                            title: modelData.value
                            description: (modelData.match === "class" ? "class" : "initialClass") + " · " + root.label(modelData.style)
                            Button {
                                text: root.tr("edit", "Edit")
                                onClicked: {
                                    windowClass.text = modelData.value;
                                    matchType.currentIndex = root.catalog.matches.indexOf(modelData.match);
                                    ruleStyle.currentIndex = root.catalog.ruleStyles.indexOf(modelData.style);
                                }
                            }
                            Button {
                                text: root.tr("remove", "Remove")
                                onClicked: {
                                    const updated = root.customize();
                                    updated.rules.splice(index, 1);
                                    root.draft = updated;
                                }
                            }
                        }
                    }
                ]
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.tr("minimize_note", "MYO minimizes windows to a hidden workspace. Hyprland has no dedicated minimize or restore animation.")
                color: ThemeBackend.subtext0
            }
        }
    }

    Window {
        id: testWindow
        width: 360
        height: 200
        title: root.tr("sample", "Application window")
        color: ThemeBackend.base
        Button {
            anchors.centerIn: parent
            text: root.tr("close_window", "Close test window")
            onClicked: testWindow.close()
        }
    }
}
