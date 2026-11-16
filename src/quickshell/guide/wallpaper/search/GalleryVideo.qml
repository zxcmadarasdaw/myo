import QtQuick
import QtMultimedia

Video {
    id: clip
    objectName: "galleryVideo"
    readonly property bool ready: hasVideo && error === MediaPlayer.NoError
    readonly property bool isPlaying: playbackState === MediaPlayer.PlayingState
    property bool loopOn: true
    signal failed()

    fillMode: VideoOutput.PreserveAspectCrop
    muted: true
    loops: loopOn ? MediaPlayer.Infinite : 1
    visible: ready

    onSourceChanged: {
        stop();
        if (source.toString() !== "") play();
    }
    onErrorOccurred: clip.failed()
    Component.onCompleted: if (source.toString() !== "") play()
    Component.onDestruction: stop()
}
