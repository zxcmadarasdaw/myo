import QtQuick
import "../../../"

// History line of real samples (0..1). Repaints only when a sample arrives and the
// face is visible; there is no timer of its own.
Canvas {
    id: spark

    property var values: []
    property color color: ThemeBackend.mauve
    property real fillOpacity: 0.18
    property real lineWidth: 1.5
    property bool stepped: false
    property int capacity: 48

    onValuesChanged: if (visible) requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onColorChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const data = (values || []).slice(-capacity);
        if (data.length < 2 || width < 4 || height < 4) return;
        const step = width / (capacity - 1);
        const x0 = width - (data.length - 1) * step;
        const y = v => height - 1 - Math.max(0, Math.min(1, v)) * (height - 2);
        ctx.beginPath();
        ctx.moveTo(x0, y(data[0]));
        for (let i = 1; i < data.length; i++) {
            const x = x0 + i * step;
            if (stepped) ctx.lineTo(x, y(data[i - 1]));
            ctx.lineTo(x, y(data[i]));
        }
        ctx.lineWidth = lineWidth;
        ctx.strokeStyle = color;
        ctx.stroke();
        if (fillOpacity > 0) {
            ctx.lineTo(width, height);
            ctx.lineTo(x0, height);
            ctx.closePath();
            ctx.fillStyle = Qt.alpha(color, fillOpacity);
            ctx.fill();
        }
    }
}
