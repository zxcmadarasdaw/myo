import QtQuick
import "../../"
import "../../reusables"

// Generic on/off setting for the widget editor toolbar.
// settingData: { property: "showLatency", name: "Latency" }
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
    readonly property bool current: {
        let w = settingRoot.targetWidget;
        return !!(w && propName !== "" && w[propName] === true);
    }

    implicitWidth: row.implicitWidth + Scaler.s(20)
    implicitHeight: Scaler.s(34)

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        color: glass.active ? "transparent" : ThemeBackend.surface0
        GlassFill {
            id: glass
            anchors.fill: parent
            radius: parent.radius
            tintColor: ThemeBackend.surface0
            tintAmount: 0.3
        }
    }

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

        Toggle {
            anchors.verticalCenter: parent.verticalCenter
            horizontalPadding: 0
            cornerRadius: ThemeBackend.borderRadius
            checked: settingRoot.current
            accentColor: ThemeBackend.mauve
            baseColor: ThemeBackend.surface1
            handleColor: ThemeBackend.crust
            handleOffColor: ThemeBackend.text
            onToggled: function(c) {
                let w = settingRoot.targetWidget;
                try { if (w && w[settingRoot.propName] !== undefined) w[settingRoot.propName] = c; } catch (e) {}
                if (settingRoot.redactor && settingRoot.propName !== "") settingRoot.redactor.setWidgetProperty(settingRoot.propName, c);
            }
        }
    }
}
