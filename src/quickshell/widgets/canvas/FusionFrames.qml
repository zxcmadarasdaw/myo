import QtQuick
import "../../"
import "WidgetFusion.js" as Fusion
import "CanvasMath.js" as CM

Item {
    id: frame
    property var records: []
    property var camera: null
    readonly property real zoom: camera ? camera.viewZoom : 1
    readonly property real viewX: camera ? camera.viewX : 0
    readonly property real viewY: camera ? camera.viewY : 0
    readonly property var panels: Fusion.groups(records)
    readonly property bool hasFade: visible && panels.some(panel => panel.options.animation === "fade")
    property real reveal: 1
    onHasFadeChanged: {
        if (hasFade) revealFrame.restart();
    }
    NumberAnimation { id: revealFrame; target: frame; property: "reveal"; from: 0; to: 1; duration: 180 }

    Repeater {
        model: frame.panels
        delegate: Rectangle {
            id: plate
            required property var modelData
            readonly property var options: modelData.options
            readonly property bool borderless: options.style === "borderless" || options.mode === "seamless"
            readonly property real pad: options.style === "compact" ? Math.min(options.padding, 6) : options.padding
            readonly property real heading: options.title ? 26 : 0
            opacity: options.animation === "fade" ? frame.reveal : 1
            x: (modelData.box.x - pad - frame.viewX) * frame.zoom
            y: (modelData.box.y - pad - heading - frame.viewY) * frame.zoom
            width: (modelData.box.w + pad * 2) * frame.zoom
            height: (modelData.box.h + pad * 2 + heading) * frame.zoom
            radius: (options.style === "retro" || options.style === "technical" || options.style === "editorial" ? 2 : options.radius) * frame.zoom
            antialiasing: radius > 0
            color: options.style === "borderless" ? "transparent"
                   : Qt.alpha(options.background || (options.style === "retro" ? ThemeBackend.surface0 : ThemeBackend.base),
                              options.style === "minimal" ? options.opacity * 0.55 : options.opacity)
            border.width: borderless ? 0 : 1
            border.color: Qt.alpha(ThemeBackend.mauve, options.style === "technical" || options.style === "retro" ? 0.65 : 0.28)
            Repeater {
                model: plate.options.dividers && !plate.borderless && plate.options.mode !== "freeform"
                       ? plate.modelData.members.length - 1 : 0
                delegate: Rectangle {
                    required property int index
                    readonly property var previous: CM.widgetBox(plate.modelData.members[index])
                    readonly property var current: CM.widgetBox(plate.modelData.members[index + 1])
                    readonly property bool sameRow: previous.y === current.y
                    readonly property real previousEnd: sameRow ? previous.x + previous.w : previous.y + previous.h
                    readonly property real nextStart: sameRow ? current.x : current.y
                    readonly property real midpoint: (previousEnd + nextStart) / 2
                    visible: nextStart > previousEnd
                    color: Qt.alpha(ThemeBackend.mauve, 0.3)
                    x: sameRow ? (midpoint - plate.modelData.box.x + plate.pad) * frame.zoom : plate.pad * frame.zoom
                    y: ((sameRow ? current.y : midpoint) - plate.modelData.box.y + plate.pad + plate.heading) * frame.zoom
                    width: sameRow ? 1 : Math.max(0, plate.width - 2 * x)
                    height: sameRow ? Math.min(previous.h, current.h) * frame.zoom : 1
                }
            }
            Rectangle {
                visible: !plate.borderless && ["technical", "editorial", "retro"].includes(plate.options.style)
                x: plate.pad * frame.zoom
                width: Math.min(parent.width, plate.options.style === "editorial" ? 90 * frame.zoom : parent.width - x)
                height: Math.max(1, 2 * frame.zoom)
                color: ThemeBackend.mauve
            }
            Text {
                visible: plate.heading > 0
                x: plate.pad * frame.zoom
                y: (plate.pad / 2 + 3) * frame.zoom
                width: Math.max(0, parent.width - 2 * x)
                text: plate.options.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: ThemeBackend.text
                font.family: plate.options.style === "retro" || plate.options.style === "technical"
                             ? "monospace" : plate.options.style === "editorial" ? "serif" : ThemeBackend.fontFamily
                font.pixelSize: Math.max(1, 14 * frame.zoom)
            }
        }
    }
}
