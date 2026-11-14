import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../../../"
import "../../../reusables"
import "../common"

// Music, Lush: the album art blurred into the glass as a backdrop, a cover
// with a glow, display-set title, pill controls and a gradient progress bar.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    // shared music settings (read by the Audio Studio drawer)
    property bool musicDrawer: true
    property string musicMaterial: "liquid"
    property bool musicAnimations: true
    property bool musicVisualizer: false

    property real minWidth: 260
    property real minHeight: 110
    property real maxWidth: 900
    property real maxHeight: 400
    property real minAspect: 1.5
    property real maxAspect: 5.0
    property bool isRound: false

    readonly property FaceTone tone: FaceTone {}
    readonly property var player: MprisController.activePlayer
    readonly property bool controllable: !previewMode && !!player && player.canControl
    readonly property real duration: player && player.lengthSupported ? Math.max(0, player.length) : 0
    readonly property bool animate: visible && musicAnimations && GpuCompatibility.effective.profile !== "Performance"
    readonly property real pad: Math.max(Scaler.s(14), Math.min(width, height) * 0.11)
    readonly property bool hasArt: backdropArt.status === Image.Ready

    function time(seconds) {
        let value = Math.max(0, Math.floor(Number(seconds) || 0));
        return Math.floor(value / 60) + ":" + (value % 60 < 10 ? "0" : "") + value % 60;
    }

    LushAppear { target: root }

    LushCard {
        id: card
        anchors.fill: parent
        intensity: MprisController.isPlaying ? 0.85 : 0.5
    }

    // blurred cover as a backdrop, masked to the card
    Rectangle {
        id: backdropMask
        anchors.fill: parent
        radius: card.radius
        visible: false
        layer.enabled: true
    }
    Image {
        id: backdropArt
        anchors.fill: parent
        source: MprisController.artUrl
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: parent
        source: backdropArt
        visible: root.hasArt
        opacity: root.tone.isLight ? 0.22 : 0.32
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        saturation: 0.2
        maskEnabled: true
        maskSource: backdropMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.pad

        Item {
            Layout.fillHeight: true
            Layout.preferredWidth: height
            Layout.maximumWidth: root.width * 0.38

            Rectangle {
                id: coverMask
                anchors.fill: parent
                radius: Math.max(Scaler.s(8), card.radius * 0.6)
                visible: false
                layer.enabled: true
            }
            Rectangle {
                anchors.fill: parent
                radius: coverMask.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.alpha(root.tone.accent, 0.35) }
                    GradientStop { position: 1; color: Qt.alpha(root.tone.accent2, 0.25) }
                }
                LushGlowText { anchors.centerIn: parent; text: "♫"; font.pixelSize: parent.height * 0.4 }
            }
            Image {
                id: cover
                anchors.fill: parent
                source: MprisController.artUrl
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                visible: false
                layer.enabled: true
            }
            MultiEffect {
                anchors.fill: parent
                source: cover
                visible: cover.status === Image.Ready
                maskEnabled: true
                maskSource: coverMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
                shadowEnabled: true
                shadowColor: root.tone.isLight ? "#000000" : root.tone.accent
                shadowBlur: 0.8
                shadowOpacity: root.tone.isLight ? 0.25 : 0.55
                autoPaddingEnabled: true
                opacity: cover.status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: root.animate ? 360 : 0; easing.type: Easing.OutCubic } }
            }
            Rectangle {
                anchors.fill: parent
                radius: coverMask.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(root.tone.sheen, root.tone.isLight ? 0.6 : 0.18)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Scaler.s(2)

            LushGlowText {
                Layout.fillWidth: true
                text: root.player ? (MprisController.trackTitle || I18n.t("widgets.music.unknownTrack", "Unknown track")) : I18n.t("widgets.music.noPlayer", "Nothing playing")
                elide: Text.ElideRight
                font.pixelSize: Math.max(Scaler.s(13), Math.min(Scaler.s(20), root.height * 0.13))
                font.weight: Font.DemiBold
                glowAmount: 0.6
            }
            Text {
                Layout.fillWidth: true
                text: root.player ? (MprisController.trackArtist || "") : ""
                visible: text !== ""
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Math.max(Scaler.s(10), Math.min(Scaler.s(13), root.height * 0.09))
                font.italic: true
                color: root.tone.muted
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Scaler.s(6)
                visible: root.height >= Scaler.s(130)
                FaceButton {
                    lush: true; text: "⏮"; iconFont: ThemeBackend.fontFamily
                    implicitWidth: Scaler.s(36); implicitHeight: Scaler.s(30)
                    accessibleName: I18n.t("widgets.music.previous", "Previous track")
                    enabled: root.controllable && root.player.canGoPrevious
                    onClicked: root.player.previous()
                }
                FaceButton {
                    lush: true; primary: true; text: MprisController.isPlaying ? "Ⅱ" : "▶"; iconFont: ThemeBackend.fontFamily
                    implicitWidth: Scaler.s(48); implicitHeight: Scaler.s(30)
                    accessibleName: I18n.t("widgets.music.playPause", "Play / pause")
                    enabled: root.controllable && (MprisController.isPlaying ? root.player.canPause : root.player.canPlay)
                    onClicked: MprisController.isPlaying ? root.player.pause() : root.player.play()
                }
                FaceButton {
                    lush: true; text: "⏭"; iconFont: ThemeBackend.fontFamily
                    implicitWidth: Scaler.s(36); implicitHeight: Scaler.s(30)
                    accessibleName: I18n.t("widgets.music.next", "Next track")
                    enabled: root.controllable && root.player.canGoNext
                    onClicked: root.player.next()
                }
                Item { Layout.fillWidth: true }
            }

            LushMeter {
                Layout.fillWidth: true
                Layout.preferredHeight: Scaler.s(6)
                value: root.duration > 0 ? MprisController.livePosition / root.duration : 0
            }
            RowLayout {
                Layout.fillWidth: true
                visible: root.height >= Scaler.s(150)
                Text { text: root.player && root.player.positionSupported ? root.time(MprisController.livePosition) : "—:—"; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(9); color: root.tone.faint }
                Item { Layout.fillWidth: true }
                Text { text: root.duration > 0 ? root.time(root.duration) : "—:—"; font.family: ThemeBackend.fontFamily; font.pixelSize: Scaler.s(9); color: root.tone.faint }
            }
        }
    }
}
