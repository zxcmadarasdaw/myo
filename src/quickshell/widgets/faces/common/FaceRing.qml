import QtQuick
import "../../../"

// Circular gauge shared by the Restrained and Lush faces.
//   lush: false -> a 1 px track and a thin arc in a quiet colour
//   lush: true  -> a recessed track, a conical-gradient arc with a soft glow
//                  and a bright cap at the end of the arc
Canvas {
    id: ring

    property real value: 0          // 0..1
    property bool lush: false
    property real thickness: lush ? Scaler.s(7) : Scaler.s(2)
    property color colorA: lush ? tone.accent : tone.quietAccent
    property color colorB: lush ? tone.accent2 : tone.quietAccent
    readonly property FaceTone tone: FaceTone {}

    readonly property real target: Math.max(0, Math.min(1, isNaN(value) ? 0 : value))
    property real shown: target
    Behavior on shown { NumberAnimation { duration: ring.lush ? 1000 : 500; easing.type: ring.lush ? Easing.OutQuint : Easing.OutCubic } }

    antialiasing: true
    renderStrategy: Canvas.Cooperative

    onShownChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onColorAChanged: requestPaint()
    onColorBChanged: requestPaint()
    onLushChanged: requestPaint()
    Connections {
        target: ThemeBackend
        function onBaseChanged() { ring.requestPaint(); }
        function onTextChanged() { ring.requestPaint(); }
    }

    function css(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + (a === undefined ? c.a : a) + ")";
    }

    onPaint: {
        let ctx = getContext("2d");
        ctx.reset();
        let size = Math.min(width, height);
        if (size <= 0) return;
        let cx = width / 2, cy = height / 2;
        let glowPad = ring.lush ? ring.thickness * 0.9 : 0;
        let rad = size / 2 - ring.thickness / 2 - glowPad - 1;
        if (rad <= 1) return;
        let start = -Math.PI / 2;
        let end = start + Math.PI * 2 * ring.shown;

        // track
        ctx.beginPath();
        ctx.arc(cx, cy, rad, 0, Math.PI * 2);
        ctx.lineWidth = ring.lush ? ring.thickness : 1;
        ctx.strokeStyle = ring.lush ? css(ring.tone.isLight ? Qt.darker(ThemeBackend.base, 1.2) : ThemeBackend.crust, 0.45)
                                    : css(ring.tone.hairline);
        ctx.stroke();

        if (ring.shown <= 0.002) return;

        if (ring.lush) {
            // glow
            if (!ring.tone.isLight) {
                ctx.beginPath();
                ctx.arc(cx, cy, rad, start, end);
                ctx.lineCap = "round";
                ctx.lineWidth = ring.thickness * 2.2;
                ctx.strokeStyle = css(ring.colorB, 0.12);
                ctx.stroke();
            }
            let g = ctx.createConicalGradient(cx, cy, -Math.PI / 2);
            // symmetric stops: correct whichever way the conical sweep runs
            g.addColorStop(0.0, css(ring.colorA, 1));
            g.addColorStop(0.5, css(ring.colorB, 1));
            g.addColorStop(1.0, css(ring.colorA, 1));
            ctx.beginPath();
            ctx.arc(cx, cy, rad, start, end);
            ctx.lineCap = "round";
            ctx.lineWidth = ring.thickness;
            ctx.strokeStyle = g;
            ctx.stroke();
            // cap
            let ex = cx + rad * Math.cos(end), ey = cy + rad * Math.sin(end);
            ctx.beginPath();
            ctx.arc(ex, ey, ring.thickness * 0.28, 0, Math.PI * 2);
            ctx.fillStyle = css(ring.tone.isLight ? ThemeBackend.base : "#ffffff", 0.85);
            ctx.fill();
        } else {
            ctx.beginPath();
            ctx.arc(cx, cy, rad, start, end);
            ctx.lineCap = "butt";
            ctx.lineWidth = ring.thickness;
            ctx.strokeStyle = css(ring.colorA, 1);
            ctx.stroke();
        }
    }
}
