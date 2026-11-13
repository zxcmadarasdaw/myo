import QtQuick
import "../../"
import "../../reusables"

// Generic numeric setting.
// settingData: { property: "updateInterval", name: "Refresh, s",
//                from: 0.5, to: 10, stepSize: 0.5, decimals: 1, scale: 1000 }
// `scale` converts the shown value to the stored one (seconds -> ms).
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
    readonly property real valueScale: settingData && settingData.scale ? settingData.scale : 1

    function shownValue() {
        let w = settingRoot.targetWidget;
        let v = (w && propName !== "" && w[propName] !== undefined) ? Number(w[propName]) : NaN;
        let from = settingData && settingData.from !== undefined ? settingData.from : 0;
        // unset / "follow the theme" values (e.g. -1) show the fallback
        if (isNaN(v) || v / valueScale < from) {
            return settingData && settingData.fallback !== undefined ? settingData.fallback : from;
        }
        return v / valueScale;
    }

    function syncValue() {
        let v = shownValue();
        if (Math.abs(selector.value - v) > 1e-6) selector.setValue(v);
    }

    Component.onCompleted: syncValue()
    onTargetWidgetChanged: syncValue()

    implicitWidth: row.implicitWidth + Scaler.s(12)
    implicitHeight: Scaler.s(34)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Scaler.s(8)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: settingRoot.settingData && settingRoot.settingData.name ? settingRoot.settingData.name : settingRoot.propName
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(11)
            font.bold: true
            color: ThemeBackend.text
        }

        NumberSelector {
            id: selector
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Scaler.s(120)
            implicitHeight: Scaler.s(32)
            from: settingRoot.settingData && settingRoot.settingData.from !== undefined ? settingRoot.settingData.from : 0
            to: settingRoot.settingData && settingRoot.settingData.to !== undefined ? settingRoot.settingData.to : 100
            stepSize: settingRoot.settingData && settingRoot.settingData.stepSize !== undefined ? settingRoot.settingData.stepSize : 1
            decimals: settingRoot.settingData && settingRoot.settingData.decimals !== undefined ? settingRoot.settingData.decimals : 0
            value: settingRoot.shownValue()
            fontFamily: ThemeBackend.fontFamily
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface0
            buttonColor: ThemeBackend.surface1
            textColor: ThemeBackend.text
            buttonTextColor: ThemeBackend.subtext1
            cornerRadius: ThemeBackend.borderRadius

            onTriggered: {
                let stored = selector.value * settingRoot.valueScale;
                if (settingRoot.valueScale !== 1) stored = Math.round(stored);
                let w = settingRoot.targetWidget;
                try { if (w && w[settingRoot.propName] !== undefined) w[settingRoot.propName] = stored; } catch (e) {}
                if (settingRoot.redactor && settingRoot.propName !== "") settingRoot.redactor.setWidgetProperty(settingRoot.propName, stored);
            }
        }
    }
}
