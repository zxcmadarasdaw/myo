import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import "../../"

VpnSheet {
    id: sh
    title: "sing-box"
    icon: "󰏗"

    function tr(key, en) { return I18n.t("vpn." + key, en); }
    readonly property var info: VpnService.sbInfo
    readonly property bool installing: VpnService.sbInstalling
    readonly property bool tun: VpnService.mode === "tun"
    readonly property string enginePath: (tun ? info.tunPath : info.path) || ""
    readonly property string engineVersion: (tun ? info.tunVersion : info.version) || ""

    onOpenChanged: if (open) VpnService.singboxInfo()

    // A vpn-bundle folder from a Serpantinum release (USB stick, Downloads…): installs offline.
    FolderDialog {
        id: bundlePicker
        title: sh.tr("sb.choose_bundle", "Choose the vpn-bundle folder")
        onAccepted: VpnService.installSingbox("bundle", selectedFolder.toString())
    }

    Flickable {
        anchors.fill: parent
        clip: true
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: Scaler.s(12)

            // current state
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: stateCol.implicitHeight + Scaler.s(18)
                radius: Scaler.s(10)
                color: VpnService.sbReady ? Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.08) : Qt.alpha(ThemeBackend.red, 0.10)
                border.width: 1
                border.color: VpnService.sbReady ? Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.3) : Qt.alpha(ThemeBackend.red, 0.35)
                ColumnLayout {
                    id: stateCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Scaler.s(10)
                    spacing: Scaler.s(4)
                    Text {
                        Layout.fillWidth: true
                        objectName: "vpnEngineState"
                        text: VpnService.sbReady ? sh.tr("sb.ready", "VPN Engine Ready")
                            : (!sh.tun && sh.enginePath ? sh.tr("sb.broken", "The chosen sing-box does not run: {error}").replace("{error}", sh.info.error || "?")
                                            : sh.tr("sb.not_installed", "VPN components are not installed"))
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: Scaler.s(12)
                        color: VpnAppearance.style.text || "#eef1f6"
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: VpnService.sbReady
                        text: sh.tr("sb.found", "In use: sing-box {version}").replace("{version}", sh.engineVersion || "?")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(11)
                        color: VpnAppearance.style.text || "#eef1f6"
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: sh.enginePath !== ""
                        text: sh.enginePath + "  ·  " + sh.tr("sb.source." + (sh.tun ? "system" : sh.info.source || "system"), "System")
                        elide: Text.ElideMiddle
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.55)
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: sh.tun && !VpnService.sbReady
                        text: sh.info.tunError || ((sh.info.tunPackages || []).length
                            ? sh.tr("sb.tun_missing", "Missing packages: {packages}. Run the offline installer with --system.")
                                .replace("{packages}", sh.info.tunPackages.join(", "))
                            : sh.tr("sb.tun_system", "TUN requires a system sing-box and administrator authorization to install it."))
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: ThemeBackend.yellow
                    }
                }
            }

            VpnSetupProgress { Layout.fillWidth: true; standalone: true; showAnimation: sh.open }

            // offline bundle chosen by hand (no internet needed)
            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(8)
                Text {
                    Layout.fillWidth: true
                    text: VpnService.sbErrorCode.indexOf("sb_bundle") === 0 && !sh.installing
                        ? sh.tr("sb.bundle_pick_hint", "Choose the vpn-bundle folder of this Serpantinum release (for example on a USB stick).")
                        : sh.tr("sb.bundle_pick", "Have the offline VPN bundle? Install from its folder without internet.")
                    wrapMode: Text.Wrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.6)
                }
                VpnPill {
                    objectName: "vpnChooseBundle"
                    text: sh.tr("sb.choose_bundle_short", "Choose folder…")
                    filled: false
                    enabled: !sh.installing && !VpnService.busy && !VpnService.connected
                    onClicked: bundlePicker.open()
                }
            }

            // already on this computer
            Text {
                Layout.fillWidth: true
                text: sh.tr("sb.found_here", "Found on this computer")
                visible: (sh.info.candidates || []).length > 0
                font.family: ThemeBackend.fontFamily
                font.weight: Font.Bold
                font.pixelSize: Scaler.s(11)
                color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.7)
            }
            Repeater {
                model: sh.info.candidates || []
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Scaler.s(8)
                    Text {
                        Layout.fillWidth: true
                        text: parent.modelData.path + (parent.modelData.system ? "  ·  " + sh.tr("sb.system_ok", "works with TUN") : "")
                        elide: Text.ElideMiddle
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(11)
                        color: VpnAppearance.style.text || "#eef1f6"
                    }
                    VpnPill {
                        readonly property bool inUse: sh.info.path === parent.modelData.path
                        text: inUse ? sh.tr("sb.in_use", "In use") : sh.tr("sb.use", "Use")
                        filled: false
                        enabled: !inUse && !VpnService.busy
                        onClicked: VpnService.useSingbox(parent.modelData.path)
                    }
                }
            }

            // a file by path
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Scaler.s(34)
                spacing: Scaler.s(8)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Scaler.s(10)
                    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.06)
                    border.width: 1
                    border.color: pathInput.activeFocus ? Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.7) : Qt.alpha(VpnAppearance.style.border || "#ffffff", 0.12)
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: Scaler.s(10)
                        verticalAlignment: Text.AlignVCenter
                        visible: pathInput.text === ""
                        text: sh.tr("sb.path_placeholder", "Path to a sing-box file, e.g. ~/bin/sing-box")
                        elide: Text.ElideRight
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(11)
                        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.4)
                    }
                    TextInput {
                        id: pathInput
                        anchors.fill: parent
                        anchors.leftMargin: Scaler.s(10)
                        anchors.rightMargin: Scaler.s(10)
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        color: VpnAppearance.style.text || "#eef1f6"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(11)
                        onAccepted: if (text.trim() !== "") VpnService.useSingbox(text.trim())
                    }
                }
                VpnPill {
                    text: sh.tr("sb.use", "Use")
                    filled: false
                    enabled: pathInput.text.trim() !== "" && !VpnService.busy
                    onClicked: VpnService.useSingbox(pathInput.text.trim())
                }
                VpnPill {
                    visible: sh.info.source === "chosen" || sh.info.source === "managed"
                    text: sh.tr("sb.auto", "Automatic")
                    filled: false
                    enabled: !VpnService.busy
                    onClicked: VpnService.useSingbox("")
                }
            }
            Text {
                Layout.fillWidth: true
                visible: VpnService.error !== "" && VpnService.errorAction === "singbox-use"
                text: VpnService.error
                wrapMode: Text.Wrap
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(11)
                color: ThemeBackend.red
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.alpha(VpnAppearance.style.border || "#ffffff", 0.1) }

            VpnPill {
                visible: VpnService.setup.systemInstall === true && VpnService.setup.binaryReady === false
                enabled: !VpnService.sbInstalling && !VpnService.busy && !VpnService.connected
                text: sh.tr("setup.system_package", "Install sing-box RPM via polkit")
                onClicked: VpnService.prepareVpn("", "", "", true, false)
            }
        }
    }
}
