import QtQuick
import QtQuick.Layouts
import "../../"

// sing-box: what is in use, download the official release from GitHub (live progress,
// speed, attempt, Cancel, Retry; checksum from the release's published digest when there
// is one), choose a sing-box already on this computer or a file by path, or install the
// system package with dnf (TUN mode accepts only /usr/bin or /usr/local/bin).
// "Installed" is shown only after the backend ran the new binary (`sing-box version`).
VpnSheet {
    id: sh
    title: "sing-box"
    icon: "󰏗"

    function tr(key, en) { return I18n.t("vpn." + key, en); }
    readonly property var info: VpnService.sbInfo
    readonly property bool installing: VpnService.sbInstalling

    function mb(v) { return (v / 1048576).toFixed(1); }
    readonly property string stageText: {
        switch (VpnService.sbStage) {
        case "release": return tr("sb.stage.release", "Looking up the latest release…");
        case "download": return tr("sb.stage.download", "Downloading…");
        case "verify": return tr("sb.stage.verify", "Checking the checksum…");
        case "extract": return tr("sb.stage.extract", "Unpacking…");
        case "test": return tr("sb.stage.test", "Testing the program…");
        default: return "";
        }
    }
    readonly property string progressText: {
        let parts = [];
        if (VpnService.sbTotal > 0) parts.push(mb(VpnService.sbDone) + " / " + mb(VpnService.sbTotal) + " " + tr("sb.mb", "MB"));
        else if (VpnService.sbDone > 0) parts.push(mb(VpnService.sbDone) + " " + tr("sb.mb", "MB"));
        if (VpnService.sbSpeed > 0) parts.push(mb(VpnService.sbSpeed) + " " + tr("sb.mbps", "MB/s"));
        if (VpnService.sbAttempt > 1) parts.push(tr("sb.attempt", "attempt {n} of 4").replace("{n}", VpnService.sbAttempt));
        return parts.join("  ·  ");
    }

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
                        text: sh.tr("sb.tun_note", "TUN mode uses only a system sing-box (/usr/bin). For TUN, install the package with dnf below.")
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: ThemeBackend.yellow
                    }
                }
            }

            // download
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(6)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Scaler.s(8)
                    Text {
                        Layout.fillWidth: true
                        text: sh.installing ? sh.stageText
                            : VpnService.sbResult
                                ? sh.tr("sb.installed", "Installed sing-box {version}").replace("{version}", VpnService.sbResult.version || "")
                                  + " · " + (VpnService.sbResult.verified ? sh.tr("sb.verified", "checksum verified")
                                                                          : sh.tr("sb.unverified", "no official checksum; checked by running it"))
                            : sh.tr("sb.download_desc", "Download the official release from GitHub (SagerNet/sing-box) for this computer.")
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(11)
                        color: VpnService.sbResult && !sh.installing ? ThemeBackend.green : (VpnAppearance.style.text || "#eef1f6")
                    }
                    VpnPill {
                        visible: !sh.installing
                        icon: "󰇚"
                        text: VpnService.sbError !== "" ? sh.tr("sb.retry", "Retry")
                            : (sh.info.source === "managed" ? sh.tr("sb.update", "Update") : sh.tr("sb.download", "Download"))
                        onClicked: VpnService.installSingbox()
                    }
                    VpnPill {
                        visible: sh.installing
                        text: sh.tr("sb.cancel", "Cancel")
                        accent: ThemeBackend.red
                        filled: false
                        onClicked: VpnService.cancelInstall()
                    }
                }
                Rectangle {                              // progress bar
                    Layout.fillWidth: true
                    Layout.preferredHeight: Scaler.s(6)
                    visible: sh.installing
                    radius: height / 2
                    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.08)
                    Rectangle {
                        height: parent.height
                        radius: height / 2
                        width: VpnService.sbTotal > 0 ? parent.width * Math.min(1, VpnService.sbDone / VpnService.sbTotal) : parent.width * 0.15
                        color: VpnAppearance.style.active || "#7fd4ff"
                        Behavior on width { NumberAnimation { duration: 240 } }
                        // indeterminate: slides while the size is unknown
                        x: VpnService.sbTotal > 0 ? 0 : slide.pos * (parent.width - width)
                        QtObject { id: slide; property real pos: 0 }
                        SequentialAnimation {
                            running: sh.installing && VpnService.sbTotal <= 0 && sh.visible
                            loops: Animation.Infinite
                            NumberAnimation { target: slide; property: "pos"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
                            NumberAnimation { target: slide; property: "pos"; from: 1; to: 0; duration: 900; easing.type: Easing.InOutSine }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: sh.installing && sh.progressText !== ""
                    text: sh.progressText
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.6)
                }
                Text {
                    Layout.fillWidth: true
                    visible: sh.installing && VpnService.sbStage !== "release" && VpnService.sbStage !== ""
                    text: VpnService.sbChecksum ? sh.tr("sb.will_verify", "The archive will be checked against the SHA-256 published with the release.")
                                                : sh.tr("sb.no_digest", "The release has no published checksum: the program is checked by running it.")
                    wrapMode: Text.Wrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(10)
                    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.45)
                }
                Text {
                    Layout.fillWidth: true
                    visible: VpnService.sbError !== "" && !sh.installing
                    text: VpnService.sbError
                    wrapMode: Text.Wrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(11)
                    color: ThemeBackend.red
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Qt.alpha(VpnAppearance.style.border || "#ffffff", 0.1) }

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

            // system package
            Text {
                Layout.fillWidth: true
                text: sh.tr("sb.dnf", "System package (needed for TUN mode), in a terminal:")
                wrapMode: Text.Wrap
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(11)
                color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.7)
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(8)
                Text {
                    Layout.fillWidth: true
                    text: VpnService.installHint
                    wrapMode: Text.WrapAnywhere
                    font.family: "monospace"
                    font.pixelSize: Scaler.s(10)
                    color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.8)
                }
                VpnPill {
                    text: sh.tr("copy", "Copy")
                    filled: false
                    onClicked: VpnService.copyText(VpnService.installHint)
                }
            }
        }
    }
}
