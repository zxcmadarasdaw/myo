import QtQuick
import QtQuick.Layouts
import "../../"

// A panel that slides up over the VPN page (server picker, subscriptions, connection,
// sing-box). While closed it is invisible AND disabled, so neither the scrim nor the
// panel can take a click; the scrim exists only while the sheet is open.
Item {
    id: sheet

    property bool open: false
    property string title: ""
    property string icon: ""
    property real panelHeight: height * 0.86
    default property alias content: body.data
    property alias headerExtra: extra.data
    signal closeRequested()

    anchors.fill: parent
    z: 40
    property real prog: open ? 1.0 : 0.0
    Behavior on prog { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    visible: prog > 0.01
    enabled: open

    MouseArea {                                   // scrim: a click outside closes
        anchors.fill: parent
        enabled: sheet.open
        hoverEnabled: true
        onClicked: sheet.closeRequested()
        onWheel: (wheel) => { wheel.accepted = true; }
        Rectangle {
            anchors.fill: parent
            radius: VpnAppearance.style.radius || 20
            color: Qt.alpha("#000000", 0.35 * sheet.prog)
        }
    }

    Item {
        id: panel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Scaler.s(10)
        height: Math.min(sheet.panelHeight, sheet.height - Scaler.s(20))
        y: sheet.height - height - Scaler.s(10) + (1 - sheet.prog) * Scaler.s(28)
        opacity: sheet.prog

        VpnMaterial {
            anchors.fill: parent
            strength: 1.25
        }
        MouseArea {                               // the panel itself swallows clicks
            anchors.fill: parent
            hoverEnabled: true
            onWheel: (wheel) => { wheel.accepted = false; }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Scaler.s(14)
            spacing: Scaler.s(10)

            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(8)
                Text {
                    visible: sheet.icon !== ""
                    text: sheet.icon
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: Scaler.s(16)
                    color: VpnAppearance.style.active || "#7fd4ff"
                }
                Text {
                    Layout.fillWidth: true
                    text: sheet.title
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.weight: Font.Bold
                    font.pixelSize: Scaler.s(14)
                    font.letterSpacing: VpnAppearance.letterSpacing * 0.5
                    color: VpnAppearance.style.text || "#eef1f6"
                }
                RowLayout { id: extra; spacing: Scaler.s(6) }
                VpnIconButton {
                    icon: "󰅖"
                    tip: I18n.t("vpn.close", "Close")
                    onClicked: sheet.closeRequested()
                }
            }

            Item {
                id: body
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
