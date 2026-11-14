import QtQuick
import "../../"
import "../../reusables"
import "../../reusables/guide"

SettingsBlob {
    id: section
    required property var tab
    readonly property var rootObj: tab.rootObj
    visible: WindowActionsController.onHyprland

    SettingsRow {
        rootObj: section.rootObj
        icon: "󰐃"
        title: I18n.t("guide.windows.pin.title", "Pinned windows — Super+Z")
        description: I18n.t("guide.windows.pin.desc", "Pin the active window across workspaces; press again to return it to tiling. Super+Shift+Z minimizes; Super+Ctrl+Z restores.")
        Row {
            spacing: section.rootObj.s(4)
            Repeater {
                model: [
                    { value: "top-left", label: "↖" }, { value: "top-right", label: "↗" },
                    { value: "bottom-left", label: "↙" }, { value: "bottom-right", label: "↘" }
                ]
                ClickButton {
                    required property var modelData
                    buttonText: modelData.label
                    height: section.rootObj.s(32)
                    cornerRadius: ThemeBackend.borderRadius
                    accentColor: (WindowActionsController.settings.corner || "top-right") === modelData.value ? ThemeBackend.mauve : ThemeBackend.surface1
                    textColor: ThemeBackend.text
                    onClicked: WindowActionsController.setSetting("corner", modelData.value)
                }
            }
        }
    }

    Repeater {
        model: [
            { key: "widthFraction", title: I18n.t("guide.windows.width", "Pinned window width (%)"), initial: 32, min: 15, max: 80, factor: 100 },
            { key: "heightFraction", title: I18n.t("guide.windows.height", "Pinned window height (%)"), initial: 32, min: 15, max: 80, factor: 100 },
            { key: "margin", title: I18n.t("guide.windows.margin", "Pinned window margin (logical pixels)"), initial: 16, min: 0, max: 200, factor: 1 }
        ]
        SettingsRow {
            id: settingRow
            required property var modelData
            rootObj: section.rootObj
            icon: "󰩨"
            title: modelData.title
            description: I18n.t("guide.windows.geometry.desc", "Applied on the next pin. Leaves room for panels and desktop widgets; changes window size, not content zoom.")
            NumberSelector {
                implicitWidth: section.rootObj.s(140)
                implicitHeight: section.rootObj.s(32)
                from: settingRow.modelData.min
                to: settingRow.modelData.max
                stepSize: 1
                decimals: 0
                readonly property real configured: WindowActionsController.settings[settingRow.modelData.key] !== undefined
                    ? WindowActionsController.settings[settingRow.modelData.key] * settingRow.modelData.factor : settingRow.modelData.initial
                value: configured
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
                onValueChanged: if (Config.dataReady && Math.abs(value - configured) > .01)
                    WindowActionsController.setSetting(settingRow.modelData.key, value / settingRow.modelData.factor)
            }
        }
    }

    Text {
        width: parent.width
        visible: text !== ""
        text: WindowActionsController.lastError
        color: ThemeBackend.red
        wrapMode: Text.Wrap
        font.pixelSize: section.rootObj.s(12)
    }
}
