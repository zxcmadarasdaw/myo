import QtQuick
import QtQuick.Layouts
import "../../"

ColumnLayout {
    id: sh
    property bool standalone: false
    property bool showAnimation: false
    readonly property bool installing: VpnService.sbInstalling
    readonly property bool measured: VpnService.sbStage === "download" && VpnService.sbTotal > 0

    function tr(key, en) { return I18n.t("vpn." + key, en); }
    function mb(v) { return (v / 1048576).toFixed(1); }
    readonly property string stageText: {
        switch (VpnService.sbStage) {
        case "system": return tr("setup.check_system", "Checking system…");
        case "binary": return tr("setup.check_binary", "Checking sing-box…");
        case "profile": return tr("setup.read_profile", "Reading VPN profile…");
        case "packages": return tr("setup.wait_auth", "Waiting for the administrator password (polkit window)…");
        case "transaction": return tr("setup.transaction", "Installing signed RPM packages (cannot be cancelled now)…");
        case "config": return tr("setup.check_config", "Checking VPN configuration…");
        case "bundle": return tr("sb.stage.bundle", "Reading the offline VPN bundle (no internet)…");
        case "release": return tr("sb.stage.release", "Looking up the latest release…");
        case "download": return tr("sb.stage.download", "Downloading…");
        case "verify": return tr("sb.stage.verify", "Checking the checksum…");
        case "extract": return tr("sb.stage.extract", "Unpacking…");
        case "test": return tr("sb.stage.test", "Testing the program…");
        default: return "";
        }
    }
    readonly property string resultText: VpnService.sbSetup ? tr("setup.done", "VPN setup complete")
        : tr("sb.installed", "Installed sing-box {version}").replace("{version}", (VpnService.sbResult || {}).version || "")
    readonly property bool timed: ["packages", "transaction"].indexOf(VpnService.sbStage) >= 0 && VpnService.sbElapsed > 0
    readonly property string progressText: {
        let parts = [];
        if (timed) return tr("setup.elapsed", "{seconds} s").replace("{seconds}", VpnService.sbElapsed)
            + (VpnService.sbStage === "packages" ? "  ·  " + tr("setup.auth_limit", "stops after 3 min without an answer") : "");
        if (VpnService.sbTotal > 0) parts.push(mb(VpnService.sbDone) + " / " + mb(VpnService.sbTotal) + " " + tr("sb.mb", "MB"));
        else if (VpnService.sbDone > 0) parts.push(mb(VpnService.sbDone) + " " + tr("sb.mb", "MB"));
        if (VpnService.sbSpeed > 0) parts.push(mb(VpnService.sbSpeed) + " " + tr("sb.mbps", "MB/s"));
        if (VpnService.sbAttempt > 1) parts.push(tr("sb.attempt", "attempt {n} of 4").replace("{n}", VpnService.sbAttempt));
        if (VpnService.sbRetryWait > 0)
            parts.push(tr("setup.retry_wait", "Retry in {seconds} s").replace("{seconds}", VpnService.sbRetryWait)
                       + " (" + VpnService.sbRetryDetail + ")");
        return parts.join("  ·  ");
    }

    spacing: Scaler.s(6)
    RowLayout {
        Layout.fillWidth: true
        spacing: Scaler.s(8)
        Text {
            Layout.fillWidth: true
            visible: sh.installing || VpnService.sbResult !== null || sh.standalone
            text: sh.installing ? sh.stageText : VpnService.sbResult ? sh.resultText
                : VpnService.sbBundleFound
                    ? sh.tr("sb.bundle_found", "Offline bundle found: sing-box {version}. It installs without internet.").replace("{version}", VpnService.sbInfo.bundle.version || "")
                    : sh.tr("sb.download_desc", "Download the official release from GitHub (SagerNet/sing-box) for this computer.")
            wrapMode: Text.Wrap
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(11)
            color: VpnService.sbResult && !sh.installing ? ThemeBackend.green : (VpnAppearance.style.text || "#eef1f6")
        }
        VpnPill {                            // local install from the offline bundle: no network
            objectName: "vpnInstallBundle"
            visible: sh.standalone && !sh.installing && VpnService.sbBundleFound
                     && (!VpnService.sbReady || VpnService.sbInfo.version !== VpnService.sbInfo.bundle.version)
            icon: "󰏗"
            text: sh.tr("sb.install_components", "Install VPN Components")
            enabled: !VpnService.busy && !VpnService.connected
            onClicked: VpnService.installSingbox("bundle", "")
        }
        VpnPill {                            // download from GitHub (needs internet)
            objectName: "vpnDownload"
            visible: sh.standalone && !sh.installing
            icon: "󰇚"
            filled: !VpnService.sbBundleFound
            text: VpnService.sbError !== "" && VpnService.sbErrorCode.indexOf("sb_bundle") !== 0 ? sh.tr("sb.retry", "Retry")
                : (VpnService.sbInfo.source === "managed" ? sh.tr("sb.update", "Update") : sh.tr("sb.download", "Download"))
            enabled: !VpnService.busy && !VpnService.connected
            onClicked: VpnService.installSingbox("online", "")
        }
        VpnPill {
            visible: VpnService.sbCanCancel
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
            width: sh.measured ? parent.width * Math.min(1, VpnService.sbDone / VpnService.sbTotal) : parent.width * 0.15
            color: VpnAppearance.style.active || "#7fd4ff"
            Behavior on width { NumberAnimation { duration: 240 } }
            // indeterminate: slides while the size is unknown
            x: sh.measured ? 0 : slide.pos * (parent.width - width)
            QtObject { id: slide; property real pos: 0 }
            SequentialAnimation {
                running: sh.installing && !sh.measured && sh.showAnimation
                loops: Animation.Infinite
                NumberAnimation { target: slide; property: "pos"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { target: slide; property: "pos"; from: 1; to: 0; duration: 900; easing.type: Easing.InOutSine }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: sh.installing && (VpnService.sbStage === "download" || sh.timed) && sh.progressText !== ""
        text: sh.progressText
        wrapMode: Text.WrapAnywhere
        font.family: ThemeBackend.fontFamily
        font.pixelSize: Scaler.s(10)
        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.6)
    }
    Text {
        Layout.fillWidth: true
        visible: sh.installing && VpnService.sbStage === "download" && VpnService.sbChecksum
        text: sh.tr("sb.will_verify", "The archive will be checked against the SHA-256 published with the release.")
        wrapMode: Text.WrapAnywhere
        font.family: ThemeBackend.fontFamily
        font.pixelSize: Scaler.s(10)
        color: Qt.alpha(VpnAppearance.style.text || "#ffffff", 0.45)
    }
    Text {
        Layout.fillWidth: true
        objectName: "vpnInstallError"
        visible: VpnService.sbError !== "" && !sh.installing
        text: VpnService.sbError + (VpnService.sbLogPath !== ""
            ? "\n" + sh.tr("setup.log", "Details: {path}").replace("{path}", VpnService.sbLogPath) : "")
        wrapMode: Text.WrapAnywhere
        font.family: ThemeBackend.fontFamily
        font.pixelSize: Scaler.s(11)
        color: ThemeBackend.red
    }
}
