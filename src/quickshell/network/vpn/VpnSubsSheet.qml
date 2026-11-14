import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../"

// VPN subscriptions: add (link + optional name), choose the active one, rename, refresh,
// delete. The link is handed to the backend on stdin only and is never shown again: the
// list shows the provider host or "N links" (serp_vpn.py sub-add / subs).
VpnSheet {
    id: sh
    title: tr("subs.title", "VPN subscriptions")
    icon: "󰑫"
    property string editing: ""                // id being renamed
    property string confirmRemove: ""
    property bool clearOnSuccess: false

    function tr(key, en) { return I18n.t("vpn." + key, en); }
    function focusAdd() { Qt.callLater(() => sh.linkInput.forceActiveFocus()); }
    function add() {
        let t = sh.linkInput.text.trim();
        if (t === "") {
            VpnService.error = tr("errors.empty_link", "Paste a subscription link first.");
            return;
        }
        clearOnSuccess = true;
        VpnService.addSub(t, sh.nameInput.text);
    }
    function pasteLink() {
        sh.linkInput.forceActiveFocus();
        let before = sh.linkInput.text;
        sh.linkInput.selectAll();
        sh.linkInput.paste();
        Qt.callLater(() => {
            if (sh.linkInput.text === before || sh.linkInput.text === "") wlPaste.running = true;
        });
    }
    function timeText(t) {
        if (!t) return "";
        return Qt.formatDateTime(new Date(t * 1000), "dd.MM.yyyy HH:mm");
    }
    function describe(it) {
        let src = it.kind === "url" ? (it.host || "") : it.kind === "links"
            ? tr("subs.links", "{count} links").replace("{count}", it.count || 0) : tr("subs.app", "app link");
        let lu = it.lastUpdate || null;
        if (!lu || !lu.time) return { text: src + " · " + tr("subs.never", "not updated yet"), error: false };
        if (lu.ok === false)
            return { text: src + " · " + timeText(lu.time) + " · " + (lu.message || tr("state.error", "Error")), error: true };
        return { text: src + " · " + tr("servers_count", "Servers: {count}").replace("{count}", lu.servers || 0)
                       + " · " + timeText(lu.time), error: false };
    }

    onOpenChanged: if (!open) { editing = ""; confirmRemove = ""; }

    Connections {
        target: VpnService
        function onBusyChanged() {
            if (!VpnService.busy && sh.clearOnSuccess) {
                if (VpnService.error === "") {          // keep the text when it failed
                    sh.linkInput.text = "";
                    sh.nameInput.text = "";
                }
                sh.clearOnSuccess = false;
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
                sh.linkInput.text = t;
                sh.linkInput.forceActiveFocus();
                sh.linkInput.cursorPosition = sh.linkInput.text.length;
            }
        }
    }

    component Field: Rectangle {
        property alias input: ti
        property string placeholder: ""
        property string icon: ""
        radius: Scaler.s(10)
        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.06)
        border.width: 1
        border.color: ti.activeFocus ? Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.7) : Qt.alpha(VpnAppearance.style.border || "#ffffff", 0.12)
        Behavior on border.color { ColorAnimation { duration: 160 } }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Scaler.s(10)
            anchors.verticalCenter: parent.verticalCenter
            text: parent.icon
            visible: parent.icon !== ""
            font.family: ThemeBackend.iconFont
            font.pixelSize: Scaler.s(14)
            color: ti.activeFocus ? (VpnAppearance.style.active || "#7fd4ff") : Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.45)
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: parent.icon !== "" ? Scaler.s(32) : Scaler.s(10)
            anchors.right: parent.right
            anchors.rightMargin: Scaler.s(10)
            anchors.verticalCenter: parent.verticalCenter
            visible: ti.text === ""
            text: parent.placeholder
            elide: Text.ElideRight
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(12)
            color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.4)
        }
        TextInput {
            id: ti
            anchors.fill: parent
            anchors.leftMargin: parent.icon !== "" ? Scaler.s(32) : Scaler.s(10)
            anchors.rightMargin: Scaler.s(10)
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            color: VpnAppearance.style.text || "#eef1f6"
            selectionColor: Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.45)
            selectedTextColor: VpnAppearance.style.text || "#eef1f6"
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(12)
            inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Scaler.s(10)

        // add form
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Scaler.s(36)
            spacing: Scaler.s(8)
            Field {
                id: linkField
                Layout.fillWidth: true
                Layout.fillHeight: true
                icon: "󰌷"
                placeholder: sh.tr("placeholder", "Subscription link (https://…, vless://…) · Ctrl+V")
                Component.onCompleted: {
                    input.inputMethodHints = Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhUrlCharactersOnly;
                }
            }
            Field {
                id: nameField
                Layout.preferredWidth: Scaler.s(130)
                Layout.fillHeight: true
                placeholder: sh.tr("subs.name", "Name (optional)")
            }
            VpnIconButton {
                Layout.preferredWidth: Scaler.s(36); Layout.preferredHeight: Scaler.s(36)
                icon: "󰆒"
                tip: sh.tr("paste", "Paste")
                enabled: !VpnService.busy
                onClicked: sh.pasteLink()
            }
            VpnPill {
                implicitHeight: Scaler.s(36)
                text: sh.tr("subs.add", "Add")
                icon: "󰐕"
                busy: VpnService.busy && VpnService.busyAction === "sub-add"
                enabled: !VpnService.busy && sh.linkInput.text.trim() !== ""
                onClicked: sh.add()
            }
        }
        Text {
            Layout.fillWidth: true
            visible: VpnService.error !== ""
            text: VpnService.error
            wrapMode: Text.Wrap
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(11)
            color: ThemeBackend.red
        }
        Text {
            Layout.fillWidth: true
            text: sh.tr("subs.formats", "Supported: subscription URLs (base64, Clash/Mihomo YAML, sing-box JSON) and vless/vmess/trojan/ss/hysteria2/tuic links. The link is stored only on this computer and is never shown in logs.")
            wrapMode: Text.Wrap
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(10)
            color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.45)
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.alpha(VpnAppearance.style.border || "#ffffff", 0.1) }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Scaler.s(6)
            boundsBehavior: Flickable.StopAtBounds
            model: VpnService.subs

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property var info: sh.describe(modelData)
                readonly property bool isActive: modelData.active === true
                width: ListView.view.width
                height: Scaler.s(52)
                radius: Scaler.s(10)
                color: isActive ? Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.12)
                    : Qt.alpha(VpnAppearance.style.text || "#ffffff", rMouse.containsMouse ? 0.08 : 0.04)
                border.width: isActive ? 1 : 0
                border.color: Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.4)
                Behavior on color { ColorAnimation { duration: 140 } }

                MouseArea {
                    id: rMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: row.isActive ? Qt.ArrowCursor : Qt.PointingHandCursor
                    enabled: !VpnService.busy && sh.editing !== row.modelData.id
                    onClicked: if (!row.isActive) VpnService.useSub(row.modelData.id)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Scaler.s(12)
                    anchors.rightMargin: Scaler.s(8)
                    spacing: Scaler.s(8)
                    Rectangle {                         // radio
                        Layout.preferredWidth: Scaler.s(14); Layout.preferredHeight: Scaler.s(14); radius: Scaler.s(7)
                        color: "transparent"
                        border.width: Scaler.s(2)
                        border.color: row.isActive ? (VpnAppearance.style.active || "#7fd4ff") : Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.4)
                        Rectangle {
                            anchors.centerIn: parent
                            width: Scaler.s(6); height: width; radius: width / 2
                            visible: row.isActive
                            color: VpnAppearance.style.active || "#7fd4ff"
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Scaler.s(2)
                        Text {
                            Layout.fillWidth: true
                            visible: sh.editing !== row.modelData.id
                            text: row.modelData.name
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: Scaler.s(12)
                            color: VpnAppearance.style.text || "#eef1f6"
                        }
                        Field {
                            id: renameField
                            Layout.fillWidth: true
                            Layout.preferredHeight: Scaler.s(24)
                            visible: sh.editing === row.modelData.id
                            onVisibleChanged: if (visible) { input.text = row.modelData.name; input.selectAll(); input.forceActiveFocus(); }
                            Connections {
                                target: renameField.input
                                function onAccepted() {
                                    VpnService.renameSub(row.modelData.id, renameField.input.text);
                                    sh.editing = "";
                                }
                            }
                            Keys.onEscapePressed: (event) => { sh.editing = ""; event.accepted = true; }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.info.text
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(10)
                            color: row.info.error ? ThemeBackend.red : Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.55)
                        }
                    }
                    VpnIconButton {
                        visible: row.isActive
                        icon: "󰑓"
                        tip: sh.tr("update", "Update")
                        enabled: !VpnService.busy
                        spinning: VpnService.busy && (VpnService.busyAction === "update" || VpnService.busyAction === "sub-use")
                        onClicked: VpnService.update()
                    }
                    VpnIconButton {
                        icon: sh.editing === row.modelData.id ? "󰄬" : "󰏫"
                        tip: sh.tr("subs.rename", "Rename")
                        enabled: !VpnService.busy
                        onClicked: {
                            if (sh.editing === row.modelData.id) {
                                VpnService.renameSub(row.modelData.id, renameField.input.text);
                                sh.editing = "";
                            } else {
                                sh.editing = row.modelData.id;
                            }
                        }
                    }
                    VpnPill {
                        implicitHeight: Scaler.s(30)
                        text: sh.confirmRemove === row.modelData.id ? sh.tr("forget_confirm", "Remove?") : ""
                        icon: "󰆴"
                        accent: ThemeBackend.red
                        filled: sh.confirmRemove === row.modelData.id
                        enabled: !VpnService.busy
                        onClicked: {
                            if (sh.confirmRemove !== row.modelData.id) { sh.confirmRemove = row.modelData.id; return; }
                            sh.confirmRemove = "";
                            VpnService.removeSub(row.modelData.id);
                        }
                        Accessible.name: sh.tr("forget", "Remove")
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            visible: VpnService.subs.length === 0
            text: sh.tr("subs.empty", "No subscriptions yet. Paste the link your VPN provider gave you.")
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(12)
            color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.6)
        }
    }

    property alias linkInput: linkField.input
    property alias nameInput: nameField.input
    Connections {
        target: linkField.input
        function onAccepted() { sh.add(); }
    }
}
