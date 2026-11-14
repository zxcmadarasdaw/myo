import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Body of the Atelier load faces (CPU, RAM, temperature, disk, GPU). It only shows what
// it is given; `value` < 0 means "not measured" and is shown as such, never as 0 %.
// The history line samples the current value every `sampleInterval` ms while visible,
// so it moves with time even when the reading does not change.
Item {
    id: body
    anchors.fill: parent
    clip: true

    property string faceStyle: "matte"
    property string title: ""
    property string valueText: "—"
    property string detailText: ""
    property string note: ""
    property real value: -1
    property int sampleInterval: 2000

    AtelierKit { id: kit; style: body.faceStyle }
    AtelierAppear { target: body; kit: kit }

    readonly property string look: kit.styleId
    readonly property bool known: value >= 0
    readonly property bool compact: look === "compact" || height < Scaler.s(84)
    readonly property bool showSpark: kit.t.spark && !compact && height >= Scaler.s(120)
    readonly property color levelColor: known ? kit.level(value) : kit.faint

    property var history: []
    function sample() {
        if (!body.known) return;
        const next = body.history.slice(-47);
        next.push(body.value);
        body.history = next;
    }
    Timer {
        interval: Math.max(500, body.sampleInterval)
        repeat: true
        running: body.visible && body.showSpark
        triggeredOnStart: true
        onTriggered: body.sample()
    }

    AtelierCard {
        id: card
        kit: kit
        title: body.title
        detail: body.compact ? "" : body.detailText
        showHeader: kit.hasHeader && !body.compact
        emphasised: body.known && body.value >= 0.9
    }

    // compact: label · value · level in one line
    RowLayout {
        visible: body.compact
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        spacing: Scaler.s(10)
        Text {
            text: kit.label(body.title)
            font.family: kit.labelFamily
            font.pixelSize: Scaler.s(10)
            font.letterSpacing: kit.tracking
            color: kit.muted
        }
        Text {
            text: body.valueText
            font.family: kit.displayFamily
            font.weight: Font.Medium
            font.pixelSize: Math.max(Scaler.s(12), Math.min(Scaler.s(20), card.contentHeight * 0.7))
            color: body.known && body.value >= 0.9 ? kit.alarm : kit.ink
        }
        AtelierMeter {
            kit: kit
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: implicitHeight
            visible: body.known
            value: Math.max(0, body.value)
            color: body.levelColor
        }
        Text {
            visible: !body.known && body.note !== ""
            Layout.fillWidth: true
            text: body.note
            elide: Text.ElideRight
            font.family: kit.labelFamily
            font.pixelSize: Scaler.s(9)
            color: kit.faint
        }
    }

    ColumnLayout {
        visible: !body.compact
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        spacing: Scaler.s(4)

        Text {
            Layout.fillWidth: true
            Layout.fillHeight: !body.showSpark
            Layout.preferredHeight: body.showSpark ? card.contentHeight * 0.42 : -1
            text: body.valueText
            font.family: kit.displayFamily
            font.weight: kit.displayWeight
            font.pixelSize: height
            fontSizeMode: Text.Fit
            minimumPixelSize: 10
            verticalAlignment: Text.AlignVCenter
            color: body.known && body.value >= 0.9 ? kit.alarm : kit.ink
        }

        Text {
            visible: !body.known && body.note !== ""
            Layout.fillWidth: true
            text: body.note
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: kit.labelFamily
            font.pixelSize: Scaler.s(10)
            color: kit.faint
        }

        AtelierSpark {
            visible: body.showSpark && body.known
            Layout.fillWidth: true
            Layout.fillHeight: true
            values: body.history
            color: body.levelColor
            stepped: body.look === "retro"
            fillOpacity: body.look === "technical" ? 0.12 : 0.2
        }

        AtelierMeter {
            kit: kit
            visible: body.known
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            value: Math.max(0, body.value)
            color: body.levelColor
        }
    }
}
