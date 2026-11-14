import QtQuick
import QtQuick.Effects
import "../../../reusables"
import "../../../"
import "../common"

// Image, Lush: the picture set into an ornamented glass frame with a deep
// mat, rounded corners, an inner bevel and a soft vignette.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 80
    property real minHeight: 80
    property real maxWidth: 4000
    property real maxHeight: 4000
    property real minAspect: 0.05
    property real maxAspect: 20.0
    property bool isRound: false

    property string imagePath: ""
    readonly property FaceTone tone: FaceTone {}
    readonly property real mat: Math.max(Scaler.s(10), Math.min(Scaler.s(28), Math.min(width, height) * 0.08))

    LushAppear { target: root }

    LushCard { id: frame; anchors.fill: parent; intensity: 0.55 }

    Item {
        id: picture
        anchors.fill: parent
        anchors.margins: root.mat
        readonly property real r: Math.max(Scaler.s(6), frame.radius - root.mat * 0.6)

        Rectangle {
            id: picMask
            anchors.fill: parent
            radius: picture.r
            visible: false
            layer.enabled: true
        }

        BoundedImage {
            id: srcImage
            anchors.fill: parent
            source: root.imagePath !== "" ? (root.imagePath.startsWith("file://") ? root.imagePath : "file://" + root.imagePath) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            allowAnimation: true
            playing: root.visible
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            source: srcImage
            visible: srcImage.status === Image.Ready
            maskEnabled: true
            maskSource: picMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            saturation: 0.05
        }

        // vignette
        Rectangle {
            anchors.fill: parent
            radius: picture.r
            visible: srcImage.status === Image.Ready
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha("#000000", 0.18) }
                GradientStop { position: 0.25; color: "transparent" }
                GradientStop { position: 0.75; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.alpha("#000000", 0.28) }
            }
        }

        // bevel: dark outer line, light inner line
        Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: picture.r + 1
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha("#000000", root.tone.isLight ? 0.18 : 0.45)
        }
        Rectangle {
            anchors.fill: parent
            radius: picture.r
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(root.tone.sheen, root.tone.isLight ? 0.6 : 0.16)
        }

        Text {
            anchors.centerIn: parent
            visible: root.imagePath === "" || srcImage.status !== Image.Ready
            text: "󰋩"
            font.family: ThemeBackend.iconFont
            font.pixelSize: Math.max(16, Math.min(root.width, root.height) * 0.28)
            color: Qt.alpha(root.tone.accent, 0.7)
        }
    }
}
