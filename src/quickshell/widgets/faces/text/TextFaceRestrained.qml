import QtQuick
import "../../../"
import "../common"

// Text, Restrained: the text set in a light weight on a flat card with a
// 1 px hairline; a short quiet rule marks the left edge.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property real minWidth: 60
    property real minHeight: 30
    property real maxWidth: 2000
    property real maxHeight: 800
    property real minAspect: 0.2
    property real maxAspect: 20.0
    property bool isRound: false

    property string textContent: ""
    readonly property bool isEmpty: root.textContent.trim() === ""
    readonly property FaceTone tone: FaceTone {}
    readonly property real pad: Math.max(Scaler.s(6), Math.min(width, height) * 0.14)

    MinimalAppear { target: root }

    MinimalCard { anchors.fill: parent }

    Rectangle {
        x: root.pad * 0.5
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: Math.max(Scaler.s(10), parent.height * 0.42)
        color: root.tone.quietAccent
    }

    Text {
        anchors.fill: parent
        anchors.margins: root.pad
        anchors.leftMargin: root.pad * 1.2
        text: root.isEmpty ? I18n.t("widgets.text.placeholder", "Enter text") : root.textContent
        font.family: ThemeBackend.fontFamily
        font.weight: Font.Light
        font.pixelSize: height
        fontSizeMode: Text.Fit
        minimumPixelSize: 8
        color: root.isEmpty ? root.tone.faint : root.tone.ink
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
    }
}
