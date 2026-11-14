import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

// VPN block of the network panel (Super+N): a card above the Internet card in the
// same material and with the same intro, plus the server list, which opens as an
// overlay below the card. State and actions live in the VpnService singleton.
Item {
    id: block

    property var window                     // NetworkPopup root: s(), animWin(), easeOut(), introState, exitOpacity
    readonly property real cardHeight: s(106)
    readonly property real gap: s(8)
    property bool listOpen: false
    property var expanded: ({})             // country code -> bool
    property bool confirmForget: false
    property bool clearOnSuccess: false

    function s(v) { return Scaler.s(v); }
    function tr(key, en) { return I18n.t("vpn." + key, en); }

    readonly property string vpnState: VpnService.vpnState
    readonly property bool busy: VpnService.busy
    readonly property string stateText: {
        switch (vpnState) {
        case "connected": return tr("state.connected", "Connected");
        case "disconnected": return tr("state.disconnected", "Disconnected");
        case "none": return tr("state.none", "No subscription");
        case "missing": return tr("state.missing", "sing-box is not installed");
        case "error": return tr("state.error", "Error");
        default: return "…";
        }
    }
    readonly property color stateColor: vpnState === "connected" ? ThemeBackend.green
        : (vpnState === "error" || vpnState === "missing") ? ThemeBackend.red
        : ThemeBackend.overlay1
    readonly property string problemText: VpnService.error !== "" ? VpnService.error : (VpnService.status.error || "")
    readonly property bool tun: VpnService.mode === "tun"
    readonly property var firstWarning: VpnService.checks.find(c => c.level === "warn") || null
    readonly property string detailText: {
        if (VpnService.forcing) return tr("busy.force", "Turning the VPN off…");
        if (busy) {
            switch (VpnService.busyAction) {
            case "set-source": case "update": return tr("busy.update", "Downloading and checking the subscription…");
            case "connect": case "select": return tr("busy.connect", "Connecting…");
            case "disconnect": return tr("busy.disconnect", "Disconnecting…");
            case "mode": return tr("busy.mode", "Switching mode…");
            default: return "…";
            }
        }
        if (problemText !== "") return problemText;
        if (firstWarning) return firstWarning.message;
        if (vpnState === "connected" && tun) return tr("tun_on", "All traffic of this computer goes through the VPN");
        if (vpnState === "connected") return tr("proxy_at", "HTTP/SOCKS5 proxy") + "  " + VpnService.proxy;
        if (vpnState === "none") return tr("hint.none", "Paste a subscription link below and press Save");
        if (VpnService.warning !== "") return VpnService.warning;
        return tr("servers_count", "Servers: {count}").replace("{count}", VpnService.servers.length);
    }
    readonly property bool detailIsProblem: !busy && problemText !== ""
    readonly property bool detailIsWarning: !busy && !detailIsProblem && firstWarning !== null
    readonly property bool showForceOff: VpnService.canForceOff || VpnService.forcing
        || (tun && (vpnState === "error" || (busy && VpnService.busyAction === "disconnect")))

    function pingText(tag) {
        let d = VpnService.delays[tag];
        if (d === undefined) return VpnService.pinging ? "…" : "";
        if (d <= 0) return tr("timeout", "timeout");
        return d + " " + tr("ms", "ms");
    }
    function pingColor(d) {
        if (d === undefined || d <= 0) return ThemeBackend.overlay1;
        if (d < 150) return ThemeBackend.green;
        if (d < 400) return ThemeBackend.yellow;
        return ThemeBackend.peach;
    }

    function save() {
        let t = linkInput.text.trim();
        if (t !== "") {
            clearOnSuccess = true;
            VpnService.setSource(t);
        } else if (VpnService.hasSource) {
            VpnService.update();
        }
    }

    function pasteLink() {
        linkInput.forceActiveFocus();
        let before = linkInput.text;
        linkInput.selectAll();
        linkInput.paste();
        Qt.callLater(() => {
            if (linkInput.text === before || linkInput.text === "") wlPaste.running = true;
        });
    }

    function openList() {
        let ex = {};
        let cur = VpnService.currentServer;
        if (cur) ex[cur.country || ""] = true;
        expanded = ex;
        confirmForget = false;
        listOpen = true;
        VpnService.ping();
    }

    function toggleCountry(code) {
        let ex = Object.assign({}, expanded);
        ex[code] = !ex[code];
        expanded = ex;
    }

    // ---- wiring ------------------------------------------------------------------------

    Binding {
        target: VpnService
        property: "panelOpen"
        value: block.window ? block.window.visible : false
    }

    Connections {
        target: block.window
        function onVisibleChanged() {
            if (!block.window.visible) {
                block.listOpen = false;
                block.confirmForget = false;
            }
        }
    }

    Connections {
        target: VpnService
        function onBusyChanged() {
            if (!VpnService.busy && block.clearOnSuccess) {
                if (VpnService.error === "") linkInput.text = "";   // keep the text when it failed
                block.clearOnSuccess = false;
            }
        }
    }

    // Paste fallback when Qt's clipboard is empty on this surface (wl-paste output is
    // read from stdout, nothing is passed on a command line).
    Process {
        id: wlPaste
        command: ["wl-paste", "--no-newline", "--type", "text/plain"]
        stdout: StdioCollector {
            onStreamFinished: {
                let t = this.text.trim();
                if (t === "") return;
                linkInput.text = t;
                linkInput.forceActiveFocus();
                linkInput.cursorPosition = linkInput.text.length;
            }
        }
    }

    // ---- card --------------------------------------------------------------------------

    Item {
        id: card
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: block.cardHeight
        visible: block.window ? block.window.visible : true
        readonly property real intro: block.window
            ? block.window.easeOut(block.window.animWin(block.window.introState, 0.0, 0.12)) : 1.0
        readonly property real exitOp: block.window ? block.window.exitOpacity : 1.0
        opacity: exitOp * intro
        scale: (0.96 + 0.04 * intro) * (0.97 + 0.03 * exitOp)
        transformOrigin: Item.Bottom

        Rectangle {
            id: cardBg
            anchors.fill: parent
            radius: ThemeBackend.borderRadius
            color: Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
            clip: true
            border.width: 1
            border.color: Qt.alpha(block.stateColor, block.vpnState === "connected" ? 0.45 : 0.0)
            Behavior on border.color { ColorAnimation { duration: 400; easing.type: Easing.OutCubic } }

            WallpaperBlur {
                z: -1
                anchors.fill: parent
                topLeftRadius: parent.topLeftRadius
                topRightRadius: parent.topRightRadius
                bottomLeftRadius: parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius
            }

            // soft glow on the left that follows the state colour
            Rectangle {
                width: parent.width * 0.5
                height: parent.height * 2.2
                radius: width / 2
                x: -width * 0.55
                y: (parent.height - height) / 2
                color: block.stateColor
                opacity: block.vpnState === "connected" ? 0.10 : 0.0
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: block.s(12)
            spacing: block.s(8)

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: block.s(40)
                spacing: block.s(10)

                // state badge
                Rectangle {
                    Layout.preferredWidth: block.s(40)
                    Layout.preferredHeight: block.s(40)
                    radius: block.s(12)
                    color: Qt.alpha(block.stateColor, 0.16)
                    Behavior on color { ColorAnimation { duration: 300 } }
                    Text {
                        anchors.centerIn: parent
                        text: block.vpnState === "connected" ? "󰦝" : (block.vpnState === "error" || block.vpnState === "missing") ? "󰒙" : "󰦞"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: block.s(20)
                        color: block.stateColor
                        visible: !block.busy
                    }
                    Spinner {
                        anchors.centerIn: parent
                        size: block.s(20)
                        color: ThemeBackend.blue
                        running: block.busy
                        visible: block.busy
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: block.s(80)
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: block.s(6)
                        Text {
                            text: "VPN"
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Black
                            font.pixelSize: block.s(14)
                            color: ThemeBackend.text
                        }
                        Rectangle {
                            Layout.preferredWidth: block.s(6); Layout.preferredHeight: block.s(6); radius: block.s(3)
                            color: block.stateColor
                        }
                        Text {
                            Layout.fillWidth: true
                            text: block.stateText + (block.tun ? "  ·  TUN" : "")
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: block.s(12)
                            color: block.stateColor
                        }
                    }
                    Text {
                        id: detailLabel
                        Layout.fillWidth: true
                        text: block.detailText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: block.s(11)
                        color: block.detailIsProblem ? ThemeBackend.red : block.detailIsWarning ? ThemeBackend.yellow : ThemeBackend.subtext0
                        MouseArea {
                            anchors.fill: parent
                            enabled: block.detailIsProblem || block.detailIsWarning || block.vpnState === "connected"
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: block.openList()
                        }
                    }
                }

                // current server: country + ping; opens the server list
                Rectangle {
                    id: chip
                    visible: VpnService.servers.length > 0
                    Layout.preferredHeight: block.s(32)
                    Layout.preferredWidth: Math.min(block.s(230), chipRow.implicitWidth + block.s(24))
                    radius: height / 2
                    color: chipMouse.containsMouse || block.listOpen ? Qt.alpha(ThemeBackend.surface1, 0.85) : Qt.alpha(ThemeBackend.surface0, 0.7)
                    border.width: 1
                    border.color: block.listOpen ? Qt.alpha(ThemeBackend.blue, 0.6) : Qt.alpha(ThemeBackend.surface2, 0.4)
                    Behavior on color { ColorAnimation { duration: 160 } }

                    readonly property var cur: VpnService.currentServer
                    readonly property string title: cur ? (cur.country ? cur.countryName : cur.name) : block.tr("choose", "Choose a server")
                    readonly property var delay: cur ? VpnService.delays[cur.tag] : undefined

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: block.s(6)
                        Text {
                            text: chip.cur && chip.cur.flag ? chip.cur.flag : "󰇧"
                            font.family: chip.cur && chip.cur.flag ? ThemeBackend.fontFamily : ThemeBackend.iconFont
                            font.pixelSize: block.s(14)
                            color: ThemeBackend.text
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: chip.title
                            width: Math.min(implicitWidth, block.s(120))
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: block.s(12)
                            color: ThemeBackend.text
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: text !== ""
                            text: chip.cur ? block.pingText(chip.cur.tag) : ""
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: block.s(11)
                            color: block.pingColor(chip.delay)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "󰅀"
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: block.s(12)
                            color: ThemeBackend.subtext0
                            rotation: block.listOpen ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: block.listOpen ? (block.listOpen = false) : block.openList()
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: block.tr("servers", "Servers")
                }

                PillButton {
                    id: connectBtn
                    Layout.preferredHeight: block.s(32)
                    text: VpnService.connected ? block.tr("disconnect", "Disconnect") : block.tr("connect", "Connect")
                    accent: VpnService.connected ? ThemeBackend.red : ThemeBackend.green
                    filled: !VpnService.connected
                    enabled: !block.busy && !VpnService.forcing && VpnService.hasSource && block.vpnState !== "missing" && VpnService.servers.length > 0
                    onClicked: VpnService.toggle()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: block.s(34)
                spacing: block.s(8)

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: block.s(10)
                    color: Qt.alpha(ThemeBackend.surface0, 0.65)
                    border.width: 1
                    border.color: linkInput.activeFocus ? Qt.alpha(ThemeBackend.blue, 0.7) : Qt.alpha(ThemeBackend.surface2, 0.35)
                    Behavior on border.color { ColorAnimation { duration: 160 } }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: block.s(32)
                        anchors.right: parent.right
                        anchors.rightMargin: block.s(10)
                        anchors.verticalCenter: parent.verticalCenter
                        visible: linkInput.text === ""
                        text: VpnService.hasSource
                            ? block.tr("placeholder_saved", "Subscription saved · paste a new link to replace it")
                            : block.tr("placeholder", "Subscription link (https://…, vless://…) · Ctrl+V")
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: block.s(12)
                        color: ThemeBackend.overlay1
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: block.s(10)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󰌷"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: block.s(14)
                        color: linkInput.activeFocus ? ThemeBackend.blue : ThemeBackend.overlay1
                    }
                    TextInput {
                        id: linkInput
                        anchors.fill: parent
                        anchors.leftMargin: block.s(32)
                        anchors.rightMargin: block.s(10)
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        color: ThemeBackend.text
                        selectionColor: Qt.alpha(ThemeBackend.blue, 0.45)
                        selectedTextColor: ThemeBackend.text
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: block.s(12)
                        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly
                        enabled: !block.busy
                        onAccepted: block.save()
                        Keys.onEscapePressed: (event) => {
                            if (text !== "") { text = ""; event.accepted = true; }
                            else { focus = false; event.accepted = false; }
                        }
                        Accessible.name: block.tr("link", "Subscription link")
                    }
                }

                IconButtonSmall {
                    Layout.preferredWidth: block.s(34)
                    Layout.preferredHeight: block.s(34)
                    icon: "󰆒"
                    tip: block.tr("paste", "Paste")
                    enabled: !block.busy
                    onClicked: block.pasteLink()
                }

                PillButton {
                    Layout.preferredHeight: block.s(34)
                    text: linkInput.text.trim() !== "" || !VpnService.hasSource ? block.tr("save", "Save") : block.tr("update", "Update")
                    accent: ThemeBackend.blue
                    filled: linkInput.text.trim() !== ""
                    enabled: !block.busy && (linkInput.text.trim() !== "" || VpnService.hasSource)
                    onClicked: block.save()
                }
            }
        }
    }

    // ---- server list overlay -----------------------------------------------------------

    MouseArea {                           // a click outside closes the list
        anchors.fill: parent
        anchors.topMargin: card.height
        z: 50
        visible: block.listOpen
        hoverEnabled: true
        onClicked: block.listOpen = false
        onWheel: (wheel) => { wheel.accepted = true; }
    }

    Rectangle {
        id: panel
        z: 51
        x: 0
        width: parent.width
        property real openProg: block.listOpen ? 1.0 : 0.0
        Behavior on openProg { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        y: card.height + block.s(6) - (1.0 - openProg) * block.s(10)
        height: Math.max(0, Math.min(parent.height - card.height - block.s(14), panelCol.implicitHeight + block.s(24)))
        opacity: openProg
        visible: openProg > 0.01
        radius: ThemeBackend.borderRadius
        color: Qt.alpha(ThemeBackend.mantle, 0.97)
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.surface2, 0.5)
        clip: true

        MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: (wheel) => { wheel.accepted = false; } }

        ColumnLayout {
            id: panelCol
            anchors.fill: parent
            anchors.margins: block.s(12)
            spacing: block.s(10)

            // problem / install hint
            Rectangle {
                Layout.fillWidth: true
                visible: block.problemText !== "" || block.vpnState === "missing"
                Layout.preferredHeight: problemCol.implicitHeight + block.s(16)
                radius: block.s(10)
                color: Qt.alpha(ThemeBackend.red, 0.12)
                border.width: 1
                border.color: Qt.alpha(ThemeBackend.red, 0.35)
                ColumnLayout {
                    id: problemCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: block.s(10)
                    spacing: block.s(6)
                    Text {
                        Layout.fillWidth: true
                        text: block.problemText !== "" ? block.problemText : block.tr("state.missing", "sing-box is not installed")
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: block.s(12)
                        color: ThemeBackend.text
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: block.vpnState === "missing"
                        spacing: block.s(8)
                        Text {
                            Layout.fillWidth: true
                            text: VpnService.installHint
                            wrapMode: Text.WrapAnywhere
                            font.family: "monospace"
                            font.pixelSize: block.s(11)
                            color: ThemeBackend.subtext1
                        }
                        PillButton {
                            Layout.preferredHeight: block.s(28)
                            text: block.tr("copy", "Copy")
                            accent: ThemeBackend.blue
                            onClicked: VpnService.copyText(VpnService.installHint)
                        }
                    }
                }
            }

            // mode: local proxy (stage 1) or the whole system through TUN (stage 2)
            RowLayout {
                Layout.fillWidth: true
                spacing: block.s(8)
                Rectangle {
                    id: modeSwitch
                    Layout.preferredHeight: block.s(30)
                    Layout.preferredWidth: block.s(220)
                    radius: height / 2
                    color: Qt.alpha(ThemeBackend.surface0, 0.65)
                    border.width: 1
                    border.color: Qt.alpha(ThemeBackend.surface2, 0.35)
                    Rectangle {                   // sliding highlight
                        width: parent.width / 2 - block.s(4)
                        height: parent.height - block.s(6)
                        y: block.s(3)
                        x: block.tun ? parent.width / 2 + block.s(1) : block.s(3)
                        radius: height / 2
                        color: Qt.alpha(ThemeBackend.blue, 0.75)
                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: [
                                { key: "proxy", label: block.tr("mode.proxy", "Proxy") },
                                { key: "tun", label: block.tr("mode.tun", "TUN · whole system") }
                            ]
                            delegate: Item {
                                required property var modelData
                                readonly property bool active: VpnService.mode === modelData.key
                                readonly property bool usable: modelData.key === "proxy" || VpnService.tunInstalled
                                width: modeSwitch.width / 2
                                height: modeSwitch.height
                                opacity: usable ? 1.0 : 0.45
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: block.s(11)
                                    color: parent.active ? ThemeBackend.crust : ThemeBackend.text
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !block.busy && !VpnService.forcing && !parent.active
                                    onClicked: {
                                        if (!parent.usable) {
                                            VpnService.error = block.tr("mode.tun_missing",
                                                "TUN mode needs the serpantinum-vpn service: run the Serpantinum installer again.");
                                            return;
                                        }
                                        VpnService.setMode(parent.modelData.key);
                                    }
                                }
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData.label
                                Accessible.checked: active
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: block.tun ? block.tr("mode.tun_desc", "All apps, through the system service")
                                    : block.tr("mode.proxy_desc", "Only apps set to use the proxy")
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: block.s(11)
                    color: ThemeBackend.subtext0
                }
                PillButton {
                    Layout.preferredHeight: block.s(28)
                    visible: block.showForceOff
                    text: block.tr("force_off", "Force off")
                    accent: ThemeBackend.red
                    filled: true
                    enabled: !VpnService.forcing
                    onClicked: VpnService.forceOff()
                }
            }

            // DNS notes and other VPNs that conflict with TUN
            Repeater {
                model: VpnService.checks
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: block.s(8)
                    Text {
                        Layout.alignment: Qt.AlignTop
                        text: parent.modelData.level === "warn" ? "󰀦" : "󰋽"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: block.s(13)
                        color: parent.modelData.level === "warn" ? ThemeBackend.yellow : ThemeBackend.overlay1
                    }
                    Text {
                        Layout.fillWidth: true
                        text: parent.modelData.message
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: block.s(11)
                        color: parent.modelData.level === "warn" ? ThemeBackend.text : ThemeBackend.subtext0
                    }
                }
            }

            // proxy address, ping, refresh, forget
            RowLayout {
                Layout.fillWidth: true
                spacing: block.s(8)
                Text {
                    Layout.fillWidth: true
                    text: block.tr("proxy_at", "HTTP/SOCKS5 proxy") + "  " + VpnService.proxy
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: block.s(11)
                    color: ThemeBackend.subtext0
                }
                IconButtonSmall {
                    Layout.preferredWidth: block.s(28); Layout.preferredHeight: block.s(28)
                    icon: "󰆏"; tip: block.tr("copy_proxy", "Copy proxy address")
                    onClicked: VpnService.copyText(VpnService.proxy)
                }
                IconButtonSmall {
                    Layout.preferredWidth: block.s(28); Layout.preferredHeight: block.s(28)
                    icon: "󰓅"; tip: block.tr("ping", "Measure ping")
                    spinning: VpnService.pinging
                    enabled: !VpnService.pinging && VpnService.servers.length > 0
                    onClicked: VpnService.ping()
                }
                IconButtonSmall {
                    Layout.preferredWidth: block.s(28); Layout.preferredHeight: block.s(28)
                    icon: "󰑓"; tip: block.tr("update", "Update")
                    enabled: !block.busy && VpnService.hasSource
                    spinning: block.busy && (VpnService.busyAction === "update" || VpnService.busyAction === "set-source")
                    onClicked: VpnService.update()
                }
                PillButton {
                    Layout.preferredHeight: block.s(28)
                    visible: VpnService.hasSource
                    text: block.confirmForget ? block.tr("forget_confirm", "Remove?") : block.tr("forget", "Remove")
                    accent: ThemeBackend.red
                    filled: block.confirmForget
                    enabled: !block.busy
                    onClicked: {
                        if (!block.confirmForget) { block.confirmForget = true; return; }
                        block.confirmForget = false;
                        block.listOpen = false;
                        VpnService.forget();
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.alpha(ThemeBackend.surface2, 0.4)
                visible: countryList.count > 0
            }

            ListView {
                id: countryList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                Layout.minimumHeight: Math.min(contentHeight, block.s(120))
                visible: count > 0
                clip: true
                spacing: block.s(4)
                boundsBehavior: Flickable.StopAtBounds
                model: VpnService.countries

                delegate: Column {
                    id: countryDelegate
                    required property var modelData
                    readonly property bool open: block.expanded[modelData.code] === true
                    width: ListView.view.width
                    spacing: block.s(2)

                    Rectangle {
                        width: parent.width
                        height: block.s(38)
                        radius: block.s(10)
                        color: countryMouse.containsMouse ? Qt.alpha(ThemeBackend.surface0, 0.9) : Qt.alpha(ThemeBackend.surface0, 0.45)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: block.s(12)
                            anchors.rightMargin: block.s(12)
                            spacing: block.s(8)
                            Text {
                                text: countryDelegate.modelData.flag || "󰇧"
                                font.family: countryDelegate.modelData.flag ? ThemeBackend.fontFamily : ThemeBackend.iconFont
                                font.pixelSize: block.s(16)
                                color: ThemeBackend.text
                            }
                            Text {
                                Layout.fillWidth: true
                                text: countryDelegate.modelData.name
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: block.s(12)
                                color: ThemeBackend.text
                            }
                            Text {
                                text: countryDelegate.modelData.servers.length
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: block.s(11)
                                color: ThemeBackend.overlay1
                            }
                            Text {
                                Layout.preferredWidth: block.s(64)
                                horizontalAlignment: Text.AlignRight
                                text: countryDelegate.modelData.best > 0 ? countryDelegate.modelData.best + " " + block.tr("ms", "ms") : (VpnService.pinging ? "…" : "")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: block.s(11)
                                color: block.pingColor(countryDelegate.modelData.best)
                            }
                            Text {
                                text: "󰅀"
                                font.family: ThemeBackend.iconFont
                                font.pixelSize: block.s(12)
                                color: ThemeBackend.subtext0
                                rotation: countryDelegate.open ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                        }
                        MouseArea {
                            id: countryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: block.toggleCountry(countryDelegate.modelData.code)
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: countryDelegate.modelData.name
                    }

                    Repeater {
                        model: countryDelegate.open ? countryDelegate.modelData.servers : []
                        delegate: Rectangle {
                            id: serverRow
                            required property var modelData
                            readonly property bool isCurrent: VpnService.current === modelData.tag
                            readonly property var delay: VpnService.delays[modelData.tag]
                            width: countryDelegate.width
                            height: block.s(34)
                            radius: block.s(8)
                            color: isCurrent ? Qt.alpha(ThemeBackend.blue, 0.16)
                                : (serverMouse.containsMouse ? Qt.alpha(ThemeBackend.surface0, 0.7) : "transparent")
                            Behavior on color { ColorAnimation { duration: 140 } }
                            opacity: 0
                            Component.onCompleted: opacity = 1
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: block.s(20)
                                anchors.rightMargin: block.s(12)
                                spacing: block.s(8)
                                Rectangle {
                                    Layout.preferredWidth: block.s(8); Layout.preferredHeight: block.s(8); radius: block.s(4)
                                    color: serverRow.isCurrent ? (VpnService.connected ? ThemeBackend.green : ThemeBackend.blue) : "transparent"
                                    border.width: 1
                                    border.color: serverRow.isCurrent ? "transparent" : ThemeBackend.overlay0
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: serverRow.modelData.name
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: block.s(12)
                                    color: ThemeBackend.text
                                }
                                Text {
                                    text: serverRow.modelData.protocol
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: block.s(10)
                                    color: ThemeBackend.overlay1
                                }
                                Text {
                                    Layout.preferredWidth: block.s(64)
                                    horizontalAlignment: Text.AlignRight
                                    text: block.pingText(serverRow.modelData.tag)
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: block.s(11)
                                    color: block.pingColor(serverRow.delay)
                                }
                            }
                            MouseArea {
                                id: serverMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !block.busy && block.vpnState !== "missing"
                                onClicked: VpnService.select(serverRow.modelData.tag)
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: serverRow.modelData.name
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: VpnService.servers.length === 0
                text: VpnService.hasSource ? block.tr("no_servers_yet", "No servers yet. Press Update.") : block.tr("hint.none", "Paste a subscription link below and press Save")
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.family: ThemeBackend.fontFamily
                font.pixelSize: block.s(12)
                color: ThemeBackend.subtext0
            }
        }
    }

    // ---- small inline components (no access to outer ids: use Scaler directly) --------

    component Spinner: Item {
        id: sp
        property real size: 16
        property color color: ThemeBackend.blue
        property bool running: false
        property real angle: 0
        width: size
        height: size
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: Math.max(2, sp.size * 0.14)
            border.color: Qt.alpha(sp.color, 0.25)
        }
        Rectangle {
            width: Math.max(3, sp.size * 0.22)
            height: width
            radius: width / 2
            color: sp.color
            x: sp.size / 2 - width / 2 + Math.sin(sp.angle * Math.PI / 180) * (sp.size / 2 - width / 2)
            y: sp.size / 2 - height / 2 - Math.cos(sp.angle * Math.PI / 180) * (sp.size / 2 - height / 2)
        }
        NumberAnimation on angle {
            from: 0; to: 360; duration: 900
            loops: Animation.Infinite
            running: sp.running && sp.visible
        }
    }

    component PillButton: Rectangle {
        id: pb
        property string text: ""
        property color accent: ThemeBackend.blue
        property bool filled: true
        signal clicked()
        implicitWidth: pbLabel.implicitWidth + Scaler.s(28)
        implicitHeight: Scaler.s(32)
        Layout.preferredWidth: implicitWidth
        radius: height / 2
        opacity: enabled ? 1.0 : 0.45
        color: filled ? Qt.alpha(accent, pbMouse.pressed ? 0.95 : (pbMouse.containsMouse ? 0.85 : 0.75))
                      : Qt.alpha(accent, pbMouse.pressed ? 0.30 : (pbMouse.containsMouse ? 0.22 : 0.14))
        border.width: filled ? 0 : 1
        border.color: Qt.alpha(accent, 0.45)
        scale: pbMouse.pressed ? 0.97 : 1.0
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Text {
            id: pbLabel
            anchors.centerIn: parent
            text: pb.text
            font.family: ThemeBackend.fontFamily
            font.weight: Font.Bold
            font.pixelSize: Scaler.s(12)
            color: pb.filled ? ThemeBackend.crust : pb.accent
        }
        MouseArea {
            id: pbMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: pb.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
        Accessible.role: Accessible.Button
        Accessible.name: pb.text
    }

    component IconButtonSmall: Rectangle {
        id: ib
        property string icon: ""
        property string tip: ""
        property bool spinning: false
        signal clicked()
        radius: Scaler.s(10)
        opacity: enabled ? 1.0 : 0.45
        color: ibMouse.pressed ? Qt.alpha(ThemeBackend.surface1, 0.95) : (ibMouse.containsMouse ? Qt.alpha(ThemeBackend.surface1, 0.8) : Qt.alpha(ThemeBackend.surface0, 0.65))
        border.width: 1
        border.color: Qt.alpha(ThemeBackend.surface2, 0.35)
        Behavior on color { ColorAnimation { duration: 140 } }
        Text {
            anchors.centerIn: parent
            text: ib.icon
            font.family: ThemeBackend.iconFont
            font.pixelSize: Math.round(ib.height * 0.45)
            color: ThemeBackend.text
            visible: !ib.spinning
        }
        Spinner {
            anchors.centerIn: parent
            size: ib.height * 0.45
            running: ib.spinning
            visible: ib.spinning
        }
        MouseArea {
            id: ibMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: ib.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
        Accessible.role: Accessible.Button
        Accessible.name: ib.tip
    }
}
