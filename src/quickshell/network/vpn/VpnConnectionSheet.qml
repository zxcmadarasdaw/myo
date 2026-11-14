import QtQuick
import QtQuick.Layouts
import "../../"

// Connection details: proxy / TUN mode, proxy address, DNS and conflict notes, the
// emergency "Force off", the sing-box in use and "remove all VPN data".
VpnSheet {
    id: sh
    title: tr("conn.title", "Connection")
    icon: "󰒓"
    property bool forceOffShown: false
    property bool confirmForget: false
    signal singboxRequested()

    function tr(key, en) { return I18n.t("vpn." + key, en); }
    readonly property bool tun: VpnService.mode === "tun"
    readonly property var sb: VpnService.sbInfo
    onOpenChanged: if (!open) confirmForget = false

    Flickable {
        anchors.fill: parent
        clip: true
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: Scaler.s(12)

            // mode: local proxy (stage 1) or the whole system through TUN (stage 2)
            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(10)
                Rectangle {
                    id: modeSwitch
                    Layout.preferredHeight: Scaler.s(32)
                    Layout.preferredWidth: Scaler.s(240)
                    radius: height / 2
                    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.06)
                    border.width: 1
                    border.color: Qt.alpha(VpnAppearance.style.border || "#ffffff", 0.12)
                    Rectangle {
                        width: parent.width / 2 - Scaler.s(4)
                        height: parent.height - Scaler.s(6)
                        y: Scaler.s(3)
                        x: sh.tun ? parent.width / 2 + Scaler.s(1) : Scaler.s(3)
                        radius: height / 2
                        color: Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.8)
                        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: [
                                { key: "proxy", label: sh.tr("mode.proxy", "Proxy") },
                                { key: "tun", label: sh.tr("mode.tun", "TUN · whole system") }
                            ]
                            delegate: Item {
                                required property var modelData
                                readonly property bool isOn: VpnService.mode === modelData.key
                                readonly property bool usable: modelData.key === "proxy" || VpnService.tunInstalled
                                width: modeSwitch.width / 2
                                height: modeSwitch.height
                                opacity: usable ? 1.0 : 0.45
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    font.family: ThemeBackend.fontFamily
                                    font.weight: Font.Bold
                                    font.pixelSize: Scaler.s(11)
                                    color: parent.isOn ? (VpnAppearance.style.background || "#0b0d12") : (VpnAppearance.style.text || "#eef1f6")
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !VpnService.busy && !VpnService.forcing && !parent.isOn
                                    onClicked: {
                                        if (!parent.usable) {
                                            VpnService.error = sh.tr("mode.tun_missing",
                                                "TUN mode needs the serpantinum-vpn service: run the Serpantinum installer again.");
                                            return;
                                        }
                                        VpnService.setMode(parent.modelData.key);
                                    }
                                }
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: modelData.label
                                Accessible.checked: isOn
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: sh.tun ? sh.tr("mode.tun_desc", "All apps, through the system service")
                                 : sh.tr("mode.proxy_desc", "Only apps set to use the proxy")
                    wrapMode: Text.Wrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(11)
                    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.6)
                }
            }

            // proxy address
            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(8)
                Text {
                    Layout.fillWidth: true
                    text: sh.tr("proxy_at", "HTTP/SOCKS5 proxy") + "  " + VpnService.proxy
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(12)
                    color: VpnAppearance.style.text || "#eef1f6"
                }
                VpnIconButton {
                    icon: "󰆏"
                    tip: sh.tr("copy_proxy", "Copy proxy address")
                    onClicked: VpnService.copyText(VpnService.proxy)
                }
                VpnPill {
                    visible: sh.forceOffShown
                    text: sh.tr("force_off", "Force off")
                    accent: ThemeBackend.red
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
                    spacing: Scaler.s(8)
                    Text {
                        Layout.alignment: Qt.AlignTop
                        text: parent.modelData.level === "warn" ? "󰀦" : "󰋽"
                        font.family: ThemeBackend.iconFont
                        font.pixelSize: Scaler.s(13)
                        color: parent.modelData.level === "warn" ? ThemeBackend.yellow : Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.5)
                    }
                    Text {
                        Layout.fillWidth: true
                        text: parent.modelData.message
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(11)
                        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", parent.modelData.level === "warn" ? 0.9 : 0.6)
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.alpha(VpnAppearance.style.border || "#ffffff", 0.1) }

            // sing-box in use
            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(10)
                Text {
                    text: "󰏗"
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(16)
                    color: sh.sb.works ? (VpnAppearance.style.active || "#7fd4ff") : ThemeBackend.red
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: sh.sb.works ? "sing-box " + (sh.sb.version || "") : sh.tr("state.missing", "sing-box is not installed")
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: Scaler.s(12)
                        color: VpnAppearance.style.text || "#eef1f6"
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: (sh.sb.path || "") !== ""
                        text: (sh.sb.path || "") + "  ·  " + sh.tr("sb.source." + (sh.sb.source || "system"), sh.sb.source || "")
                        elide: Text.ElideMiddle
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.5)
                    }
                }
                VpnPill {
                    text: sh.tr("sb.manage", "Manage")
                    filled: false
                    onClicked: sh.singboxRequested()
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.alpha(VpnAppearance.style.border || "#ffffff", 0.1) }

            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(10)
                Text {
                    Layout.fillWidth: true
                    text: sh.tr("forget_all_desc", "Remove all subscriptions, servers and the VPN configuration from this computer.")
                    wrapMode: Text.Wrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(11)
                    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.55)
                }
                VpnPill {
                    visible: VpnService.hasSource
                    text: sh.confirmForget ? sh.tr("forget_confirm", "Remove?") : sh.tr("forget_all", "Remove all")
                    accent: ThemeBackend.red
                    filled: sh.confirmForget
                    enabled: !VpnService.busy
                    onClicked: {
                        if (!sh.confirmForget) { sh.confirmForget = true; return; }
                        sh.confirmForget = false;
                        VpnService.forget();
                        sh.closeRequested();
                    }
                }
            }
        }
    }
}
