import QtQuick
import QtQuick.Shapes
import "../../../"

// Fine decorative frame for Lush faces: a thin arc and a short tail at each
// corner, plus a small diamond at the middle of the top and bottom edges.
// Strokes are 1 px and transparent inside, so content under them stays visible.
Item {
    id: orn

    property real radius: Scaler.s(16)
    property color color: ThemeBackend.mauve
    property bool diamonds: width >= Scaler.s(160)

    readonly property real inset: Math.max(Scaler.s(4), radius * 0.32)
    readonly property real arm: Math.max(Scaler.s(8), Math.min(Scaler.s(26), Math.min(width, height) * 0.14))
    readonly property real r: Math.max(Scaler.s(4), radius - inset)

    Shape {
        anchors.fill: parent
        antialiasing: true

        // top-left
        ShapePath {
            strokeColor: orn.color; strokeWidth: 1; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: orn.inset; startY: orn.inset + orn.r + orn.arm
            PathLine { x: orn.inset; y: orn.inset + orn.r }
            PathArc { x: orn.inset + orn.r; y: orn.inset; radiusX: orn.r; radiusY: orn.r }
            PathLine { x: orn.inset + orn.r + orn.arm; y: orn.inset }
        }
        // top-right
        ShapePath {
            strokeColor: orn.color; strokeWidth: 1; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: orn.width - orn.inset - orn.r - orn.arm; startY: orn.inset
            PathLine { x: orn.width - orn.inset - orn.r; y: orn.inset }
            PathArc { x: orn.width - orn.inset; y: orn.inset + orn.r; radiusX: orn.r; radiusY: orn.r }
            PathLine { x: orn.width - orn.inset; y: orn.inset + orn.r + orn.arm }
        }
        // bottom-right
        ShapePath {
            strokeColor: orn.color; strokeWidth: 1; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: orn.width - orn.inset; startY: orn.height - orn.inset - orn.r - orn.arm
            PathLine { x: orn.width - orn.inset; y: orn.height - orn.inset - orn.r }
            PathArc { x: orn.width - orn.inset - orn.r; y: orn.height - orn.inset; radiusX: orn.r; radiusY: orn.r }
            PathLine { x: orn.width - orn.inset - orn.r - orn.arm; y: orn.height - orn.inset }
        }
        // bottom-left
        ShapePath {
            strokeColor: orn.color; strokeWidth: 1; fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: orn.inset + orn.r + orn.arm; startY: orn.height - orn.inset
            PathLine { x: orn.inset + orn.r; y: orn.height - orn.inset }
            PathArc { x: orn.inset; y: orn.height - orn.inset - orn.r; radiusX: orn.r; radiusY: orn.r }
            PathLine { x: orn.inset; y: orn.height - orn.inset - orn.r - orn.arm }
        }
    }

    Repeater {
        model: orn.diamonds ? 2 : 0
        Rectangle {
            required property int index
            width: Scaler.s(5); height: width
            rotation: 45
            x: (orn.width - width) / 2
            y: index === 0 ? orn.inset - height / 2 : orn.height - orn.inset - height / 2
            color: "transparent"
            border.width: 1
            border.color: orn.color
            antialiasing: true
        }
    }
}
