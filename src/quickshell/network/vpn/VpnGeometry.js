.pragma library
// Geometry of the VPN Control Studio: where the power button and the four nodes sit for
// each layout, and the path of every connection line for each line style. Pure functions
// (no QML), recomputed only when the size, layout or style changes; the animated signal
// dots read positions with pointAt() instead of repainting the canvas.

var NODE_IDS = ["ip", "location", "server", "protocol"];

// Positions are fractions of the composition rectangle (node centres).
var LAYOUTS = {
    centered: { button: [0.5, 0.27], scale: 0.40,
                ip: [0.17, 0.60], location: [0.83, 0.60], protocol: [0.31, 0.90], server: [0.69, 0.90] },
    vertical: { button: [0.5, 0.15], scale: 0.27,
                ip: [0.27, 0.42], location: [0.73, 0.57], protocol: [0.27, 0.74], server: [0.73, 0.90] },
    horizontal: { button: [0.21, 0.5], scale: 0.42,
                  ip: [0.72, 0.13], location: [0.72, 0.38], server: [0.72, 0.63], protocol: [0.72, 0.88] },
    compact: { button: [0.5, 0.24], scale: 0.32,
               ip: [0.27, 0.62], location: [0.73, 0.62], protocol: [0.27, 0.88], server: [0.73, 0.88] },
    expanded: { button: [0.5, 0.48], scale: 0.42,
                ip: [0.15, 0.12], location: [0.85, 0.12], protocol: [0.15, 0.86], server: [0.85, 0.86] }
};

function resolveLayout(name, w, h, unit) {
    var u = unit || 1;
    if (name === "auto" || !LAYOUTS[name])
        return (w < 520 * u || h < 300 * u) ? "compact" : "centered";
    return name;
}

// -> { name, button: {cx, cy, d}, nodeW, nodeH, nodes: {id: {cx, cy, x, y}} }
function layout(name, w, h, unit) {
    var u = unit || 1;
    var n = resolveLayout(name, w, h, u);
    var L = LAYOUTS[n];
    var nodeW = Math.max(120 * u, Math.min(210 * u, w * (n === "horizontal" ? 0.40 : 0.29)));
    var nodeH = (n === "compact" ? 50 : 58) * u;
    var d = Math.max(84 * u, Math.min(180 * u, Math.min(w, h) * L.scale));
    if (n === "horizontal") d = Math.min(d, w * 0.30);
    var out = { name: n, button: { cx: L.button[0] * w, cy: L.button[1] * h, d: d }, nodeW: nodeW, nodeH: nodeH, nodes: {} };
    // the button stays fully inside too
    out.button.cx = Math.max(d / 2 + 2, Math.min(w - d / 2 - 2, out.button.cx));
    out.button.cy = Math.max(d / 2 + 2, Math.min(h - d / 2 - 2, out.button.cy));
    for (var i = 0; i < NODE_IDS.length; i++) {
        var id = NODE_IDS[i];
        var cx = L[id][0] * w;
        var cy = L[id][1] * h;
        cx = Math.max(nodeW / 2 + 2, Math.min(w - nodeW / 2 - 2, cx));
        cy = Math.max(nodeH / 2 + 2, Math.min(h - nodeH / 2 - 2, cy));
        out.nodes[id] = { cx: cx, cy: cy, x: cx - nodeW / 2, y: cy - nodeH / 2 };
    }
    return out;
}

// Where a line meets a node: the middle of the edge that faces the button.
function attach(node, from, nw, nh) {
    var dx = from.x - node.cx;
    var dy = from.y - node.cy;
    if (Math.abs(dy) * nw >= Math.abs(dx) * nh)
        return { x: node.cx, y: node.cy + (dy < 0 ? -nh / 2 : nh / 2), side: "v" };
    return { x: node.cx + (dx < 0 ? -nw / 2 : nw / 2), y: node.cy, side: "h" };
}

function bezier(p0, p1, p2, p3, steps) {
    var pts = [];
    for (var i = 0; i <= steps; i++) {
        var t = i / steps, a = 1 - t;
        pts.push({
            x: a * a * a * p0.x + 3 * a * a * t * p1.x + 3 * a * t * t * p2.x + t * t * t * p3.x,
            y: a * a * a * p0.y + 3 * a * a * t * p1.y + 3 * a * t * t * p2.y + t * t * t * p3.y
        });
    }
    return pts;
}

// Orthogonal route with 45° chamfered corners (circuit board look).
function chamfer(points, c) {
    if (points.length < 3) return { pts: points, corners: [] };
    var out = [points[0]];
    var corners = [];
    for (var i = 1; i < points.length - 1; i++) {
        var a = points[i - 1], b = points[i], d = points[i + 1];
        var l1 = Math.hypot(b.x - a.x, b.y - a.y);
        var l2 = Math.hypot(d.x - b.x, d.y - b.y);
        if (l1 < 0.5 || l2 < 0.5) { out.push(b); continue; }
        var k = Math.min(c, l1 / 2.5, l2 / 2.5);
        if (k < 1) { out.push(b); continue; }
        out.push({ x: b.x + (a.x - b.x) / l1 * k, y: b.y + (a.y - b.y) / l1 * k });
        out.push({ x: b.x + (d.x - b.x) / l2 * k, y: b.y + (d.y - b.y) / l2 * k });
        corners.push(b);
    }
    out.push(points[points.length - 1]);
    return { pts: out, corners: corners };
}

function measure(pts) {
    var acc = [0];
    for (var i = 1; i < pts.length; i++)
        acc.push(acc[i - 1] + Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y));
    return acc;
}

// One line from the button to a node -> { id, pts, acc, len, corners, end }
function linkPath(style, button, node, nw, nh, unit) {
    var u = unit || 1;
    var c = { x: button.cx, y: button.cy };
    var end = attach(node, c, nw, nh);
    var dx = end.x - c.x, dy = end.y - c.y;
    var dist = Math.hypot(dx, dy) || 1;
    var r = button.d / 2 + 6 * u;
    var pts, corners = [];
    if (style === "curved" || style === "flow") {
        var start, p1, p2;
        if (end.side === "v") {
            var down = dy >= 0 ? 1 : -1;
            start = { x: c.x + dx / dist * r * 0.35, y: c.y + down * r * 0.94 };
            var my = (end.y - start.y) * 0.62;
            p1 = { x: start.x, y: start.y + my };
            p2 = { x: end.x, y: end.y - my };
        } else {
            var side = dx >= 0 ? 1 : -1;
            start = { x: c.x + side * r * 0.94, y: c.y + dy / dist * r * 0.35 };
            var mx = (end.x - start.x) * 0.62;
            p1 = { x: start.x + mx, y: start.y };
            p2 = { x: end.x - mx, y: end.y };
        }
        pts = bezier(start, p1, p2, end, 32);
    } else if (style === "circuit") {
        var s0, route;
        if (end.side === "v") {
            var vdir = dy >= 0 ? 1 : -1;
            s0 = { x: c.x, y: c.y + vdir * r };
            var midY = s0.y + (end.y - s0.y) * 0.45;
            route = [s0, { x: s0.x, y: midY }, { x: end.x, y: midY }, end];
        } else {
            var hdir = dx >= 0 ? 1 : -1;
            s0 = { x: c.x + hdir * r, y: c.y };
            var midX = s0.x + (end.x - s0.x) * 0.45;
            route = [s0, { x: midX, y: s0.y }, { x: midX, y: end.y }, end];
        }
        var ch = chamfer(route, 12 * u);
        pts = ch.pts;
        corners = ch.corners;
    } else {                                     // straight, minimal
        pts = [{ x: c.x + dx / dist * r, y: c.y + dy / dist * r }, { x: end.x, y: end.y }];
    }
    var acc = measure(pts);
    return { pts: pts, acc: acc, len: acc[acc.length - 1], corners: corners, end: end };
}

function links(style, lay, unit) {
    var out = [];
    for (var i = 0; i < NODE_IDS.length; i++) {
        var id = NODE_IDS[i];
        var p = linkPath(style, lay.button, lay.nodes[id], lay.nodeW, lay.nodeH, unit);
        p.id = id;
        out.push(p);
    }
    return out;
}

// Point at fraction t (0..1) of a path's length.
function pointAt(link, t) {
    if (!link || !link.pts || link.pts.length === 0) return { x: -100, y: -100 };
    var target = Math.max(0, Math.min(1, t)) * link.len;
    var acc = link.acc;
    for (var i = 1; i < acc.length; i++) {
        if (acc[i] >= target) {
            var seg = acc[i] - acc[i - 1] || 1;
            var k = (target - acc[i - 1]) / seg;
            var a = link.pts[i - 1], b = link.pts[i];
            return { x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k };
        }
    }
    var last = link.pts[link.pts.length - 1];
    return { x: last.x, y: last.y };
}

// Points of the first fraction t of a path (the draw-in of the intro).
function partial(link, t) {
    if (t >= 1) return link.pts;
    var target = Math.max(0, t) * link.len;
    var out = [link.pts[0]];
    for (var i = 1; i < link.pts.length; i++) {
        if (link.acc[i] <= target) {
            out.push(link.pts[i]);
        } else {
            out.push(pointAt(link, t));
            break;
        }
    }
    return out;
}

// Does any node rectangle overlap the button or another node? (used by the tests)
function overlaps(lay) {
    var b = lay.button;
    var rects = [{ x: b.cx - b.d / 2, y: b.cy - b.d / 2, w: b.d, h: b.d }];
    for (var i = 0; i < NODE_IDS.length; i++) {
        var n = lay.nodes[NODE_IDS[i]];
        rects.push({ x: n.x, y: n.y, w: lay.nodeW, h: lay.nodeH });
    }
    for (var a = 0; a < rects.length; a++)
        for (var c = a + 1; c < rects.length; c++) {
            var A = rects[a], B = rects[c];
            if (A.x < B.x + B.w && B.x < A.x + A.w && A.y < B.y + B.h && B.y < A.y + A.h) return true;
        }
    return false;
}
