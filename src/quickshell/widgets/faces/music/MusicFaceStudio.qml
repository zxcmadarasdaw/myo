import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../../../"
import "../../../reusables"
import "../../../media"

Item {
    id: root
    anchors.fill: parent
    property bool previewMode: false
    property string musicStyle: "compact"
    property bool musicDrawer: true
    property string musicMaterial: "liquid"
    property bool musicAnimations: true
    property bool musicVisualizer: false
    property real minWidth: 260
    property real minHeight: 140
    property real maxWidth: 800
    property real maxHeight: 360
    property real minAspect: 1.5
    property real maxAspect: 5
    readonly property bool animate: visible && musicAnimations && GpuCompatibility.effective.profile !== "Performance"
    readonly property var player: MprisController.activePlayer
    readonly property var players: Mpris.players.values
    readonly property bool controllable: !previewMode && !!player && player.canControl
    readonly property real duration: player && player.lengthSupported ? Math.max(0, player.length) : 0
    readonly property color accent: musicStyle === "neon" ? ThemeBackend.sky : ThemeBackend.mauve
    function time(seconds) {
        let value = Math.max(0, Math.floor(Number(seconds) || 0));
        return Math.floor(value/60) + ":" + (value%60 < 10 ? "0" : "") + value%60;
    }
    Rectangle {
        anchors.fill: parent
        radius: root.musicStyle === "floating" ? Math.min(36,height/3) : ThemeBackend.borderRadius
        color: Qt.alpha(ThemeBackend.base, root.musicStyle === "minimal" || root.musicMaterial === "minimal" ? 0.98 : ThemeBackend.elementOpacity)
        border.width: root.musicStyle === "minimal" ? 44 : 1
        border.color: Qt.alpha(root.accent, root.musicStyle === "neon" ? 0.8 : 0.28)
        GlassFill { anchors.fill: parent; radius: parent.radius; allowed: root.musicStyle !== "minimal" && root.musicMaterial !== "minimal" && root.musicMaterial !== "mica"; tintColor: ThemeBackend.base }
        WallpaperBlur { anchors.fill: parent; z: -1; radius: parent.radius; visible: root.musicStyle !== "minimal" && root.musicMaterial !== "minimal" && GpuCompatibility.blurAllowed }
    }
    Image {
        anchors.fill: parent; anchors.margins: 5
        visible: root.musicStyle === "album"
        source: MprisController.artUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; clip: true; opacity: 0.18
    }
    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 12
        Item {
            Layout.preferredWidth: root.musicStyle === "minimal" ? 44 : Math.min(100, root.height-30)
            Layout.fillHeight: true
            visible: true
            Rectangle {
                id: cover
                anchors.centerIn: parent
                width: parent.width; height: width
                radius: root.musicStyle === "vinyl" ? width/2 : 10
                color: ThemeBackend.surface0
                border.color: Qt.alpha(root.accent,0.4)
                clip: true
                Text { anchors.centerIn: parent; text: "♫"; color: root.accent; font.pixelSize: 32 }
                Image {
                    id: art
                    objectName: "albumArt"
                    anchors.fill: parent
                    anchors.margins: root.musicStyle === "vinyl" ? parent.width*0.22 : 3
                    source: MprisController.artUrl
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: root.animate ? 240 : 0 } }
                    onSourceChanged: if (root.animate) coverFade.restart()
                    SequentialAnimation {
                        id: coverFade
                        NumberAnimation { target: art; property: "scale"; from: 0.92; to: 1; duration: 240; easing.type: Easing.OutCubic }
                    }
                }
                Rectangle { visible: root.musicStyle === "vinyl"; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: ThemeBackend.base }
                RotationAnimator on rotation { from: 0; to: 360; duration: 18000; loops: Animation.Infinite; running: root.animate && root.musicStyle === "vinyl" && MprisController.isPlaying }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    objectName: "trackTitle"
                    text: root.player ? (MprisController.trackTitle || "Неизвестный трек") : "Нет активного плеера"
                    color: ThemeBackend.text; font.family: ThemeBackend.fontFamily; font.bold: true; font.pixelSize: 14
                    elide: Text.ElideRight
                }
                StudioComboBox {
                    objectName: "playerSelector"
                    Layout.preferredWidth: 76
                    implicitHeight: 26
                    model: ["Auto"].concat(root.players.map(p => p.identity || p.dbusName))
                    currentIndex: MprisController.selectedBus === "" ? 0 : Math.max(0, root.players.findIndex(p => p.dbusName === MprisController.selectedBus)+1)
                    onActivated: index => MprisController.selectedBus = index > 0 ? root.players[index-1].dbusName : ""
                    enabled: !root.previewMode
                    Accessible.name: "Активный плеер"
                }
            }
            Text { Layout.fillWidth: true; text: root.player ? (MprisController.trackArtist || "Неизвестный исполнитель") : "Откройте музыкальное приложение"; elide: Text.ElideRight; color: ThemeBackend.subtext0; font.pixelSize: 11 }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                StudioButton { objectName: "previousTrack"; text: "⏮"; implicitWidth: 36; implicitHeight: 28; enabled: root.controllable && root.player.canGoPrevious; onClicked: root.player.previous(); Accessible.name: "Предыдущий трек" }
                StudioButton { objectName: "playPause"; text: MprisController.isPlaying ? "Ⅱ" : "▶"; implicitWidth: 42; implicitHeight: 28; enabled: root.controllable && (MprisController.isPlaying ? root.player.canPause : root.player.canPlay); onClicked: { if (MprisController.isPlaying) root.player.pause(); else root.player.play(); } Accessible.name: "Воспроизведение / пауза" }
                StudioButton { objectName: "nextTrack"; text: "⏭"; implicitWidth: 36; implicitHeight: 28; enabled: root.controllable && root.player.canGoNext; onClicked: root.player.next(); Accessible.name: "Следующий трек" }
                Item { Layout.fillWidth: true }
            }
            StudioSlider {
                objectName: "trackSeek"
                Layout.fillWidth: true; Layout.preferredHeight: 18
                from: 0; to: Math.max(1, root.duration)
                value: Math.min(root.duration, MprisController.livePosition)
                enabled: root.controllable && root.player.canSeek && root.player.positionSupported && root.duration > 0
                onMoved: root.player.position = value
                animate: root.animate; accent: root.accent
                Accessible.name: "Позиция воспроизведения"
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: root.player && root.player.positionSupported ? root.time(MprisController.livePosition) : "—:—"; color: ThemeBackend.subtext0; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
                Text { text: root.duration > 0 ? root.time(root.duration) : "—:—"; color: ThemeBackend.subtext0; font.pixelSize: 10 }
            }
        }
    }
}
