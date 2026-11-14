import QtQuick
import QtQuick.Layouts
import "../../../"
import "../common"

// Clock, Atelier: one face, nine looks (faceStyle). The look decides typography and
// arrangement: Elegant sets a serif time over an italic date, Editorial a heavy serif
// figure over a tracked kicker, Technical a monospaced time with a seconds scale, Retro
// a window with a blinking colon, Compact a single line.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property string faceStyle: "elegant"
    property real minWidth: 120
    property real minHeight: 48
    property real maxWidth: 1600
    property real maxHeight: 800
    property real minAspect: 1.0
    property real maxAspect: 8.0
    property bool isRound: false

    AtelierKit { id: kit; style: root.faceStyle }
    AtelierAppear { target: root; kit: kit }

    readonly property string look: kit.styleId
    readonly property bool compact: look === "compact" || height < Scaler.s(70)
    readonly property bool centered: look === "elegant" || look === "borderless"
    readonly property bool withSeconds: look === "technical"

    // Seconds only where they are shown; one 1 s timer while visible.
    property int second: new Date().getSeconds()
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && (root.withSeconds || (root.look === "retro" && kit.loops))
        onTriggered: root.second = new Date().getSeconds()
    }
    readonly property bool colonOn: root.look !== "retro" || !kit.loops || root.second % 2 === 0

    readonly property string dateLine: {
        switch (look) {
        case "technical": {
            const d = DateTime.now;
            const pad = n => (n < 10 ? "0" : "") + n;
            return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + "  ·  " + DateTime.dayNameShort.toUpperCase();
        }
        case "elegant": return DateTime.dayName + ", " + DateTime.fullDate;
        case "compact": return DateTime.dayNameShort + " " + DateTime.shortDate;
        default: return kit.label(DateTime.dayName + "  ·  " + DateTime.fullDate);
        }
    }

    AtelierCard {
        id: card
        kit: kit
        title: I18n.t("widgets.types.clock", "Clock")
        detail: root.look === "retro" ? DateTime.dayNameShort.toUpperCase() : ""
        showHeader: kit.hasHeader && (root.look === "retro" || root.look === "technical") && !root.compact
    }

    GridLayout {
        x: card.contentX
        y: card.contentY
        width: card.contentWidth
        height: card.contentHeight
        columns: root.compact ? 2 : 1
        rowSpacing: Math.max(Scaler.s(3), height * 0.04)
        columnSpacing: Scaler.s(12)

        Text {
            id: timeText
            Layout.fillWidth: !root.compact
            Layout.fillHeight: true
            Layout.preferredWidth: root.compact ? implicitWidth : -1
            text: DateTime.hour
                  + "<font color='" + (root.colonOn ? (root.look === "editorial" || root.look === "premium" ? kit.accent : kit.faint) : "transparent") + "'>:</font>"
                  + DateTime.minute
                  + (root.withSeconds ? "<font color='" + kit.faint + "'><small>:" + (root.second < 10 ? "0" : "") + root.second + "</small></font>" : "")
                  + (DateTime.amPm !== "" ? "<font color='" + kit.muted + "'><small> " + DateTime.amPm + "</small></font>" : "")
            textFormat: Text.StyledText
            font.family: kit.displayFamily
            font.weight: kit.displayWeight
            font.pixelSize: root.compact ? Math.max(Scaler.s(14), parent.height * 0.8) : height
            fontSizeMode: root.compact ? Text.FixedSize : Text.Fit
            minimumPixelSize: 10
            font.letterSpacing: root.look === "editorial" ? -height * 0.02 : 0
            color: kit.ink
            horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
            style: root.look === "borderless" ? Text.Raised : Text.Normal
            styleColor: Qt.alpha(ThemeBackend.crust, 0.6)
        }

        AtelierMeter {
            visible: root.withSeconds && !root.compact
            kit: kit
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            value: root.second / 59
            color: kit.accent
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: root.compact ? Qt.AlignVCenter : Qt.AlignTop
            visible: root.compact || root.height >= Scaler.s(84)
            spacing: Scaler.s(8)

            Item { Layout.fillWidth: true; visible: root.centered && !root.compact }
            Rectangle {
                visible: root.look === "elegant"
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Scaler.s(5)
                Layout.preferredHeight: Scaler.s(5)
                radius: width / 2
                color: kit.accent2
            }
            Text {
                Layout.fillWidth: !root.centered || root.compact
                Layout.maximumWidth: card.contentWidth
                text: root.dateLine
                elide: Text.ElideRight
                font.family: root.look === "elegant" ? kit.serif : kit.labelFamily
                font.italic: root.look === "elegant"
                font.pixelSize: root.look === "elegant" ? Math.max(Scaler.s(11), Math.min(Scaler.s(17), root.height * 0.11))
                                : Math.max(Scaler.s(9), Math.min(Scaler.s(13), root.height * 0.09))
                font.letterSpacing: root.look === "elegant" || root.compact ? 0 : kit.tracking
                color: root.look === "editorial" ? kit.accent : kit.muted
                style: root.look === "borderless" ? Text.Raised : Text.Normal
                styleColor: Qt.alpha(ThemeBackend.crust, 0.6)
            }
            Item { Layout.fillWidth: true; visible: root.centered && !root.compact }
        }
    }
}
