import QtQuick
import QtQuick.Layouts
import "../../../"
import "../../../reusables"
import "../common"

// Music, Restrained: a small square cover with a hairline, title and
// artist, three quiet controls and a 1 px progress line.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    // shared music settings (read by the Audio Studio drawer)
    property bool musicDrawer: true
    property string musicMaterial: "liquid"
    property bool musicAnimations: true
    property bool musicVisualizer: false

    property real minWidth: 200
    property real minHeight: 64
    property real maxWidth: 900
    property real maxHeight: 300
    property real minAspect: 1.6
    property real maxAspect: 7.0
    property bool isRound: false

    readonly property FaceTone tone: FaceTone {}
    readonly property var player: MprisController.activePlayer
    readonly property bool controllable: !previewMode && !!player && player.canControl
    readonly property real duration: player && player.lengthSupported ? Math.max(0, player.length) : 0
    readonly property real pad: Math.max(Scaler.s(8), Math.min(width, height) * 0.12)
    readonly property bool showArt: height >= Scaler.s(70) && width >= Scaler.s(240)
    readonly property bool showControls: height >= Scaler.s(90)

    MinimalAppear { target: root }

    MinimalCard { anchors.fill: parent }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.pad

        Item {
            visible: root.showArt
            Layout.fillHeight: true
            Layout.preferredWidth: height

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(ThemeBackend.text, 0.04)
                border.width: 1
                border.color: root.tone.hairline
                radius: Math.min(Scaler.s(2), ThemeBackend.clampedBorderRadius)
                Text { anchors.centerIn: parent; text: "♪"; color: root.tone.faint; font.pixelSize: parent.height * 0.35 }
            }
            Image {
                anchors.fill: parent
                anchors.margins: 1
                source: MprisController.artUrl
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: root.musicAnimations ? 240 : 0; easing.type: Easing.OutCubic } }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Scaler.s(2)

            Text {
                Layout.fillWidth: true
                text: root.player ? (MprisController.trackTitle || I18n.t("widgets.music.unknownTrack", "Unknown track")) : I18n.t("widgets.music.noPlayer", "Nothing playing")
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(11), Math.min(Scaler.s(15), root.height * 0.15))
                color: root.tone.ink
            }
            Text {
                Layout.fillWidth: true
                text: root.player ? (MprisController.trackArtist || "") : ""
                visible: text !== ""
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(9), Math.min(Scaler.s(12), root.height * 0.11))
                color: root.tone.muted
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                visible: root.showControls
                Layout.fillWidth: true
                spacing: Scaler.s(2)
                FaceButton {
                    text: "⏮"; iconFont: ThemeBackend.fontFamily
                    accessibleName: I18n.t("widgets.music.previous", "Previous track")
                    enabled: root.controllable && root.player.canGoPrevious
                    onClicked: root.player.previous()
                }
                FaceButton {
                    text: MprisController.isPlaying ? "Ⅱ" : "▶"; iconFont: ThemeBackend.fontFamily
                    primary: true
                    accessibleName: I18n.t("widgets.music.playPause", "Play / pause")
                    enabled: root.controllable && (MprisController.isPlaying ? root.player.canPause : root.player.canPlay)
                    onClicked: MprisController.isPlaying ? root.player.pause() : root.player.play()
                }
                FaceButton {
                    text: "⏭"; iconFont: ThemeBackend.fontFamily
                    accessibleName: I18n.t("widgets.music.next", "Next track")
                    enabled: root.controllable && root.player.canGoNext
                    onClicked: root.player.next()
                }
                Item { Layout.fillWidth: true }
            }

            MinimalMeter {
                Layout.fillWidth: true
                Layout.preferredHeight: Scaler.s(2)
                value: root.duration > 0 ? MprisController.livePosition / root.duration : 0
            }
        }
    }
}
