import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../reusables"
import "../../../"
import "../common"

// User, Restrained: a square avatar with a hairline, name and host in plain
// type, and a row of outline power actions that must be held to confirm.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property real minWidth: 200
    property real minHeight: 100
    property real maxWidth: 600
    property real maxHeight: 360
    property real minAspect: 1.1
    property real maxAspect: 4.0
    property bool isRound: false

    readonly property FaceTone tone: FaceTone {}
    readonly property real pad: Math.max(Scaler.s(10), Math.min(width, height) * 0.09)
    readonly property bool showActions: height >= Scaler.s(120)

    MinimalAppear { target: root }

    MinimalCard { anchors.fill: parent }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.pad * 0.8

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.pad

            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: height
                Layout.maximumWidth: Scaler.s(80)
                Layout.maximumHeight: Scaler.s(80)
                ImageBox {
                    anchors.fill: parent
                    size: Math.min(parent.width, parent.height)
                    cornerRadius: Math.min(Scaler.s(3), ThemeBackend.clampedBorderRadius)
                    imageRadius: cornerRadius
                    source: SystemInfo.avatarPath !== "" ? "file://" + SystemInfo.avatarPath : ""
                    backgroundColor: Qt.alpha(ThemeBackend.text, 0.04)
                    borderColor: root.tone.hairline
                    borderWidth: 1
                }
                Text {
                    anchors.centerIn: parent
                    visible: SystemInfo.avatarPath === ""
                    text: String.fromCodePoint(0xF007)
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: parent.height * 0.4
                    color: root.tone.faint
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Scaler.s(2)
                Text {
                    Layout.fillWidth: true
                    text: SystemInfo.username !== "" ? SystemInfo.username : "user"
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Math.max(Scaler.s(13), Math.min(Scaler.s(20), root.height * 0.14))
                    font.weight: Font.Light
                    color: root.tone.ink
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: SystemInfo.hostname !== "" ? ("@" + SystemInfo.hostname).toUpperCase() : ""
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(9)
                    font.letterSpacing: Scaler.s(1.5)
                    color: root.tone.muted
                }
                Text {
                    Layout.fillWidth: true
                    visible: SystemInfo.uptime !== "" && root.height >= Scaler.s(140)
                    text: SystemInfo.uptime
                    elide: Text.ElideRight
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(9)
                    color: root.tone.faint
                }
            }
        }

        Rectangle {
            visible: root.showActions
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.tone.hairline
        }

        RowLayout {
            visible: root.showActions
            Layout.fillWidth: true
            Layout.preferredHeight: Scaler.s(30)
            spacing: Scaler.s(6)

            FaceButton {
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: String.fromCodePoint(0xF023)
                accessibleName: I18n.t("widgets.user.lock", "Lock")
                enabled: !root.previewMode
                onClicked: Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/lock.sh"])
            }
            HoldAction { Layout.fillWidth: true; Layout.fillHeight: true; cmd: "sleep"; icon: String.fromCodePoint(0xF04B2); weight: 1.0; color: ThemeBackend.blue; armed: !root.previewMode }
            HoldAction { Layout.fillWidth: true; Layout.fillHeight: true; cmd: "reboot"; icon: String.fromCodePoint(0xF0453); weight: 2.0; color: ThemeBackend.peach; armed: !root.previewMode }
            HoldAction { Layout.fillWidth: true; Layout.fillHeight: true; cmd: "poweroff"; icon: String.fromCodePoint(0xF011); weight: 3.0; color: ThemeBackend.red; armed: !root.previewMode }
        }
    }
}
