import QtQuick
import "../../../reusables"
import "../../../"
import "../common"

// Image, Restrained: the picture in a narrow flat mat with a 1 px hairline,
// like a print in a plain frame.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property real minWidth: 40
    property real minHeight: 40
    property real maxWidth: 4000
    property real maxHeight: 4000
    property real minAspect: 0.02
    property real maxAspect: 50.0
    property bool isRound: false

    property string imagePath: ""
    readonly property FaceTone tone: FaceTone {}
    readonly property real mat: Math.max(Scaler.s(4), Math.min(Scaler.s(14), Math.min(width, height) * 0.04))

    MinimalAppear { target: root }

    MinimalCard { anchors.fill: parent }

    BoundedImage {
        id: srcImage
        anchors.fill: parent
        anchors.margins: root.mat
        source: root.imagePath !== "" ? (root.imagePath.startsWith("file://") ? root.imagePath : "file://" + root.imagePath) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        allowAnimation: true
        playing: root.visible
        visible: status === Image.Ready
    }

    Rectangle {
        anchors.fill: srcImage
        color: "transparent"
        border.width: 1
        border.color: root.tone.hairline
    }

    Text {
        anchors.centerIn: parent
        visible: root.imagePath === "" || srcImage.status !== Image.Ready
        text: "󰋩"
        font.family: ThemeBackend.iconFont
        font.pixelSize: Math.max(14, Math.min(root.width, root.height) * 0.25)
        color: root.tone.faint
    }
}
