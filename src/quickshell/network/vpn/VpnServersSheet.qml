import QtQuick
import QtQuick.Layouts
import "../../"

// Server picker: only the servers of the active subscription, grouped by the country the
// backend found for them (flag only when that country is known; "Unknown" otherwise).
// Delay is shown only after it was measured. Choosing a server switches to it during
// an active connection. The IP/location nodes update after the new exit IP is read.
VpnSheet {
    id: sh
    title: tr("picker.title", "Choose a server")
    icon: "󰒋"
    property var expanded: ({})

    function tr(key, en) { return I18n.t("vpn." + key, en); }
    function delayText(d) {
        if (d === undefined) return VpnService.pinging ? "…" : "";
        if (d <= 0) return tr("timeout", "timeout");
        return d + " " + tr("ms", "ms");
    }
    function delayColor(d) {
        if (d === undefined || d <= 0) return Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.45);
        if (d < 150) return ThemeBackend.green;
        if (d < 400) return ThemeBackend.yellow;
        return ThemeBackend.peach;
    }
    function toggle(code) {
        let ex = Object.assign({}, expanded);
        ex[code] = !ex[code];
        expanded = ex;
    }
    onOpenChanged: {
        if (open) {
            let ex = {};
            let cur = VpnService.currentServer;
            if (cur) ex[cur.country || ""] = true;
            if (VpnService.countries.length === 1) ex[VpnService.countries[0].code] = true;
            expanded = ex;
        }
    }

    headerExtra: [
        VpnIconButton {
            icon: "󰓅"
            tip: sh.tr("ping", "Measure ping")
            spinning: VpnService.pinging
            enabled: !VpnService.pinging && VpnService.servers.length > 0
            onClicked: VpnService.ping()
        }
    ]

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        spacing: Scaler.s(4)
        boundsBehavior: Flickable.StopAtBounds
        model: sh.open || sh.visible ? VpnService.countries : []

        delegate: Column {
            id: country
            required property var modelData
            readonly property bool isOpen: sh.expanded[modelData.code] === true
            readonly property bool hasCurrent: modelData.servers.some(s => s.tag === VpnService.current)
            width: ListView.view.width
            spacing: Scaler.s(2)

            Rectangle {
                width: parent.width
                height: Scaler.s(40)
                radius: Scaler.s(10)
                color: Qt.alpha(VpnAppearance.style.text || "#ffffff", cMouse.containsMouse ? 0.10 : 0.05)
                border.width: country.hasCurrent ? 1 : 0
                border.color: Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.45)
                Behavior on color { ColorAnimation { duration: 140 } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Scaler.s(12)
                    anchors.rightMargin: Scaler.s(12)
                    spacing: Scaler.s(8)
                    Text {
                        text: country.modelData.code !== "" && country.modelData.flag ? country.modelData.flag : "󰇧"
                        font.family: country.modelData.code !== "" && country.modelData.flag ? ThemeBackend.fontFamily : ThemeBackend.iconFont
                        font.pixelSize: Scaler.s(17)
                        color: VpnAppearance.style.text || "#eef1f6"
                    }
                    Text {
                        Layout.fillWidth: true
                        text: country.modelData.code === "" ? sh.tr("unknown_country", "Unknown") : country.modelData.name
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: Scaler.s(12)
                        color: VpnAppearance.style.text || "#eef1f6"
                    }
                    Text {
                        visible: country.hasCurrent
                        text: VpnService.connected ? sh.tr("picker.connected", "connected") : sh.tr("picker.selected", "selected")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: VpnService.connected ? (VpnAppearance.style.active || "#7fd4ff") : Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.6)
                    }
                    Text {
                        text: sh.tr("picker.count", "{count} servers").replace("{count}", country.modelData.servers.length)
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.5)
                    }
                    Text {
                        Layout.preferredWidth: Scaler.s(60)
                        horizontalAlignment: Text.AlignRight
                        text: country.modelData.best > 0 ? country.modelData.best + " " + sh.tr("ms", "ms") : (VpnService.pinging ? "…" : "")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(11)
                        color: sh.delayColor(country.modelData.best > 0 ? country.modelData.best : undefined)
                    }
                    Text {
                        text: "󰅀"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: Scaler.s(12)
                        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.55)
                        rotation: country.isOpen ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                }
                MouseArea {
                    id: cMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sh.toggle(country.modelData.code)
                }
                Accessible.role: Accessible.Button
                Accessible.name: country.modelData.name
            }

            Repeater {
                model: country.isOpen ? country.modelData.servers : []
                delegate: Rectangle {
                    id: srv
                    required property var modelData
                    readonly property bool isCurrent: VpnService.current === modelData.tag
                    readonly property var delay: VpnService.delays[modelData.tag]
                    width: country.width
                    height: Scaler.s(36)
                    radius: Scaler.s(8)
                    color: isCurrent ? Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.16)
                        : (sMouse.containsMouse ? Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.07) : "transparent")
                    Behavior on color { ColorAnimation { duration: 140 } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Scaler.s(22)
                        anchors.rightMargin: Scaler.s(12)
                        spacing: Scaler.s(8)
                        Rectangle {
                            Layout.preferredWidth: Scaler.s(8); Layout.preferredHeight: Scaler.s(8); radius: Scaler.s(4)
                            color: srv.isCurrent ? (VpnService.connected ? ThemeBackend.green : (VpnAppearance.style.active || "#7fd4ff")) : "transparent"
                            border.width: 1
                            border.color: srv.isCurrent ? "transparent" : Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.4)
                        }
                        Text {
                            Layout.fillWidth: true
                            text: srv.modelData.name
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(12)
                            color: VpnAppearance.style.text || "#eef1f6"
                        }
                        Text {
                            text: String(srv.modelData.protocol || "").toUpperCase()
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(9)
                            font.letterSpacing: 1
                            color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.5)
                        }
                        Text {
                            Layout.preferredWidth: Scaler.s(60)
                            horizontalAlignment: Text.AlignRight
                            text: sh.delayText(srv.delay)
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(11)
                            color: sh.delayColor(srv.delay)
                        }
                    }
                    MouseArea {
                        id: sMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !VpnService.busy && !VpnService.sbInstalling && !VpnService.setupNeeded
                        onClicked: {
                            VpnService.select(srv.modelData.tag);
                            sh.closeRequested();
                        }
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: srv.modelData.name
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        width: parent.width * 0.8
        visible: VpnService.servers.length === 0
        text: VpnService.hasSource ? sh.tr("no_servers_yet", "No servers yet. Press Update.") : sh.tr("hint.add", "Add a VPN subscription to start.")
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        font.family: ThemeBackend.fontFamily
        font.pixelSize: Scaler.s(12)
        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.6)
    }
}
