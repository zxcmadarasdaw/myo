import QtQuick

// Animated GIF layer. A plain Image shows only the first GIF frame, so GIFs are
// rendered with AnimatedImage. The loader is inactive for every other format.
Loader {
    id: root

    required property url imageUrl
    required property bool playing

    signal failed(string reason)

    active: {
        const url = imageUrl.toString().toLowerCase();
        return url.endsWith(".gif") || url.indexOf(".gif?") !== -1;
    }
    sourceComponent: AnimatedImage {
        source: root.imageUrl
        fillMode: Image.PreserveAspectCrop
        cache: false
        playing: root.playing
        function reportIfBroken() {
            // Qt reports a truncated GIF as Ready with zero frames: nothing is
            // drawn and no error is raised, so treat that as a failure too.
            if (status === Image.Error || (status === Image.Ready && frameCount < 1))
                root.failed("Cannot decode GIF (damaged file or unsupported variant)");
        }
        onStatusChanged: reportIfBroken()
        // Local files load synchronously while the object is created, before
        // onStatusChanged is connected, so check the initial status as well.
        Component.onCompleted: reportIfBroken()
    }
}
