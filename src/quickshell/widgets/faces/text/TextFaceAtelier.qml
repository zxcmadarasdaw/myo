import QtQuick
import "../../../"
import "../common"

// Text, Atelier: the user's text set in the look's type — a serif quote for Elegant,
// a heavy headline for Editorial, a prompt line for Technical / Retro.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property string faceStyle: "editorial"
    property real minWidth: 60
    property real minHeight: 30
    property real maxWidth: 2000
    property real maxHeight: 800
    property real minAspect: 0.2
    property real maxAspect: 20.0
    property bool isRound: false

    property string textContent: ""
    readonly property bool isEmpty: root.textContent.trim() === ""

    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }

    readonly property string look: kit.styleId
    readonly property bool prompt: look === "technical" || look === "retro"

    AtelierCard {
        id: card
        kit: kit
        title: I18n.t("widgets.types.text", "Text")
        showHeader: kit.hasHeader && root.height >= Scaler.s(90) && root.prompt
    }

    Text {
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        text: root.isEmpty ? I18n.t("widgets.text.placeholder", "Enter text")
              : (root.prompt ? "> " : root.look === "elegant" ? "“" : "") + root.textContent + (root.look === "elegant" ? "”" : "")
        font.family: kit.displayFamily
        font.weight: kit.displayWeight
        font.italic: root.look === "elegant"
        font.letterSpacing: root.look === "editorial" ? -Scaler.s(0.5) : 0
        font.pixelSize: height
        fontSizeMode: Text.Fit
        minimumPixelSize: 8
        color: root.isEmpty ? kit.faint : kit.ink
        wrapMode: Text.Wrap
        horizontalAlignment: root.look === "elegant" || root.look === "borderless" ? Text.AlignHCenter : Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        style: root.look === "borderless" ? Text.Raised : Text.Normal
        styleColor: Qt.alpha(ThemeBackend.crust, 0.6)
    }
}
