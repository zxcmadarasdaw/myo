import QtQuick

Loader {
    id: root

    required property url imageUrl
    required property bool playing

    active: imageUrl.toString().toLowerCase().endsWith(".gif")
    sourceComponent: AnimatedImage {
        source: root.imageUrl
        fillMode: Image.PreserveAspectCrop
        cache: false
        playing: root.playing
    }
}
