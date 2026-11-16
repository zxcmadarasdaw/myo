import QtQuick
import QtQuick.Layouts
import "../../"

VpnSheet {
    id: sh
    title: "sing-box"
    icon: "󰏗"

    function tr(key, en) { return I18n.t("vpn." + key, en); }
    readonly property var info: VpnService.sbInfo
    property bool inspectTun: false
    readonly property bool tun: inspectTun || VpnService.mode === "tun"
    readonly property bool ready: tun ? info.tunUsable === true : info.works === true
    readonly property string enginePath: (tun ? info.tunPath : info.path) || ""
    readonly property string engineVersion: (tun ? info.tunVersion : info.version) || ""

    onOpenChanged: if (open) VpnService.singboxInfo()

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
                color: sh.ready ? Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.08) : Qt.alpha(ThemeBackend.red, 0.10)
                border.width: 1
                border.color: sh.ready ? Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.3) : Qt.alpha(ThemeBackend.red, 0.35)
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
                        text: sh.ready ? sh.tr("sb.ready", "VPN Engine Ready")
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
                        visible: sh.ready
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
                        visible: sh.tun && !sh.ready
                        text: sh.info.tunError || sh.tr("sb.tun_system", "TUN requires system sing-box and the Serpantinum VPN service.")
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: ThemeBackend.yellow
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: !sh.ready
                spacing: Scaler.s(8)
                Text {
                    Layout.fillWidth: true
                    text: sh.tr("sb.repair_hint", "From the Serpantinum folder, run {command}").replace("{command}", VpnService.installHint)
                    wrapMode: Text.Wrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.6)
                }
                VpnPill {
                    objectName: "vpnCopyRepair"
                    text: sh.tr("sb.copy_command", "Copy command")
                    filled: false
                    onClicked: VpnService.copyText(VpnService.installHint)
                }
            }
            Text {
                Layout.fillWidth: true
                visible: !sh.ready && !!sh.info.componentsLog
                text: sh.tr("setup.log", "Details: {path}").replace("{path}", sh.info.componentsLog || "")
                wrapMode: Text.WrapAnywhere
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(10)
                color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.6)
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

        }
    }
}
