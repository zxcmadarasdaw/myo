import QtQuick

// GIF and verified animated WebP use the existing AnimatedImage layer.
//
// WallpaperEngine loads this file by URL (Loader.source), not as a type:
// Quickshell serves the config over its qs: scheme, which Qt treats as a remote
// location, and in a remote directory without qmldir sibling files are not
// types. Loading by URL also keeps a GIF problem from stopping the whole shell.
// The properties are set through Binding, so they are not required properties.
Loader {
    id: root

    property url imageUrl
    property bool playing: false

    signal failed(string reason)

    active: {
        const url = imageUrl.toString().toLowerCase().split("?")[0];
        return url.endsWith(".gif") || url.endsWith(".animated.webp");
    }
    sourceComponent: AnimatedImage {
        id: animation
        source: root.imageUrl
        fillMode: Image.PreserveAspectCrop
        cache: false
        playing: false
        function syncPlayback() {
            playing = root.playing && status === Image.Ready && frameCount > 0;
        }
        Connections {
            target: root
            function onPlayingChanged() { animation.syncPlayback(); }
        }
        function reportIfBroken() {
            // Qt reports a truncated GIF as Ready with zero frames: nothing is
            // drawn and no error is raised, so treat that as a failure too.
            if (status === Image.Error || (status === Image.Ready && frameCount < 1)) {
                // Deferred: a local GIF fails while it is being created, before
                // the owner's Connections are attached to this item.
                const url = root.imageUrl;
                Qt.callLater(function() {
                    if (root.imageUrl === url)
                        root.failed("Cannot decode animation (damaged file or unsupported variant)");
                });
            }
        }
        onStatusChanged: {
            reportIfBroken();
            syncPlayback();
        }
        onSourceChanged: Qt.callLater(syncPlayback)
        // Local files load synchronously while the object is created, before
        // onStatusChanged is connected, so check the initial status as well.
        Component.onCompleted: {
            reportIfBroken();
            syncPlayback();
        }
    }
}
