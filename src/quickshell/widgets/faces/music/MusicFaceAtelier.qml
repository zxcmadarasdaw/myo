import QtQuick
import QtQuick.Layouts
import "../../../"
import "../../../reusables"
import "../common"

// Music, Atelier: cover, title, artist, transport and progress from MprisController,
// exactly like the other music faces. Only the arrangement and type change with the look.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property string faceStyle: "matte"
    // shared music settings (read by the Audio Studio drawer)
    property bool musicDrawer: true
    property string musicMaterial: "minimal"
    property bool musicAnimations: true
    property bool musicVisualizer: false

    property real minWidth: 220
    property real minHeight: 64
    property real maxWidth: 1400
    property real maxHeight: 500
    property real minAspect: 1.4
    property real maxAspect: 9.0
    property bool isRound: false

    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }

    readonly property string look: kit.styleId
    readonly property var player: MprisController.activePlayer
    readonly property bool controllable: !previewMode && !!player && player.canControl
    readonly property real duration: player && player.lengthSupported ? Math.max(0, player.length) : 0
    readonly property real position: Math.max(0, MprisController.livePosition || 0)
    readonly property bool compact: look === "compact" || height < Scaler.s(100)
    readonly property bool showTimes: (look === "technical" || look === "retro" || look === "premium") && duration > 0

    function clock(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60);
    }

    AtelierCard {
        id: card
        kit: kit
        title: MprisController.isPlaying ? I18n.t("widgets.music.nowPlaying", "Now playing") : I18n.t("widgets.types.music", "Music")
        detail: root.player && root.player.identity ? root.player.identity : ""
        showHeader: kit.hasHeader && !root.compact
    }

    RowLayout {
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        spacing: Scaler.s(root.compact ? 10 : 14)

        Item {
            visible: card.contentWidth >= Scaler.s(200)
            Layout.fillHeight: true
            Layout.preferredWidth: Math.min(card.contentHeight, card.contentWidth * 0.4)

            Rectangle {
                anchors.fill: parent
                radius: root.look === "retro" || root.look === "technical" || root.look === "editorial" ? 0
                        : Math.min(kit.radius * 0.7, Scaler.s(12))
                color: Qt.alpha(ThemeBackend.text, 0.05)
                border.width: 1
                border.color: root.look === "retro" ? Qt.alpha(kit.accent, 0.6) : kit.hair
                Text { anchors.centerIn: parent; text: "♪"; color: kit.faint; font.pixelSize: parent.height * 0.35 }
            }
            Image {
                anchors.fill: parent
                anchors.margins: 1
                source: MprisController.artUrl
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(256, 256)
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: kit.duration(260); easing.type: Easing.OutCubic } }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Scaler.s(2)

            Text {
                Layout.fillWidth: true
                text: root.player ? (MprisController.trackTitle || I18n.t("widgets.music.unknownTrack", "Unknown track"))
                                  : I18n.t("widgets.music.noPlayer", "Nothing playing")
                elide: Text.ElideRight
                font.family: root.look === "elegant" || root.look === "editorial" ? kit.serif
                             : root.look === "retro" || root.look === "technical" ? kit.mono : kit.sans
                font.italic: root.look === "elegant"
                font.weight: root.look === "editorial" ? Font.DemiBold : Font.Medium
                font.pixelSize: Math.max(Scaler.s(12), Math.min(Scaler.s(root.look === "premium" || root.look === "editorial" ? 22 : 16), root.height * 0.14))
                color: kit.ink
            }
            Text {
                Layout.fillWidth: true
                text: root.player ? (MprisController.trackArtist || "") : ""
                visible: text !== ""
                elide: Text.ElideRight
                font.family: kit.labelFamily
                font.pixelSize: Math.max(Scaler.s(10), Math.min(Scaler.s(13), root.height * 0.1))
                font.letterSpacing: root.look === "editorial" ? kit.tracking : 0
                color: root.look === "editorial" ? kit.accent : kit.muted
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Scaler.s(4)
                FaceButton {
                    text: "⏮"; iconFont: ThemeBackend.fontFamily
                    lush: root.look === "premium"
                    accessibleName: I18n.t("widgets.music.previous", "Previous track")
                    enabled: root.controllable && root.player.canGoPrevious
                    onClicked: root.player.previous()
                }
                FaceButton {
                    text: MprisController.isPlaying ? "Ⅱ" : "▶"; iconFont: ThemeBackend.fontFamily
                    primary: true
                    lush: root.look === "premium"
                    accent: kit.accent
                    accessibleName: I18n.t("widgets.music.playPause", "Play / pause")
                    enabled: root.controllable && (MprisController.isPlaying ? root.player.canPause : root.player.canPlay)
                    onClicked: MprisController.isPlaying ? root.player.pause() : root.player.play()
                }
                FaceButton {
                    text: "⏭"; iconFont: ThemeBackend.fontFamily
                    lush: root.look === "premium"
                    accessibleName: I18n.t("widgets.music.next", "Next track")
                    enabled: root.controllable && root.player.canGoNext
                    onClicked: root.player.next()
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: root.showTimes
                    text: root.clock(root.position) + " / " + root.clock(root.duration)
                    font.family: kit.mono
                    font.pixelSize: Scaler.s(10)
                    color: kit.faint
                }
            }

            AtelierMeter {
                kit: kit
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                kind: kit.t.meter === "bar" ? "line" : kit.t.meter
                value: root.duration > 0 ? root.position / root.duration : 0
                color: kit.accent
            }
        }
    }
}
