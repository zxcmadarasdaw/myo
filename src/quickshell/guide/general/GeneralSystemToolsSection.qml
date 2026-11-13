import QtQuick
import "../../"
import "../../reusables"
import "../../reusables/guide"

// System tools: Process Explorer (hotkey, material, refresh interval).
// Values live in settings.json under "processExplorer"; see
// singletons/widgetcontrols/ProcessExplorerController.qml.
SettingsBlob {
    id: section
    required property var tab
    readonly property var rootObj: tab.rootObj

    SettingsRow {
        rootObj: section.tab.rootObj
        icon: "󰍛"
        title: I18n.t("guide.general.processes.hotkey.title", "Process Explorer hotkey")
        description: I18n.t("guide.general.processes.hotkey.desc", "Opens and closes the Process Explorer (Hyprland). Example: SUPER + SHIFT + P")

        Row {
            spacing: section.rootObj.s(8)

            Input {
                id: hotkeyInput
                width: section.rootObj.s(180)
                height: section.rootObj.s(32)
                text: ProcessExplorerController.hotkey
                placeholderText: ProcessExplorerController.defaultHotkey
                fontPixelSize: section.rootObj.s(12)
                cornerRadius: ThemeBackend.borderRadius
                hasError: text.trim() !== "" && !ProcessExplorerController.validHotkey(text)
                onAccepted: function(t) { hotkeyApply.apply(); }
            }

            ClickButton {
                id: hotkeyApply
                height: section.rootObj.s(32)
                buttonText: I18n.t("guide.general.processes.hotkey.apply", "Apply")
                textFontSize: section.rootObj.s(11)
                cornerRadius: ThemeBackend.borderRadius
                accentColor: ThemeBackend.mauve
                textColor: ThemeBackend.crust
                function apply() {
                    let t = hotkeyInput.text.trim();
                    if (t === "") t = ProcessExplorerController.defaultHotkey;
                    if (!ProcessExplorerController.validHotkey(t)) { hotkeyInput.triggerShake(); return; }
                    ProcessExplorerController.setSetting("hotkey", ProcessExplorerController.normalizeHotkey(t));
                }
                onClicked: apply()
            }
        }
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        icon: "󰂵"
        title: I18n.t("guide.general.processes.material.title", "Process Explorer material")
        description: I18n.t("guide.general.processes.material.desc", "Background of the panel")

        Row {
            spacing: section.rootObj.s(6)
            Repeater {
                model: [
                    { id: "standard", label: I18n.t("guide.general.processes.material.standard", "Standard") },
                    { id: "liquid", label: I18n.t("guide.general.processes.material.liquid", "Liquid Glass") },
                    { id: "mica", label: I18n.t("guide.general.processes.material.mica", "Mica") },
                    { id: "neon", label: I18n.t("guide.general.processes.material.neon", "Neon Glass") }
                ]
                ClickButton {
                    required property var modelData
                    height: section.rootObj.s(32)
                    buttonText: modelData.label
                    textFontSize: section.rootObj.s(11)
                    cornerRadius: ThemeBackend.borderRadius
                    readonly property bool active: ProcessExplorerController.material === modelData.id
                    accentColor: active ? ThemeBackend.mauve : ThemeBackend.surface1
                    textColor: active ? ThemeBackend.crust : ThemeBackend.text
                    onClicked: ProcessExplorerController.setSetting("material", modelData.id)
                }
            }
        }
    }

    SettingsRow {
        rootObj: section.tab.rootObj
        icon: "󰑐"
        title: I18n.t("guide.general.processes.interval.title", "Process Explorer refresh (seconds)")
        description: I18n.t("guide.general.processes.interval.desc", "How often the list is sampled while the panel is open")

        NumberSelector {
            implicitWidth: section.rootObj.s(140)
            implicitHeight: section.rootObj.s(32)
            from: 0.5
            to: 10
            stepSize: 0.5
            decimals: 1
            value: ProcessExplorerController.interval
            baseColor: ThemeBackend.surface0
            accentColor: ThemeBackend.mauve
            buttonColor: ThemeBackend.surface1
            buttonTextColor: ThemeBackend.text
            textColor: ThemeBackend.text
            subTextColor: ThemeBackend.subtext0
            borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
            cornerRadius: ThemeBackend.borderRadius
            fontFamily: ThemeBackend.fontFamily
            fontPixelSize: section.rootObj.s(12)
            onValueChanged: {
                let v = Math.round(value * 2) / 2;
                if (Math.abs(v - ProcessExplorerController.interval) > 0.01) ProcessExplorerController.setSetting("interval", v);
            }
        }
    }
}
