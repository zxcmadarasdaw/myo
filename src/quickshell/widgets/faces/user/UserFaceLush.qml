import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import "../../../reusables"
import "../../../"
import "../common"

// User, Lush: a round avatar inside a glowing gradient halo, a display-set
// greeting with the name, and glass pill power actions (hold to confirm).
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 240
    property real minHeight: 130
    property real maxWidth: 640
    property real maxHeight: 400
    property real minAspect: 1.1
    property real maxAspect: 3.5
    property bool isRound: false

    readonly property FaceTone tone: FaceTone {}
    readonly property real pad: Math.max(Scaler.s(14), Math.min(width, height) * 0.09)
    readonly property bool showActions: height >= Scaler.s(150)
    readonly property string greeting: {
        let h = DateTime.now.getHours();
        if (h < 5) return I18n.t("widgets.user.night", "Good night");
        if (h < 12) return I18n.t("widgets.user.morning", "Good morning");
        if (h < 18) return I18n.t("widgets.user.afternoon", "Good afternoon");
        return I18n.t("widgets.user.evening", "Good evening");
    }

    LushAppear { target: root }

    LushCard { anchors.fill: parent; intensity: 0.7 }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.pad * 0.7

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.pad

            Item {
                id: avatar
                Layout.fillHeight: true
                Layout.preferredWidth: height
                Layout.maximumWidth: Scaler.s(96)
                Layout.maximumHeight: Scaler.s(96)
                readonly property real ringW: Math.max(Scaler.s(2), width * 0.04)

                // gradient halo ring
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.tone.accent }
                        GradientStop { position: 1.0; color: root.tone.accent2 }
                    }
                    layer.enabled: !root.tone.isLight
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: root.tone.accent
                        shadowBlur: 0.7
                        shadowOpacity: 0.6
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                        autoPaddingEnabled: true
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: avatar.ringW
                    radius: width / 2
                    color: ThemeBackend.base
                }
                ImageBox {
                    anchors.fill: parent
                    anchors.margins: avatar.ringW * 2
                    size: Math.min(width, height)
                    cornerRadius: width / 2
                    imageRadius: width / 2
                    source: SystemInfo.avatarPath !== "" ? "file://" + SystemInfo.avatarPath : ""
                    backgroundColor: Qt.alpha(root.tone.accent, 0.18)
                }
                LushGlowText {
                    anchors.centerIn: parent
                    visible: SystemInfo.avatarPath === ""
                    text: String.fromCodePoint(0xF007)
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: parent.height * 0.36
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: root.greeting
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Math.max(Scaler.s(10), Math.min(Scaler.s(13), root.height * 0.08))
                    font.italic: true
                    color: root.tone.muted
                }
                LushGlowText {
                    Layout.fillWidth: true
                    text: SystemInfo.username !== "" ? SystemInfo.username : "user"
                    elide: Text.ElideRight
                    font.pixelSize: Math.max(Scaler.s(16), Math.min(Scaler.s(28), root.height * 0.16))
                    font.weight: Font.DemiBold
                    glowAmount: 0.7
                }
                Text {
                    Layout.fillWidth: true
                    visible: SystemInfo.hostname !== ""
                    text: SystemInfo.hostname + (SystemInfo.uptime !== "" ? "  ·  " + SystemInfo.uptime : "")
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(9)
                    font.letterSpacing: Scaler.s(1)
                    color: root.tone.faint
                }
            }
        }

        RowLayout {
            visible: root.showActions
            Layout.fillWidth: true
            Layout.preferredHeight: Scaler.s(32)
            spacing: Scaler.s(8)

            FaceButton {
                Layout.fillWidth: true
                Layout.fillHeight: true
                lush: true
                text: String.fromCodePoint(0xF023)
                accessibleName: I18n.t("widgets.user.lock", "Lock")
                enabled: !root.previewMode
                onClicked: Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/lock.sh"])
            }
            HoldAction { Layout.fillWidth: true; Layout.fillHeight: true; lush: true; cmd: "sleep"; icon: String.fromCodePoint(0xF04B2); weight: 1.0; color: ThemeBackend.blue; armed: !root.previewMode }
            HoldAction { Layout.fillWidth: true; Layout.fillHeight: true; lush: true; cmd: "reboot"; icon: String.fromCodePoint(0xF0453); weight: 2.0; color: ThemeBackend.peach; armed: !root.previewMode }
            HoldAction { Layout.fillWidth: true; Layout.fillHeight: true; lush: true; cmd: "poweroff"; icon: String.fromCodePoint(0xF011); weight: 3.0; color: ThemeBackend.red; armed: !root.previewMode }
        }
    }
}
