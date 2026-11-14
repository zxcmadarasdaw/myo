import QtQuick
import "../../../"

// Frame of an Atelier face: surface, border, header and the small style details.
// Faces put their content in the rectangle (contentX, contentY, contentWidth, contentHeight).
// Nothing here is a control: the decorative window squares of the Retro look and the
// Technical corner marks take no input. The hover handler only reads the pointer.
Item {
    id: card
    anchors.fill: parent

    property AtelierKit kit: AtelierKit {}
    property string title: ""
    property string detail: ""
    property bool showHeader: kit.hasHeader
    property bool emphasised: false
    property color detailColor: kit.faint
    property real margin: kit.pad(10)

    readonly property var t: kit.t
    readonly property bool hovered: hover.hovered
    readonly property real shadow: t.frame === "window" ? Scaler.s(3) : 0
    readonly property real headerHeight: showHeader ? kit.headerHeight : 0
    readonly property real contentX: margin
    readonly property real contentY: t.frame === "window" ? (showHeader ? headerHeight + margin * 0.8 : margin)
                                     : (showHeader ? margin + headerHeight + Scaler.s(4) : margin)
    readonly property real contentWidth: Math.max(0, width - shadow - margin * 2)
    readonly property real contentHeight: Math.max(0, height - shadow - contentY - margin)

    HoverHandler { id: hover; enabled: card.kit.transitions }

    // Retro: a solid offset shadow instead of a soft one (no blur, no shader).
    Rectangle {
        visible: card.shadow > 0
        x: card.shadow
        y: card.shadow
        width: surface.width
        height: surface.height
        radius: surface.radius
        color: Qt.alpha(card.kit.accent, 0.28)
    }

    // Borderless: a soft vertical scrim so text stays readable on bright frames of the video.
    Rectangle {
        visible: card.t.frame === "scrim"
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.alpha(ThemeBackend.crust, 0.32) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Rectangle {
        id: surface
        visible: card.t.frame !== "scrim"
        width: card.width - card.shadow
        height: card.height - card.shadow
        radius: card.kit.radius
        antialiasing: true
        color: Qt.alpha(card.kit.surface, card.t.fill)
        gradient: card.t.fillTone === "gradient" ? premiumGradient : null
        border.width: card.t.border > 0 ? 1 : 0
        border.color: card.t.accentBorder
            ? Qt.alpha(card.kit.accent, Math.min(1, card.t.border * (card.hovered || card.emphasised ? 1.6 : 1)))
            : Qt.alpha(ThemeBackend.text, Math.min(1, card.t.border + (card.hovered ? 0.08 : 0) + (card.emphasised ? 0.12 : 0)))
        Behavior on border.color { ColorAnimation { duration: card.kit.duration(200); easing.type: Easing.OutCubic } }

        Gradient {
            id: premiumGradient
            GradientStop { position: 0.0; color: Qt.alpha(Qt.lighter(ThemeBackend.base, 1.35), card.t.fill) }
            GradientStop { position: 1.0; color: Qt.alpha(ThemeBackend.crust, card.t.fill) }
        }
    }

    // Premium: a hairline of light along the top edge.
    Rectangle {
        visible: card.t.frame === "sheen"
        x: surface.radius
        y: 1
        width: surface.width - surface.radius * 2
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.alpha(ThemeBackend.text, 0.22) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // Retro: title bar with the title in capitals and three inert window squares.
    Item {
        visible: card.t.frame === "window" && card.showHeader
        x: 1
        y: 1
        width: surface.width - 2
        height: card.headerHeight
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(card.kit.accent, card.hovered ? 0.24 : 0.16)
            Behavior on color { ColorAnimation { duration: card.kit.duration(200) } }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Qt.alpha(card.kit.accent, 0.55)
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Scaler.s(8)
            anchors.right: windowDetail.left
            anchors.rightMargin: Scaler.s(6)
            anchors.verticalCenter: parent.verticalCenter
            text: card.kit.label(card.title)
            elide: Text.ElideRight
            font.family: card.kit.mono
            font.pixelSize: Scaler.s(10)
            font.weight: Font.DemiBold
            font.letterSpacing: Scaler.s(1)
            color: card.kit.ink
        }
        Text {
            id: windowDetail
            anchors.right: squares.left
            anchors.rightMargin: Scaler.s(8)
            anchors.verticalCenter: parent.verticalCenter
            text: card.detail
            font.family: card.kit.mono
            font.pixelSize: Scaler.s(9)
            color: card.detailColor
        }
        Row {
            id: squares
            anchors.right: parent.right
            anchors.rightMargin: Scaler.s(7)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Scaler.s(4)
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: Scaler.s(7)
                    height: width
                    color: index === 2 ? Qt.alpha(card.kit.accent, 0.7) : "transparent"
                    border.width: 1
                    border.color: Qt.alpha(card.kit.ink, 0.55)
                }
            }
        }
    }

    // Technical: corner marks.
    Repeater {
        model: card.t.frame === "brackets" ? 4 : 0
        Item {
            required property int index
            readonly property bool isRight: index % 2 === 1
            readonly property bool isBottom: index > 1
            readonly property real len: Scaler.s(10)
            x: isRight ? surface.width - len : 0
            y: isBottom ? surface.height - len : 0
            width: len
            height: len
            Rectangle { x: 0; y: parent.isBottom ? parent.len - 1.5 : 0; width: parent.len; height: 1.5; color: card.kit.accent }
            Rectangle { x: parent.isRight ? parent.len - 1.5 : 0; y: 0; width: 1.5; height: parent.len; color: card.kit.accent }
        }
    }

    // Editorial: an accent bar over a full-width hairline.
    Rectangle {
        visible: card.t.frame === "rule"
        x: 0
        y: 0
        width: surface.width
        height: 1
        color: card.kit.hairStrong
    }
    Rectangle {
        visible: card.t.frame === "rule"
        x: 0
        y: 0
        width: Scaler.s(36)
        height: Scaler.s(3)
        color: card.kit.accent
    }

    // Header for every look except the Retro title bar.
    Item {
        visible: card.showHeader && card.t.frame !== "window"
        x: card.margin
        y: card.margin
        width: card.contentWidth
        height: card.headerHeight

        Rectangle {
            id: dot
            visible: card.t.header === "dot"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? Scaler.s(6) : 0
            height: width
            radius: width / 2
            color: card.kit.accent
        }
        Text {
            anchors.left: dot.right
            anchors.leftMargin: dot.visible ? Scaler.s(7) : 0
            anchors.right: headerDetail.left
            anchors.rightMargin: Scaler.s(6)
            anchors.verticalCenter: parent.verticalCenter
            text: (card.t.header === "code" ? "// " : "") + card.kit.label(card.title)
            elide: Text.ElideRight
            font.family: card.kit.labelFamily
            font.pixelSize: card.t.header === "serif" ? Scaler.s(13) : card.t.header === "dot" ? Scaler.s(12) : Scaler.s(10)
            font.italic: card.t.header === "serif"
            font.weight: card.t.header === "dot" ? Font.Medium : Font.Normal
            font.letterSpacing: card.t.header === "serif" || card.t.header === "dot" ? 0 : card.kit.tracking
            color: card.t.header === "kicker" ? card.kit.accent : card.t.header === "dot" ? card.kit.ink : card.kit.muted
        }
        Text {
            id: headerDetail
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: card.detail
            font.family: card.kit.labelFamily
            font.pixelSize: Scaler.s(10)
            font.italic: card.t.header === "serif"
            color: card.detailColor
        }
    }
}
