import QtQuick
import QtQuick.Effects
import QtMultimedia
import "../../../"

Item {
    id: root
    required property bool active
    property bool obscured: false
    property bool preview: false
    readonly property bool ready: mediaWidth >= 40 && mediaHeight >= 40 && decoder.item?.ready === true
    readonly property bool failed: decoder.item?.failed === true
    readonly property bool vertical: FastfetchMedia.layout === "vertical" || width < 300
    readonly property real gap: FastfetchMedia.style.gap
    readonly property real mediaWidth: vertical
        ? Math.min(width, width * FastfetchMedia.mediaWidth / 100)
        : Math.min(Math.max(0, width - 154 - gap), width * FastfetchMedia.mediaWidth / 100)
    readonly property real mediaHeight: vertical
        ? Math.min(Math.max(0, height - 57 - gap), height * FastfetchMedia.mediaHeight / 100)
        : height * FastfetchMedia.mediaHeight / 100
    readonly property real leadingSpace: ready && !vertical ? mediaWidth + gap : 0
    readonly property real topSpace: ready && vertical ? mediaHeight + gap : 0
    readonly property bool animated: decoder.item?.animated === true
    readonly property bool playing: decoder.item?.playing === true && !hiddenPause
    readonly property bool hiddenPause: (!visible || obscured) && FastfetchMedia.pauseWhenHidden
    property bool requestedPlay: FastfetchMedia.autoplay
    readonly property bool canPlay: FastfetchMedia.allowMotion && requestedPlay && !hiddenPause
    readonly property bool capImageFrames: FastfetchMedia.kind === "animated" && animated && FastfetchMedia.animationFps > 0
                                            && GpuCompatibility.shadersAllowed
    readonly property bool wantsAudio: !releasing && !preview && visible && !obscured
                                    && ready && playing && FastfetchMedia.playAudio
                                    && decoder.item?.hasAudio === true
                                    && (FastfetchMedia.mixWallpaperAudio || !FastfetchMedia.wallpaperAudible)

    property bool releasing: false
    clip: true

    function togglePlayback() {
        root.requestedPlay = !root.playing;
        if (root.requestedPlay && decoder.item) decoder.item.resume();
    }

    onWantsAudioChanged: updateAudioOwner()
    onPlayingChanged: if (capImageFrames && visible) sampledAnimation.scheduleUpdate()
    onVisibleChanged: if (visible && capImageFrames) sampledAnimation.scheduleUpdate()
    Connections {
        target: FastfetchMedia
        function onAudioOwnerChanged() { root.updateAudioOwner(); }
        function onAutoplayChanged() { root.requestedPlay = FastfetchMedia.autoplay; }
        function onPathChanged() { root.requestedPlay = FastfetchMedia.autoplay; }
    }
    Component.onDestruction: {
        root.releasing = true;
        if (FastfetchMedia.audioOwner === root) FastfetchMedia.audioOwner = null;
    }

    function updateAudioOwner() {
        if (wantsAudio && !FastfetchMedia.audioOwner) FastfetchMedia.audioOwner = root;
        else if (!wantsAudio && FastfetchMedia.audioOwner === root) FastfetchMedia.audioOwner = null;
    }

    function align(space) {
        if (FastfetchMedia.position === "start") return 0;
        if (FastfetchMedia.position === "end") return space;
        return space / 2;
    }

    Rectangle {
        anchors.fill: parent
        visible: root.ready && FastfetchMedia.layout === "floating"
        radius: FastfetchMedia.radius
        color: Qt.alpha(FastfetchMedia.style.accent, 0.075)
        border.color: Qt.alpha(FastfetchMedia.style.accent, 0.18)
    }

    Item {
        id: viewport
        width: root.mediaWidth
        height: root.mediaHeight
        x: root.vertical ? root.align(root.width - width) : 0
        y: root.vertical ? 0 : root.align(root.height - height)
        clip: true
        opacity: FastfetchMedia.opacityValue

        Loader {
            id: decoder
            anchors.fill: parent
            active: root.active && root.mediaWidth >= 40 && root.mediaHeight >= 40 && FastfetchMedia.kind !== ""
                    && (FastfetchMedia.kind !== "video" || FastfetchMedia.allowMotion)
            sourceComponent: FastfetchMedia.kind === "video" ? video
                             : FastfetchMedia.kind === "animated" ? animation : still
            visible: root.capImageFrames || !rounded.active
        }

        ShaderEffectSource {
            id: sampledAnimation
            anchors.fill: decoder
            visible: root.capImageFrames && !rounded.active
            sourceItem: root.capImageFrames ? decoder : null
            hideSource: root.capImageFrames
            live: false
            onSourceItemChanged: if (sourceItem) scheduleUpdate()
            onWidthChanged: if (sourceItem) scheduleUpdate()
            onHeightChanged: if (sourceItem) scheduleUpdate()
        }

        Timer {
            running: root.capImageFrames && root.visible && root.playing
            interval: Math.ceil(1000 / Math.max(1, FastfetchMedia.animationFps))
            repeat: true
            onTriggered: sampledAnimation.scheduleUpdate()
        }

        Loader {
            id: rounded
            anchors.fill: parent
            active: root.ready && root.visible && FastfetchMedia.radius > 0 && GpuCompatibility.shadersAllowed
            sourceComponent: MultiEffect {
                source: root.capImageFrames ? sampledAnimation : decoder
                autoPaddingEnabled: false
                maskEnabled: true
                maskSource: Rectangle {
                    width: viewport.width
                    height: viewport.height
                    radius: FastfetchMedia.radius
                    color: "white"
                    visible: false
                    layer.enabled: true
                }
            }
        }

        HoverHandler { id: mediaHover; enabled: root.ready && root.animated && FastfetchMedia.allowMotion }
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 6
            width: 30
            height: 30
            radius: 8
            color: Qt.alpha(FastfetchMedia.style.bg, 0.88)
            visible: root.ready && root.animated && FastfetchMedia.allowMotion && (mediaHover.hovered || !root.playing)
            Text {
                anchors.centerIn: parent
                text: root.playing ? "Ⅱ" : "▶"
                color: FastfetchMedia.style.fg
            }
            TapHandler {
                onTapped: root.togglePlayback()
            }
            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
        }
    }

    Component {
        id: still
        Image {
            source: Caching.fileUrl(FastfetchMedia.path)
            asynchronous: true
            cache: false
            sourceSize: Qt.size(960, 960)
            fillMode: Image.PreserveAspectFit
            scale: FastfetchMedia.zoom
            readonly property bool ready: status === Image.Ready
            readonly property bool failed: status === Image.Error
            readonly property bool animated: false
        }
    }

    Component {
        id: animation
        AnimatedImage {
            id: image
            source: Caching.fileUrl(FastfetchMedia.path)
            asynchronous: true
            sourceSize: Qt.size(960, 960)
            cache: false
            scale: FastfetchMedia.zoom
            fillMode: Image.PreserveAspectFit
            playing: root.requestedPlay && FastfetchMedia.allowMotion
            paused: root.hiddenPause
            speed: FastfetchMedia.speed
            readonly property bool animated: frameCount > 1
            readonly property bool ready: status === Image.Ready && frameCount > 0
            readonly property bool failed: status === Image.Error || (status === Image.Ready && !ready)

            function resume() {
                if (animated && !playing) {
                    currentFrame = 0;
                    playing = true;
                }
            }

            // Qt versions before 6.12 use the loop count embedded in the image.
            function configureLoop() {
                if ("loops" in image) image["loops"] = FastfetchMedia.loop ? AnimatedImage.Infinite : 1;
            }
            Component.onCompleted: configureLoop()
            Connections {
                target: FastfetchMedia
                function onLoopChanged() { image.configureLoop(); }
            }
            onCurrentFrameChanged: {
                if (!("loops" in image) && !FastfetchMedia.loop && animated && currentFrame === frameCount - 1)
                    Qt.callLater(function() { if (!FastfetchMedia.loop && currentFrame === frameCount - 1) image.playing = false; });
            }
            onPlayingChanged: {
                if (!playing && !("loops" in image) && FastfetchMedia.loop && animated && root.canPlay)
                    Qt.callLater(function() { if (root.canPlay && FastfetchMedia.loop) image.resume(); });
            }
        }
    }

    Component {
        id: video
        Item {
            readonly property bool ready: player.hasVideo && !failed
            readonly property bool failed: player.error !== MediaPlayer.NoError || (loaded && !player.hasVideo)
            readonly property bool loaded: player.mediaStatus === MediaPlayer.LoadedMedia
                                        || player.mediaStatus === MediaPlayer.BufferedMedia
            readonly property bool hasAudio: player.hasAudio
            readonly property bool animated: true
            readonly property bool playing: player.playing

            function resume() { if (root.canPlay) player.play(); }

            VideoOutput {
                id: output
                anchors.fill: parent
                scale: FastfetchMedia.zoom
                fillMode: VideoOutput.PreserveAspectFit
            }
            MediaPlayer {
                id: player
                source: Caching.fileUrl(FastfetchMedia.path)
                videoOutput: output
                audioOutput: FastfetchMedia.audioOwner === root ? audio : null
                loops: FastfetchMedia.loop ? MediaPlayer.Infinite : 1
                playbackRate: FastfetchMedia.speed
                onMediaStatusChanged: {
                    if (mediaStatus === MediaPlayer.LoadedMedia) {
                        if (root.canPlay) play();
                        else pause();
                    }
                }
            }
            AudioOutput { id: audio }
            Connections {
                target: root
                function onCanPlayChanged() {
                    if (root.canPlay) player.play();
                    else if (player.playing) player.pause();
                }
            }
        }
    }
}
