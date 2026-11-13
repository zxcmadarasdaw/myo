import QtQuick
import "../../"
import "../../reusables"

// Generic "pick one of N" setting: a pill that cycles through the options
// (click: next, right click: previous, wheel: either way).
// settingData: { property: "material", name: "Material",
//                options: [{ id: "glass", label: "Glass" }, ...],
//                optionsSource: "netInterfaces" | "monoFonts" }   // optional live list
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

    readonly property var options: {
        let sd = settingRoot.settingData;
        if (sd && sd.optionsSource === "netInterfaces") {
            let list = [{ id: "auto", label: I18n.t("widgets.network.auto", "Auto") }];
            for (let n of NetStats.interfaceNames()) list.push({ id: n, label: n });
            return list;
        }
        if (sd && sd.optionsSource === "monoFonts") {
            // installed monospace families (fixed-pitch names), "monospace" first
            let list = [{ id: "monospace", label: "monospace" }];
            let seen = { "monospace": true };
            for (let f of Qt.fontFamilies()) {
                if (seen[f] || !/mono|code|courier|hack|iosevka|consol|terminus|fixed/i.test(f)) continue;
                seen[f] = true;
                list.push({ id: f, label: f });
            }
            return list;
        }
        return (sd && Array.isArray(sd.options)) ? sd.options : [];
    }

    readonly property var currentValue: {
        let w = settingRoot.targetWidget;
        if (!w || propName === "") return undefined;
        try { return w[propName]; } catch (e) { return undefined; }
    }

    readonly property int currentIndex: {
        for (let i = 0; i < options.length; i++) if (options[i].id === currentValue) return i;
        return 0;
    }

    readonly property string currentLabel: options.length > 0 ? (options[currentIndex].label || options[currentIndex].id) : "-"

    function choose(step) {
        if (options.length === 0) return;
        let next = options[(currentIndex + step + options.length) % options.length].id;
        let w = settingRoot.targetWidget;
        try { if (w && w[propName] !== undefined) w[propName] = next; } catch (e) {}
        if (settingRoot.redactor && propName !== "") settingRoot.redactor.setWidgetProperty(propName, next);
    }

    // The interface list is live only while someone samples it.
    readonly property string token: "choice-setting-" + Math.random().toString(36).slice(2)
    Component.onCompleted: if (settingData && settingData.optionsSource === "netInterfaces") NetStats.register(token, 2000, false, "")
    Component.onDestruction: NetStats.unregister(token)

    implicitWidth: row.implicitWidth + Scaler.s(24)
    implicitHeight: Scaler.s(34)

    Rectangle {
        anchors.fill: parent
        radius: ThemeBackend.borderRadius
        color: glass.active ? "transparent" : (area.containsMouse ? ThemeBackend.surface1 : ThemeBackend.surface0)
        Behavior on color { ColorAnimation { duration: 150 } }
        GlassFill {
            id: glass
            anchors.fill: parent
            radius: parent.radius
            tintColor: ThemeBackend.surface0
            tintAmount: area.containsMouse ? 0.45 : 0.3
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Scaler.s(6)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: settingRoot.settingData && settingRoot.settingData.name ? settingRoot.settingData.name : settingRoot.propName
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(11)
            color: ThemeBackend.subtext0
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: settingRoot.currentLabel
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(11)
            font.bold: true
            color: ThemeBackend.mauve
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅂"
            font.family: ThemeBackend.iconFont
            font.pixelSize: Scaler.s(12)
            color: ThemeBackend.subtext0
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => settingRoot.choose(mouse.button === Qt.RightButton ? -1 : 1)
        onWheel: wheel => settingRoot.choose(wheel.angleDelta.y > 0 ? -1 : 1)
    }
}
