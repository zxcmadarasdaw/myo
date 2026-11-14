import QtQuick
import "../../"
import "VpnGeometry.js" as Geo

// Connection lines of the VPN Control Studio: from the power button to the four nodes.
// Two canvases: the base (inactive colour) and the lit copy (active colour + glow). Glow,
// fade-out on disconnect and the pulse while connecting only change the lit canvas's
// opacity, so nothing is repainted while they run; a repaint happens on a size, layout,
// style or colour change and during the short draw-in when the page opens. The moving
// light dots are small items placed with Geo.pointAt(). Nothing here takes mouse input.
Item {
    id: root

    property var lay: null                    // Geo.layout(...)
    property var style: ({})                  // VpnAppearance.style
    property string phase: "disconnected"     // VpnService.phase
    property bool active: true                // page visible: animations run only then
    property real intro: 1.0                  // 0..1 draw-in progress
    property real unit: 1.0

    readonly property var links: lay ? Geo.links(style.lineStyle || "curved", lay, unit) : []
    readonly property bool animate: style.animate !== false && active
    readonly property real speed: Math.max(0.25, style.animSpeed || 1.0)
    readonly property bool lit: phase === "connected"
    readonly property bool busyPhase: phase === "connecting" || phase === "disconnecting"
    readonly property color errorColor: ThemeBackend.red

    enabled: false                            // never a mouse target

    // lit level: 0 off, 1 connected; the pulse while connecting moves between 0.2 and 0.65
    property real litLevel: lit ? 1.0 : 0.0
    Behavior on litLevel { NumberAnimation { duration: root.lit ? 450 : 700; easing.type: Easing.OutCubic } }
    property real pulse: 0.0
    SequentialAnimation on pulse {
        running: root.busyPhase && root.animate
        loops: Animation.Infinite
        NumberAnimation { from: 0.15; to: 0.65; duration: 700 / root.speed; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.65; to: 0.15; duration: 700 / root.speed; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.pulse = root.busyPhase ? 0.4 : 0.0
    }

    // CSS colour string for the canvas (a QML color may stringify as #AARRGGBB)
    function css(c, a) {
        let q = Qt.lighter(c, 1.0);
        return "rgba(" + Math.round(q.r * 255) + "," + Math.round(q.g * 255) + "," + Math.round(q.b * 255) + ","
            + (a === undefined ? q.a : a).toFixed(3) + ")";
    }

    function strokePath(ctx, link, t) {
        let pts = Geo.partial(link, t);
        if (pts.length < 2) return;
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y);
        ctx.stroke();
    }

    function paintLinks(ctx, color, glow) {
        ctx.reset();
        if (!root.lay) return;
        let st = root.style.lineStyle || "curved";
        let w = Math.max(0.5, (root.style.lineWidth || 1.4)) * root.unit;
        let minimal = st === "minimal";
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        if (minimal) ctx.setLineDash([2, 5]);
        for (let i = 0; i < root.links.length; i++) {
            let link = root.links[i];
            let t = Math.max(0, Math.min(1, root.intro * 1.25 - i * 0.08));
            if (t <= 0) continue;
            if (glow > 0.01 && !minimal) {
                ctx.strokeStyle = root.css(color, 0.10 * glow);
                ctx.lineWidth = w * 7;
                root.strokePath(ctx, link, t);
                ctx.strokeStyle = root.css(color, 0.22 * glow);
                ctx.lineWidth = w * 3.2;
                root.strokePath(ctx, link, t);
            }
            ctx.strokeStyle = root.css(color, 1);
            ctx.lineWidth = minimal ? Math.max(1, w * 0.8) : w;
            root.strokePath(ctx, link, t);
            if (t >= 1) {
                // terminal dot at the node; vias on circuit corners
                ctx.setLineDash([]);
                ctx.fillStyle = root.css(color, 1);
                ctx.beginPath();
                ctx.arc(link.end.x, link.end.y, w * (minimal ? 1.2 : 1.8), 0, Math.PI * 2);
                ctx.fill();
                for (let c = 0; c < link.corners.length; c++) {
                    ctx.beginPath();
                    ctx.arc(link.corners[c].x, link.corners[c].y, w * 1.6, 0, Math.PI * 2);
                    ctx.stroke();
                }
                if (minimal) ctx.setLineDash([2, 5]);
            }
        }
    }

    function repaintAll() {
        base.requestPaint();
        litCanvas.requestPaint();
    }

    onLinksChanged: repaintAll()
    onStyleChanged: repaintAll()
    onIntroChanged: repaintAll()
    onWidthChanged: repaintAll()
    onHeightChanged: repaintAll()

    Canvas {
        id: base
        anchors.fill: parent
        opacity: 0.85 - 0.5 * root.litLevel
        onPaint: root.paintLinks(getContext("2d"), root.style.inactive || "#5c6370", 0)
    }

    Canvas {
        id: litCanvas
        anchors.fill: parent
        opacity: Math.max(root.litLevel, root.busyPhase ? root.pulse : 0)
        visible: opacity > 0.01
        onPaint: root.paintLinks(getContext("2d"), root.style.active || "#7fd4ff", root.style.glow || 0)
    }

    // error: the lines flash red once, then go back to the inactive look
    Canvas {
        id: errorCanvas
        anchors.fill: parent
        property real level: 0
        opacity: level
        visible: level > 0.01
        onPaint: root.paintLinks(getContext("2d"), root.errorColor, 0.4)
        NumberAnimation on level { id: errorFlash; running: false; from: 0.8; to: 0; duration: 1400; easing.type: Easing.InCubic }
    }
    Connections {
        target: root
        function onPhaseChanged() {
            if (root.phase === "error") {
                errorCanvas.requestPaint();
                errorFlash.restart();
            }
        }
    }

    // moving light dots: outward while connecting, a calm flow while connected
    Repeater {
        model: root.links.length
        delegate: Item {
            id: dotHolder
            required property int index
            readonly property var link: root.links[index] || null
            readonly property bool running: root.animate && root.intro >= 1 && (root.busyPhase || root.lit)
            readonly property int count: (root.style.lineStyle === "flow" && root.lit) ? 2 : 1
            anchors.fill: parent
            visible: running
            property real t: 0
            NumberAnimation on t {
                running: dotHolder.running
                from: 0; to: 1
                loops: Animation.Infinite
                duration: (root.busyPhase ? 1100 : 2600 + dotHolder.index * 240) / root.speed
            }
            Repeater {
                model: dotHolder.count
                delegate: Rectangle {
                    required property int index
                    readonly property real tt: {
                        let v = dotHolder.t + index / dotHolder.count;
                        v = v - Math.floor(v);
                        return root.phase === "disconnecting" ? 1 - v : v;
                    }
                    readonly property var p: Geo.pointAt(dotHolder.link, tt)
                    readonly property real size: Math.max(4, (root.style.lineWidth || 1.4) * 3.2) * root.unit
                    width: size
                    height: size
                    radius: size / 2
                    x: p.x - size / 2
                    y: p.y - size / 2
                    color: root.style.active || "#7fd4ff"
                    opacity: Math.sin(Math.PI * tt) * (root.lit ? 0.95 : 0.8)
                    Rectangle {                   // soft halo
                        anchors.centerIn: parent
                        width: parent.width * 2.6
                        height: width
                        radius: width / 2
                        color: parent.color
                        opacity: 0.18 + 0.25 * (root.style.glow || 0)
                    }
                }
            }
        }
    }
}
