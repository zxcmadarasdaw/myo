import QtQuick
import "../../../"
import "../common"

// Text, Lush: the text as a glowing display line on ornamented glass,
// with accent rules fading in from both sides.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 90
    property real minHeight: 44
    property real maxWidth: 2000
    property real maxHeight: 800
    property real minAspect: 0.3
    property real maxAspect: 20.0
    property bool isRound: false

    property string textContent: ""
    readonly property bool isEmpty: root.textContent.trim() === ""
    readonly property FaceTone tone: FaceTone {}
    readonly property real pad: Math.max(Scaler.s(12), Math.min(width, height) * 0.2)

    LushAppear { target: root }

    LushCard { anchors.fill: parent }

    LushGlowText {
        id: line
        anchors.fill: parent
        anchors.margins: root.pad
        text: root.isEmpty ? I18n.t("widgets.text.placeholder", "Enter text") : root.textContent
        font.weight: Font.DemiBold
        font.pixelSize: height
        fontSizeMode: Text.Fit
        minimumPixelSize: 8
        font.letterSpacing: Scaler.s(0.5)
        color: root.isEmpty ? root.tone.faint : root.tone.ink
        glowAmount: root.isEmpty ? 0 : 0.8
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Rectangle {
        visible: root.height >= Scaler.s(70)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.pad * 0.55
        width: Math.min(parent.width * 0.5, Scaler.s(220))
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.alpha(root.tone.accent, 0.8) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
}
