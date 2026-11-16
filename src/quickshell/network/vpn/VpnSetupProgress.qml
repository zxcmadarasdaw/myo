import QtQuick
import QtQuick.Layouts
import "../../"

ColumnLayout {
    id: root
    spacing: Scaler.s(6)

    function tr(key, en) { return I18n.t("vpn." + key, en); }

    readonly property string stageText: {
        switch (VpnService.sbStage) {
        case "system": return tr("setup.check_system", "Checking system…");
        case "binary":
        case "test": return tr("setup.check_binary", "Checking sing-box…");
        case "profile": return tr("setup.read_profile", "Reading VPN profile…");
        case "config": return tr("setup.check_config", "Checking VPN configuration…");
        default: return "";
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: VpnService.sbInstalling || VpnService.sbResult !== null
        Text {
            Layout.fillWidth: true
            text: VpnService.sbInstalling ? root.stageText : root.tr("setup.profile_ready", "VPN profile imported")
            wrapMode: Text.Wrap
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(11)
            color: VpnService.sbInstalling ? (VpnAppearance.style.text || "#eef1f6") : ThemeBackend.green
        }
        VpnPill {
            visible: VpnService.sbCanCancel
            text: root.tr("sb.cancel", "Cancel")
            accent: ThemeBackend.red
            filled: false
            onClicked: VpnService.cancelInstall()
        }
    }
    Text {
        Layout.fillWidth: true
        objectName: "vpnImportError"
        visible: VpnService.sbError !== "" && !VpnService.sbInstalling
        text: VpnService.sbError + (VpnService.sbLogPath !== ""
            ? "\n" + root.tr("setup.log", "Details: {path}").replace("{path}", VpnService.sbLogPath) : "")
        wrapMode: Text.WrapAnywhere
        font.family: ThemeBackend.fontFamily
        font.pixelSize: Scaler.s(11)
        color: ThemeBackend.red
    }
}
