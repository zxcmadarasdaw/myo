import QtQuick
import QtQuick.Layouts
import "../../"

VpnSheet {
    id: sh
    title: "sing-box"
    icon: "󰏗"

    function tr(key, en) { return I18n.t("vpn." + key, en); }
    readonly property var info: VpnService.sbInfo
    readonly property bool installing: VpnService.sbInstalling

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
                color: sh.info.works ? Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.08) : Qt.alpha(ThemeBackend.red, 0.10)
                border.width: 1
                border.color: sh.info.works ? Qt.alpha(VpnAppearance.style.active || "#7fd4ff", 0.3) : Qt.alpha(ThemeBackend.red, 0.35)
                ColumnLayout {
                    id: stateCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Scaler.s(10)
                    spacing: Scaler.s(4)
                    Text {
                        Layout.fillWidth: true
                        text: sh.info.works
                            ? sh.tr("sb.found", "In use: sing-box {version}").replace("{version}", sh.info.version || "?")
                            : (sh.info.path ? sh.tr("sb.broken", "The chosen sing-box does not run: {error}").replace("{error}", sh.info.error || "?")
                                            : sh.tr("sb.none", "sing-box was not found on this computer."))
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.weight: Font.Bold
                        font.pixelSize: Scaler.s(12)
                        color: VpnAppearance.style.text || "#eef1f6"
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: (sh.info.path || "") !== ""
                        text: (sh.info.path || "") + "  ·  " + sh.tr("sb.source." + (sh.info.source || "system"), sh.info.source || "")
                        elide: Text.ElideMiddle
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.55)
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: sh.info.works === true && sh.info.tunUsable === false
                        text: sh.tr("setup.tun_rpm", "TUN uses the system sing-box RPM.")
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: ThemeBackend.yellow
                    }
                }
            }

            VpnSetupProgress { Layout.fillWidth: true; standalone: true; showAnimation: sh.open }

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
