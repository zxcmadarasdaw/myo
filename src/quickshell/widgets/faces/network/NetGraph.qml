import QtQuick
import "../../../"

// Live download / upload graph. New samples slide in from the right instead
// of jumping, and the vertical scale eases to the new peak.
Canvas {
    id: graph

    property var rxData: []
    property var txData: []
    property color rxColor: ThemeBackend.blue
    property color txColor: ThemeBackend.mauve
    property real lineWidth: 2
    property real fillOpacity: 0.22
    property int sampleInterval: 1000
    property int capacity: 40
    property bool glow: false

    property real peak: 1024
    Behavior on peak { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

    // 1 → 0 after each sample: the curve slides left by one step
    property real slide: 0
    NumberAnimation on slide {
        id: slideAnim
        running: false
        from: 1
        to: 0
        duration: Math.max(150, graph.sampleInterval * 0.95)
        easing.type: Easing.Linear
    }

    function maxOf(a) {
        let m = 0;
        for (let i = 0; i < a.length; i++) if (a[i] > m) m = a[i];
        return m;
    }

    onRxDataChanged: {
        let m = Math.max(maxOf(rxData.slice(-capacity)), maxOf(txData.slice(-capacity)), 1024);
        peak = m * 1.15;
        if (visible) slideAnim.restart();
        requestPaint();
    }
    onSlideChanged: requestPaint()
    onPeakChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onRxColorChanged: requestPaint()

    function drawSeries(ctx, data, color) {
        let pts = data.slice(-capacity);
        if (pts.length < 2) return;
        let step = width / (capacity - 1);
        let offset = width - (pts.length - 1) * step + slide * step;
        let h = height - lineWidth;
        let y = v => h - Math.min(1, v / peak) * (h - lineWidth) + lineWidth / 2;

        ctx.beginPath();
        ctx.moveTo(offset, y(pts[0]));
        for (let i = 1; i < pts.length; i++) {
            let x0 = offset + (i - 1) * step, x1 = offset + i * step;
            let mx = (x0 + x1) / 2;
            ctx.bezierCurveTo(mx, y(pts[i - 1]), mx, y(pts[i]), x1, y(pts[i]));
        }
        ctx.lineWidth = lineWidth;
        ctx.strokeStyle = color;
        if (glow) {
            ctx.shadowColor = color;
            ctx.shadowBlur = 8;
        }
        ctx.stroke();
        ctx.shadowBlur = 0;

        ctx.lineTo(offset + (pts.length - 1) * step, height);
        ctx.lineTo(offset, height);
        ctx.closePath();
        let grad = ctx.createLinearGradient(0, 0, 0, height);
        grad.addColorStop(0, Qt.rgba(color.r, color.g, color.b, fillOpacity));
        grad.addColorStop(1, Qt.rgba(color.r, color.g, color.b, 0));
        ctx.fillStyle = grad;
        ctx.fill();
    }

    onPaint: {
        let ctx = getContext("2d");
        ctx.reset();
        ctx.save();
        ctx.beginPath();
        ctx.rect(0, 0, width, height);
        ctx.clip();
        drawSeries(ctx, txData, txColor);
        drawSeries(ctx, rxData, rxColor);
        ctx.restore();
    }
}
