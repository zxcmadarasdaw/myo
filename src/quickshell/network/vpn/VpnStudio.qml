import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../"
import "VpnGeometry.js" as Geo

// VPN tab of the network panel (Super+N -> VPN): one composition with a large power
// button in the middle and lines to IP ADDRESS, LOCATION, SELECT SERVER and PROTOCOL,
// "+ Add VPN subscription" at the bottom. Every value shown comes from the backend
// (serp_vpn.py through VpnService): the button says "connected" only after the backend
// confirmed it, the IP and its country only after they were read through the tunnel.
// Look: VpnAppearance (Settings -> Theme -> VPN).
Item {
    id: studio

    property bool active: false               // the tab is shown and the window is open
    property string sheet: ""                 // "" | servers | subs | conn | singbox
    readonly property var st: VpnAppearance.style
    readonly property string phase: VpnService.phase
    readonly property string vpnState: VpnService.vpnState
    readonly property bool missing: VpnService.setupNeeded && !VpnService.connected

    function s(v) { return Scaler.s(v); }
    function tr(key, en) { return I18n.t("vpn." + key, en); }

    function openSheet(name) {
        sheet = name;
        if (name === "servers") VpnService.ping();
        if (name === "subs") VpnService.loadSubs();
        if (name === "singbox" || name === "conn") VpnService.singboxInfo();
    }
    // Escape: closes the open sheet first; returns true when it handled the key.
    function back() {
        if (sheet !== "") {
            sheet = "";
            return true;
        }
        return false;
    }

    function primary() {
        if (missing) { openSheet("subs"); subsSheet.focusAdd(); return; }
        if (!VpnService.hasSource || VpnService.servers.length === 0) { openSheet("subs"); return; }
        if (phase === "connected") VpnService.disconnect();
        else if (phase === "disconnected" || phase === "error") VpnService.connect();
    }

    function timeText(t) {
        if (!t) return "";
        let d = new Date(t * 1000);
        let now = new Date();
        let same = d.toDateString() === now.toDateString();
        return Qt.formatDateTime(d, same ? "HH:mm" : "dd.MM.yyyy HH:mm");
    }
    function delayText(tag) {
        let d = VpnService.delays[tag];
        if (d === undefined) return "";
        if (d <= 0) return tr("timeout", "timeout");
        return d + " " + tr("ms", "ms");
    }

    readonly property string phaseText: {
        if (missing) return tr("setup.required", "Setup required");
        if (vpnState === "none" && phase === "disconnected") return tr("state.none", "No subscription");
        switch (phase) {
        case "connected": return tr("state.connected", "Connected");
        case "connecting": return tr("state.connecting", "Connecting…");
        case "disconnecting": return tr("state.disconnecting", "Disconnecting…");
        case "error": return tr("state.error", "Error");
        default: return tr("state.disconnected", "Disconnected");
        }
    }
    readonly property color phaseColor: phase === "connected" ? (st.active || "#7fd4ff")
        : (phase === "error" || missing) ? ThemeBackend.red
        : (phase === "connecting" || phase === "disconnecting") ? Qt.alpha(st.active || "#7fd4ff", 0.8)
        : (st.inactive || "#5c6370")

    readonly property string problemText: VpnService.error !== "" ? VpnService.error : (VpnService.status.error || "")
    readonly property var firstWarning: VpnService.checks.find(c => c.level === "warn") || null
    readonly property bool showForceOff: VpnService.canForceOff || VpnService.forcing
        || (VpnService.mode === "tun" && (vpnState === "error" || (VpnService.busy && VpnService.busyAction === "disconnect")))
    readonly property var message: {
        if (VpnService.forcing) return { text: tr("busy.force", "Turning the VPN off…"), level: "busy" };
        if (VpnService.busy) {
            switch (VpnService.busyAction) {
            case "set-source": case "update": case "sub-add": case "sub-use":
                return { text: tr("busy.update", "Downloading and checking the subscription…"), level: "busy" };
            case "mode": return { text: tr("busy.mode", "Switching mode…"), level: "busy" };
            case "connect": case "select": return { text: tr("busy.connect", "Connecting…"), level: "busy" };
            case "disconnect": return { text: tr("busy.disconnect", "Disconnecting…"), level: "busy" };
            default: return { text: "…", level: "busy" };
            }
        }
        if (problemText !== "") return { text: problemText, level: "error" };
        if (firstWarning) return { text: firstWarning.message, level: "warn" };
        if (phase === "connected" && VpnService.mode === "tun") return { text: tr("tun_on", "All traffic of this computer goes through the VPN"), level: "info" };
        if (phase === "connected") return { text: tr("proxy_at", "HTTP/SOCKS5 proxy") + "  " + VpnService.proxy, level: "info" };
        if (missing) return { text: tr("setup.hint", "Open setup and enter your VPN link."), level: "info" };
        if (vpnState === "none") return { text: tr("hint.add", "Add a VPN subscription to start."), level: "info" };
        if (VpnService.warning !== "") return { text: VpnService.warning, level: "warn" };
        return { text: "", level: "info" };
    }

    // ---- node contents (real data only) -------------------------------------------------
    function nodeInfo(id) {
        let cur = VpnService.currentServer;
        let on = phase === "connected";
        let ip = VpnService.exitIp;
        switch (id) {
        case "ip": {
            let r = { icon: "󰩟", caption: tr("node.ip", "IP ADDRESS"), value: "—", sub: "", flag: "", lit: on && ip !== null, warn: false };
            if (!on) { r.sub = tr("ip.after", "Checked after connecting"); return r; }
            if (VpnService.ipState === "checking" || VpnService.ipState === "" || !ip) { r.value = "…"; r.sub = tr("ip.checking", "Checking through the VPN…"); return r; }
            if (VpnService.ipState === "failed") { r.sub = tr("ip.failed", "Could not check · click to retry"); r.warn = true; return r; }
            r.value = ip.ip;
            r.sub = tr("ip.verified", "Verified at {time}").replace("{time}", timeText(ip.time));
            return r;
        }
        case "location": {
            let r = { icon: "󰍎", caption: tr("node.location", "LOCATION"), value: tr("unknown_country", "Unknown"), sub: "", flag: "", lit: false, warn: false };
            if (on && ip && ip.country) {
                r.value = ip.countryName || ip.country;
                r.flag = ip.flag || "";
                r.lit = true;
                r.sub = (cur && cur.country && cur.country !== ip.country)
                    ? tr("loc.differs", "Exit IP country differs from the server name") : tr("loc.verified", "By the exit IP");
                r.warn = cur && cur.country && cur.country !== ip.country;
                return r;
            }
            if (cur && cur.country) {
                r.value = cur.countryName || cur.country;
                r.flag = cur.flag || "";
                r.sub = tr("loc.declared", "From the server name · not verified");
            } else if (cur) {
                r.sub = tr("loc.none", "The server does not say its country");
            }
            return r;
        }
        case "server": {
            let r = { icon: "󰒋", caption: tr("node.server", "SELECT SERVER"), value: tr("choose", "Choose a server"), sub: "", flag: "", lit: on, warn: false };
            if (cur) {
                r.value = cur.name;
                let d = delayText(cur.tag);
                r.sub = d !== "" ? d : tr("servers_count", "Servers: {count}").replace("{count}", VpnService.servers.length);
            } else if (VpnService.servers.length === 0) {
                r.value = tr("no_servers", "No servers");
                r.sub = VpnService.hasSource ? tr("no_servers_yet", "No servers yet. Press Update.") : tr("hint.add", "Add a VPN subscription to start.");
            }
            return r;
        }
        default: {
            let tun = VpnService.mode === "tun";
            return { icon: "󰒃", caption: tr("node.protocol", "PROTOCOL"),
                     value: cur && cur.protocol ? String(cur.protocol).toUpperCase() : "—",
                     sub: tun ? tr("mode.tun", "TUN · whole system") : tr("mode.proxy", "Proxy") + " · " + VpnService.proxy,
                     flag: "", lit: on, warn: false };
        }
        }
    }
    function nodeClicked(id) {
        if (id === "ip") {
            if (phase === "connected") VpnService.checkIp();
        } else if (id === "server" || id === "location") {
            openSheet(VpnService.servers.length > 0 ? "servers" : "subs");
        } else {
            openSheet("conn");
        }
    }

    // ---- intro: lines draw in when the tab appears --------------------------------------
    property real intro: 1.0
    NumberAnimation on intro { id: introAnim; running: false; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }
    onActiveChanged: {
        if (active) {
            if (VpnService.sbSetup && VpnService.sbInstalling) sheet = "subs";
            if (st.animate !== false) introAnim.restart();
            else intro = 1;
        } else {
            introAnim.stop();
            intro = 1;
            sheet = "";
        }
    }

    // ---- background ------------------------------------------------------------------------
    VpnMaterial { anchors.fill: parent }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: studio.s(14)
        spacing: studio.s(6)

        // header: state + quick actions
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false               // nested layouts fill by default
            Layout.preferredHeight: studio.s(30)
            spacing: studio.s(8)
            Text {
                text: "VPN"
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Black
                font.pixelSize: studio.s(14)
                font.letterSpacing: VpnAppearance.letterSpacing
                color: studio.st.text
            }
            Rectangle {
                Layout.preferredWidth: studio.s(7); Layout.preferredHeight: studio.s(7); radius: studio.s(4)
                color: studio.phaseColor
                Behavior on color { ColorAnimation { duration: 300 } }
            }
            Text {
                Layout.fillWidth: true
                text: studio.phaseText + (VpnService.mode === "tun" ? "  ·  TUN" : "")
                    + (VpnService.subscriptionName !== "" ? "  ·  " + VpnService.subscriptionName : "")
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.weight: VpnAppearance.fontWeight
                font.pixelSize: studio.s(12)
                color: studio.phaseColor
            }
            VpnIconButton {
                icon: "󰑓"
                tip: studio.tr("update", "Update")
                enabled: !VpnService.busy && VpnService.hasSource
                spinning: VpnService.busy && (VpnService.busyAction === "update" || VpnService.busyAction === "set-source")
                onClicked: VpnService.update()
            }
            VpnIconButton {
                icon: "󰒓"
                tip: studio.tr("conn.title", "Connection")
                onClicked: studio.openSheet("conn")
            }
            VpnIconButton {
                icon: "󰏘"
                tip: studio.tr("appearance", "VPN appearance")
                onClicked: Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "open", "settings", "Theme:ThemeVpn"])
            }
        }

        // composition
        Item {
            id: stage
            Layout.fillWidth: true
            Layout.fillHeight: true
            readonly property var lay: width > 10 && height > 10
                ? Geo.layout(studio.st.layout || "auto", width, height, studio.s(1)) : null

            VpnLinks {
                anchors.fill: parent
                lay: stage.lay
                style: studio.st
                phase: studio.phase
                active: studio.active
                intro: studio.intro
                unit: studio.s(1)
            }

            // power button
            Item {
                id: power
                objectName: "vpnPower"
                readonly property real d: stage.lay ? stage.lay.button.d : studio.s(140)
                readonly property string shape: studio.st.buttonShape || "circle"
                width: shape === "pill" ? d * 1.3 : d
                height: shape === "pill" ? d * 0.72 : d
                x: stage.lay ? stage.lay.button.cx - width / 2 : 0
                y: stage.lay ? stage.lay.button.cy - height / 2 : 0
                readonly property real rad: shape === "circle" ? width / 2 : shape === "pill" ? height / 2 : d * 0.3
                readonly property bool on: studio.phase === "connected"
                readonly property bool working: studio.phase === "connecting" || studio.phase === "disconnecting"
                readonly property bool usable: !VpnService.busy && !VpnService.sbInstalling && !VpnService.forcing && !working
                property real litLevel: on ? 1 : 0
                Behavior on litLevel { NumberAnimation { duration: power.on ? 450 : 700; easing.type: Easing.OutCubic } }
                scale: (powerMouse.pressed ? 0.96 : (powerMouse.containsMouse ? 1.03 : 1.0)) * (0.92 + 0.08 * studio.intro)
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                activeFocusOnTab: true

                // glow while connected
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        anchors.centerIn: parent
                        width: power.width + (index + 1) * studio.s(14)
                        height: power.height + (index + 1) * studio.s(14)
                        radius: power.rad + (index + 1) * studio.s(7)
                        color: Qt.alpha(studio.st.glowColor || "#7fd4ff", (0.09 - index * 0.025) * (studio.st.glow || 0) * power.litLevel * 2)
                        visible: power.litLevel > 0.01 && (studio.st.glow || 0) > 0.01
                    }
                }
                // pulse while connecting
                Rectangle {
                    id: pulseRing
                    anchors.centerIn: parent
                    width: power.width
                    height: power.height
                    radius: power.rad
                    color: "transparent"
                    border.width: studio.s(2)
                    border.color: studio.st.active || "#7fd4ff"
                    property real k: 0
                    scale: 1 + 0.35 * k
                    opacity: (1 - k) * 0.7
                    visible: pulseAnim.running
                    NumberAnimation on k {
                        id: pulseAnim
                        running: power.working && studio.active && studio.st.animate !== false
                        from: 0; to: 1; duration: 1300 / Math.max(0.25, studio.st.animSpeed || 1)
                        loops: Animation.Infinite
                    }
                }
                // body
                Rectangle {
                    id: body
                    anchors.fill: parent
                    radius: power.rad
                    color: power.on ? Qt.alpha(studio.st.button || "#e8ecf4", 0.95) : Qt.alpha(studio.st.button || "#e8ecf4", 0.07)
                    Behavior on color { ColorAnimation { duration: 450; easing.type: Easing.OutCubic } }
                    border.width: studio.s(2)
                    border.color: studio.phase === "error" || studio.missing ? Qt.alpha(ThemeBackend.red, 0.8)
                        : power.on ? Qt.alpha(studio.st.active || "#7fd4ff", 0.9)
                        : Qt.alpha(studio.st.button || "#e8ecf4", power.working ? 0.35 : 0.28)
                    Behavior on border.color { ColorAnimation { duration: 300 } }
                    Rectangle {                       // inner ring
                        anchors.fill: parent
                        anchors.margins: studio.s(7)
                        radius: Math.max(0, power.rad - studio.s(7))
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(power.on ? (studio.st.background || "#000000") : (studio.st.button || "#ffffff"), 0.12)
                    }
                }
                // orbiting dot while working
                Item {
                    anchors.fill: parent
                    visible: power.working
                    rotation: orbit.angle
                    Rectangle {
                        width: studio.s(8); height: width; radius: width / 2
                        x: parent.width / 2 - width / 2
                        y: -height / 2 + studio.s(1)
                        color: studio.st.active || "#7fd4ff"
                    }
                    QtObject { id: orbit; property real angle: 0 }
                    NumberAnimation {
                        target: orbit; property: "angle"; from: 0; to: 360
                        duration: 1100; loops: Animation.Infinite
                        running: power.working && studio.active
                    }
                }
                Column {
                    anchors.centerIn: parent
                    spacing: studio.s(4)
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: studio.missing ? "󰏗" : "󰐥"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: Math.round(power.height * 0.30)
                        color: power.on ? (studio.st.background || "#0b0d12")
                            : (studio.phase === "error" || studio.missing) ? ThemeBackend.red : (studio.st.text || "#eef1f6")
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, power.width * 0.8)
                        horizontalAlignment: Text.AlignHCenter
                        elide: studio.missing ? Text.ElideNone : Text.ElideRight
                        wrapMode: studio.missing ? Text.WordWrap : Text.NoWrap
                        text: studio.missing ? studio.tr("setup.required", "Setup required")
                            : (!VpnService.hasSource ? studio.tr("btn.add", "Add")
                            : power.on ? studio.tr("btn.on", "ON")
                            : studio.phase === "connecting" ? studio.tr("btn.connecting", "…")
                            : studio.phase === "disconnecting" ? studio.tr("btn.disconnecting", "…")
                            : studio.tr("btn.off", "OFF"))
                        font.family: ThemeBackend.fontFamily
                        font.weight: VpnAppearance.fontWeight
                        font.pixelSize: Math.max(studio.s(10), Math.round(power.height * 0.085))
                        font.letterSpacing: VpnAppearance.letterSpacing
                        color: power.on ? (studio.st.background || "#0b0d12") : (studio.st.text || "#eef1f6")
                    }
                }
                Rectangle {                           // keyboard focus ring
                    anchors.fill: parent
                    anchors.margins: -studio.s(5)
                    radius: power.rad + studio.s(5)
                    color: "transparent"
                    border.width: 1.5
                    border.color: Qt.alpha(studio.st.active || "#7fd4ff", 0.8)
                    visible: power.activeFocus
                }
                MouseArea {
                    id: powerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: power.usable
                    cursorShape: Qt.PointingHandCursor
                    onClicked: studio.primary()
                }
                Keys.onSpacePressed: if (power.usable) studio.primary()
                Keys.onReturnPressed: if (power.usable) studio.primary()
                Accessible.role: Accessible.Button
                Accessible.name: studio.phase === "connected" ? studio.tr("disconnect", "Disconnect") : studio.tr("connect", "Connect")
            }

            // nodes
            Repeater {
                model: Geo.NODE_IDS
                delegate: Rectangle {
                    id: node
                    required property string modelData
                    required property int index
                    readonly property var n: stage.lay ? stage.lay.nodes[modelData] : null
                    readonly property var info: studio.nodeInfo(modelData)
                    readonly property real appear: Math.max(0, Math.min(1, studio.intro * 1.6 - 0.25 - index * 0.1))
                    x: n ? n.x : 0
                    y: n ? n.y + (1 - appear) * studio.s(8) : 0
                    width: stage.lay ? stage.lay.nodeW : 0
                    height: stage.lay ? stage.lay.nodeH : 0
                    opacity: appear
                    radius: Math.min(height / 2, (studio.st.radius || 20) * 0.55)
                    color: Qt.alpha(studio.st.background || "#0b0d12", studio.st.material === "minimal" ? 0.35 : 0.72)
                    border.width: 1
                    border.color: info.warn ? Qt.alpha(ThemeBackend.yellow, 0.6)
                        : info.lit ? Qt.alpha(studio.st.active || "#7fd4ff", 0.55)
                        : Qt.alpha(studio.st.border || "#ffffff", nodeMouse.containsMouse ? 0.28 : 0.12)
                    Behavior on border.color { ColorAnimation { duration: 350 } }
                    activeFocusOnTab: true

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: studio.s(10)
                        anchors.rightMargin: studio.s(10)
                        spacing: studio.s(8)
                        Text {
                            text: node.info.flag !== "" ? node.info.flag : node.info.icon
                            font.family: node.info.flag !== "" ? ThemeBackend.fontFamily : ThemeBackend.iconFont
                            font.pixelSize: studio.s(node.info.flag !== "" ? 18 : 16)
                            color: node.info.lit ? (studio.st.active || "#7fd4ff") : Qt.alpha(studio.st.text || "#eef1f6", 0.7)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: node.info.caption
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: studio.s(9)
                                font.letterSpacing: VpnAppearance.letterSpacing * 0.6
                                color: Qt.alpha(studio.st.text || "#eef1f6", 0.55)
                            }
                            Text {
                                Layout.fillWidth: true
                                text: node.info.value
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily
                                font.weight: VpnAppearance.fontWeight === Font.Light ? Font.Normal : Font.Bold
                                font.pixelSize: studio.s(13)
                                color: studio.st.text || "#eef1f6"
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== "" && node.height > studio.s(52)
                                text: node.info.sub
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: studio.s(9)
                                color: node.info.warn ? ThemeBackend.yellow : Qt.alpha(studio.st.text || "#eef1f6", 0.5)
                            }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: node.radius + 3
                        color: "transparent"
                        border.width: 1.5
                        border.color: Qt.alpha(studio.st.active || "#7fd4ff", 0.8)
                        visible: node.activeFocus
                    }
                    MouseArea {
                        id: nodeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: studio.nodeClicked(node.modelData)
                    }
                    Keys.onReturnPressed: studio.nodeClicked(node.modelData)
                    Keys.onSpacePressed: studio.nodeClicked(node.modelData)
                    Accessible.role: Accessible.Button
                    Accessible.name: info.caption + ": " + info.value
                }
            }
        }

        // status / error line
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false               // nested layouts fill by default
            Layout.preferredHeight: studio.s(26)
            spacing: studio.s(8)
            visible: studio.message.text !== "" || studio.showForceOff
            Text {
                text: studio.message.level === "error" ? "󰅚" : studio.message.level === "warn" ? "󰀦" : "󰋽"
                visible: studio.message.level !== "busy" && studio.message.text !== ""
                font.family: ThemeBackend.iconFont
                font.pixelSize: studio.s(13)
                color: studio.message.level === "error" ? ThemeBackend.red
                    : studio.message.level === "warn" ? ThemeBackend.yellow : Qt.alpha(studio.st.text || "#eef1f6", 0.55)
            }
            VpnSpinner {
                visible: studio.message.level === "busy"
                running: visible
                size: studio.s(12)
                color: studio.st.active || "#7fd4ff"
            }
            Text {
                id: messageText
                Layout.fillWidth: true
                text: studio.message.text
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: ThemeBackend.fontFamily
                font.pixelSize: studio.s(11)
                color: studio.message.level === "error" ? ThemeBackend.red
                    : studio.message.level === "warn" ? ThemeBackend.yellow : Qt.alpha(studio.st.text || "#eef1f6", 0.7)
                MouseArea {
                    anchors.fill: parent
                    enabled: studio.message.level === "error" || studio.message.level === "warn"
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: studio.openSheet(studio.missing ? "singbox" : "conn")
                }
            }
            VpnPill {
                visible: studio.showForceOff
                text: studio.tr("force_off", "Force off")
                accent: ThemeBackend.red
                enabled: !VpnService.forcing
                implicitHeight: studio.s(26)
                onClicked: VpnService.forceOff()
            }
        }

        // subscription bar
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false               // nested layouts fill by default
            Layout.preferredHeight: studio.s(40)
            spacing: studio.s(8)

            Rectangle {
                id: subChip
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: VpnService.hasSource
                radius: Math.min(height / 2, (studio.st.radius || 20) * 0.6)
                color: Qt.alpha(studio.st.text || "#ffffff", subMouse.containsMouse ? 0.10 : 0.05)
                border.width: 1
                border.color: Qt.alpha(studio.st.border || "#ffffff", 0.10)
                Behavior on color { ColorAnimation { duration: 140 } }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: studio.s(12)
                    anchors.rightMargin: studio.s(12)
                    spacing: studio.s(8)
                    Text {
                        text: "󰑫"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: studio.s(15)
                        color: studio.st.active || "#7fd4ff"
                    }
                    Text {
                        text: VpnService.subscriptionName !== "" ? VpnService.subscriptionName : studio.tr("subs.title", "VPN subscriptions")
                        elide: Text.ElideRight
                        Layout.maximumWidth: subChip.width * 0.45
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: studio.s(12)
                        color: studio.st.text || "#eef1f6"
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            let lu = VpnService.lastUpdate;
                            let parts = [studio.tr("servers_count", "Servers: {count}").replace("{count}", VpnService.servers.length)];
                            if (lu && lu.time) parts.push(studio.tr("subs.updated", "updated {time}").replace("{time}", studio.timeText(lu.time)));
                            return parts.join(" · ");
                        }
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: studio.s(11)
                        color: Qt.alpha(studio.st.text || "#eef1f6", 0.55)
                    }
                    Text {
                        text: "󰅀"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: studio.s(12)
                        color: Qt.alpha(studio.st.text || "#eef1f6", 0.55)
                    }
                }
                MouseArea {
                    id: subMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: studio.openSheet("subs")
                }
                Accessible.role: Accessible.Button
                Accessible.name: studio.tr("subs.title", "VPN subscriptions")
            }
            Item { Layout.fillWidth: true; visible: !VpnService.hasSource }
            VpnPill {
                Layout.preferredHeight: studio.s(40)
                implicitHeight: studio.s(40)
                icon: "󰐕"
                text: studio.tr("subs.add_button", "Add VPN subscription")
                filled: !VpnService.hasSource
                onClicked: {
                    studio.openSheet("subs");
                    subsSheet.focusAdd();
                }
            }
            Item { Layout.fillWidth: true; visible: !VpnService.hasSource }
        }
    }

    // ---- sheets (invisible and disabled while closed) ----------------------------------
    VpnServersSheet {
        objectName: "vpnSheet_servers"
        open: studio.sheet === "servers"
        onCloseRequested: studio.sheet = ""
    }
    VpnSubsSheet {
        id: subsSheet
        objectName: "vpnSheet_subs"
        open: studio.sheet === "subs"
        onCloseRequested: studio.sheet = ""
        onConnectedRequested: studio.sheet = ""
        onServersRequested: studio.openSheet("servers")
    }
    VpnConnectionSheet {
        objectName: "vpnSheet_conn"
        open: studio.sheet === "conn"
        forceOffShown: studio.showForceOff
        onCloseRequested: studio.sheet = ""
        onSingboxRequested: studio.openSheet("singbox")
    }
    VpnSingboxSheet {
        objectName: "vpnSheet_singbox"
        open: studio.sheet === "singbox"
        onCloseRequested: studio.sheet = ""
    }
}
