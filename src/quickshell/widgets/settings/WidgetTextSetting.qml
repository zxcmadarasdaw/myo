import QtQuick
import "../../"
import "../../reusables"

// Generic text setting, saved when the user presses Enter (or leaves the
// field), never on every keystroke.
// settingData: { property: "startCommand", name: "Command", placeholder: "...",
//                trustCommand: true }
// trustCommand: the text is a command the user typed here, on this machine;
// it is recorded in TerminalTrust so the terminal may run it. Commands that
// arrive any other way (imported themes, presets, hand-edited layouts) are
// not in that list and the terminal asks before running them.
Item {
    id: settingRoot
    property var typeData: null
    property var settingData: null
    property var redactor: null
    property var widget: null
    property var widgetData: null
    property var item: null

    readonly property var targetWidget: settingRoot.widget || settingRoot.widgetData || settingRoot.item || null
    readonly property string propName: settingData && settingData.property ? settingData.property : ""

    function syncValue() {
        let w = settingRoot.targetWidget;
        if (!w || input.hasFocus || propName === "") return;
        let cur = (w[propName] !== undefined && w[propName] !== null) ? String(w[propName]) : "";
        if (input.text !== cur) input.text = cur;
    }

    function commit(text) {
        let val = String(text === undefined ? input.text : text);
        if (settingData && settingData.trustCommand && val.trim() !== "") TerminalTrust.approve(val);
        let w = settingRoot.targetWidget;
        try { if (w && w[propName] !== undefined) w[propName] = val; } catch (e) {}
        if (settingRoot.redactor && propName !== "") settingRoot.redactor.setWidgetProperty(propName, val);
    }

    Component.onCompleted: syncValue()
    onTargetWidgetChanged: syncValue()

    implicitWidth: Scaler.s(settingData && settingData.width ? settingData.width : 240)
    implicitHeight: Scaler.s(34)

    Input {
        id: input
        anchors.fill: parent
        placeholderText: settingRoot.settingData && settingRoot.settingData.placeholder ? settingRoot.settingData.placeholder : (settingRoot.settingData && settingRoot.settingData.name ? settingRoot.settingData.name : "")
        fontPixelSize: Scaler.s(12)
        baseColor: ThemeBackend.surface0
        accentColor: ThemeBackend.mauve
        textColor: ThemeBackend.text
        subTextColor: ThemeBackend.subtext0
        borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
        cornerRadius: ThemeBackend.borderRadius
        horizontalPadding: Scaler.s(10)
        onAccepted: function(finalText) { settingRoot.commit(finalText); }
        onHasFocusChanged: if (!hasFocus) {
            let w = settingRoot.targetWidget;
            let cur = (w && w[settingRoot.propName] !== undefined && w[settingRoot.propName] !== null) ? String(w[settingRoot.propName]) : "";
            if (input.text !== cur) settingRoot.commit(input.text);
        }
    }
}
