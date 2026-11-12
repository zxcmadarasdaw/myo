.pragma library
// Infinite desktop canvas: pure logic, no QML dependencies.
// The same file is loaded by QML (as a library) and by node (tests/canvas).
//
// Camera model
//   camera = { x, y, zoom }: x/y is the world point shown in the top-left corner
//   of the monitor, zoom is the on-screen size of one world pixel.
//   screen = (world - camera) * zoom
//   The home camera { 0, 0, 1 } maps world coordinates to screen coordinates 1:1,
//   which is exactly how Serpantinum stored widget positions before the canvas
//   existed, so old layouts stay valid without any migration.

var SCHEMA_VERSION = 1;

var ZOOM_MIN = 0.2;
var ZOOM_MAX = 4.0;
var HOME_EPSILON = 0.01;

var MAX_COMPOSITIONS = 200;
var MAX_COMPOSITION_WIDGETS = 500;
var MAX_NAME_LENGTH = 64;

var DEFAULTS = {
    enabled: true,
    sensitivity: 1.0,
    inertia: true,
    friction: 5.0,
    wheelAction: "zoom",
    zoomStep: 1.12,
    gridSize: 20,
    snapToGrid: false,
    snapToGuides: true,
    minimap: "auto",
    minimapCorner: "bottom-right",
    dragToPan: true
};

var LIMITS = {
    sensitivity: [0.2, 5.0],
    friction: [1.0, 20.0],
    zoomStep: [1.02, 1.5],
    gridSize: [4, 400]
};

var ENUMS = {
    wheelAction: ["zoom", "pan", "none"],
    minimap: ["auto", "always", "never"],
    minimapCorner: ["top-left", "top-right", "bottom-left", "bottom-right"]
};

function clamp(v, lo, hi) {
    return Math.min(hi, Math.max(lo, v));
}

function num(v, fallback) {
    if (typeof v === "string" && v.trim() !== "") v = Number(v);
    return (typeof v === "number" && isFinite(v)) ? v : fallback;
}

function safeName(name) {
    return String(name === undefined || name === null ? "" : name).replace(/[^a-zA-Z0-9_-]/g, "_");
}

// ---------------------------------------------------------------- camera

function homeCamera() {
    return { x: 0, y: 0, zoom: 1 };
}

function normalizeCamera(c, zmin, zmax) {
    if (!c || typeof c !== "object") return homeCamera();
    return {
        x: num(c.x, 0),
        y: num(c.y, 0),
        zoom: clamp(num(c.zoom, 1), zmin || ZOOM_MIN, zmax || ZOOM_MAX)
    };
}

function isHome(cam) {
    return Math.abs(cam.x) < HOME_EPSILON && Math.abs(cam.y) < HOME_EPSILON && Math.abs(cam.zoom - 1) < 0.0005;
}

function worldToScreen(cam, wx, wy) {
    return { x: (wx - cam.x) * cam.zoom, y: (wy - cam.y) * cam.zoom };
}

function screenToWorld(cam, sx, sy) {
    return { x: sx / cam.zoom + cam.x, y: sy / cam.zoom + cam.y };
}

// Visible part of the world for a viewW x viewH monitor.
function viewRect(cam, viewW, viewH) {
    return { x: cam.x, y: cam.y, w: viewW / cam.zoom, h: viewH / cam.zoom };
}

// Drag by (dx, dy) screen pixels: the content follows the pointer.
function panBy(cam, dx, dy, sensitivity) {
    var s = num(sensitivity, 1);
    return { x: cam.x - dx * s / cam.zoom, y: cam.y - dy * s / cam.zoom, zoom: cam.zoom };
}

// Zoom by factor keeping the world point under screen point (sx, sy) in place.
function zoomAt(cam, sx, sy, factor, zmin, zmax) {
    var z = clamp(cam.zoom * num(factor, 1), zmin || ZOOM_MIN, zmax || ZOOM_MAX);
    var w = screenToWorld(cam, sx, sy);
    return { x: w.x - sx / z, y: w.y - sy / z, zoom: z };
}

function setZoomAt(cam, sx, sy, zoom, zmin, zmax) {
    return zoomAt(cam, sx, sy, num(zoom, 1) / cam.zoom, zmin, zmax);
}

// Camera that shows world point (wx, wy) in the middle of the monitor.
function centerOn(wx, wy, viewW, viewH, zoom) {
    var z = clamp(num(zoom, 1), ZOOM_MIN, ZOOM_MAX);
    return { x: wx - viewW / (2 * z), y: wy - viewH / (2 * z), zoom: z };
}

// Camera that fits rect into the monitor with padding (screen pixels).
// Never zooms in past 1:1 - a single small widget should not fill the screen.
function fitRect(rect, viewW, viewH, padding, zmin, zmax) {
    if (!rect || !(rect.w > 0) || !(rect.h > 0) || !(viewW > 0) || !(viewH > 0)) return homeCamera();
    var pad = Math.max(0, num(padding, 0));
    var availW = Math.max(1, viewW - pad * 2);
    var availH = Math.max(1, viewH - pad * 2);
    var z = clamp(Math.min(availW / rect.w, availH / rect.h), zmin || ZOOM_MIN, Math.min(zmax || ZOOM_MAX, 1));
    return centerOn(rect.x + rect.w / 2, rect.y + rect.h / 2, viewW, viewH, z);
}

// The monitor changed size (new resolution, scale, rotation). Widgets keep their
// world coordinates; the camera keeps looking at the same world point in the
// middle of the monitor. The home camera stays home so a plain legacy desktop
// behaves exactly as it did before.
function onViewportResize(cam, oldW, oldH, newW, newH) {
    if (!(oldW > 0) || !(oldH > 0) || !(newW > 0) || !(newH > 0)) return cam;
    if (isHome(cam)) return homeCamera();
    return {
        x: cam.x + (oldW - newW) / (2 * cam.zoom),
        y: cam.y + (oldH - newH) / (2 * cam.zoom),
        zoom: cam.zoom
    };
}

// ---------------------------------------------------------------- motion

// Exponential velocity decay. Velocity is in screen px/s, dt in seconds.
// Returns the screen-space displacement of this step and the new velocity.
function inertiaStep(vx, vy, dt, friction) {
    var k = Math.max(0.01, num(friction, DEFAULTS.friction));
    var t = clamp(num(dt, 0), 0, 0.1);
    var decay = Math.exp(-k * t);
    var travel = (1 - decay) / k;
    var nvx = vx * decay;
    var nvy = vy * decay;
    var done = Math.sqrt(nvx * nvx + nvy * nvy) < 12;
    return { dx: vx * travel, dy: vy * travel, vx: done ? 0 : nvx, vy: done ? 0 : nvy, done: done };
}

// Critically damped spring towards target (no overshoot). Returns { value, velocity }.
function smoothDamp(current, target, velocity, smoothTime, dt) {
    var st = Math.max(0.0001, smoothTime);
    var t = clamp(num(dt, 0), 0, 0.1);
    var omega = 2 / st;
    var x = omega * t;
    var exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
    var change = current - target;
    var temp = (velocity + omega * change) * t;
    var newVel = (velocity - omega * temp) * exp;
    var value = target + (change + temp) * exp;
    if ((target - current > 0) === (value > target)) {
        value = target;
        newVel = 0;
    }
    return { value: value, velocity: newVel };
}

// One frame of an animated camera flight. state = { x, y, zoom, vx, vy, vz }.
// Zoom is interpolated in log space so zooming in and out feels symmetric.
function flyStep(state, target, smoothTime, dt) {
    var sx = smoothDamp(state.x, target.x, state.vx || 0, smoothTime, dt);
    var sy = smoothDamp(state.y, target.y, state.vy || 0, smoothTime, dt);
    var sz = smoothDamp(Math.log(state.zoom), Math.log(target.zoom), state.vz || 0, smoothTime, dt);
    var zoom = Math.exp(sz.value);
    var done = Math.abs(sx.value - target.x) * zoom < 0.25
        && Math.abs(sy.value - target.y) * zoom < 0.25
        && Math.abs(zoom - target.zoom) < 0.0005;
    if (done) return { x: target.x, y: target.y, zoom: target.zoom, vx: 0, vy: 0, vz: 0, done: true };
    return { x: sx.value, y: sy.value, zoom: zoom, vx: sx.velocity, vy: sy.velocity, vz: sz.velocity, done: false };
}

// ---------------------------------------------------------------- geometry

function isQuarterTurned(rotation) {
    return Math.abs(Math.round(num(rotation, 0))) % 180 !== 0;
}

// Axis-aligned world box of a widget record (wX, wY, wWidth, wHeight, wRotation).
// wX / wY always address the top-left corner of that box, rotation swaps the sides.
function widgetBox(w) {
    var turned = isQuarterTurned(w.wRotation);
    var ww = Math.max(1, num(w.wWidth, 1));
    var wh = Math.max(1, num(w.wHeight, 1));
    return { x: num(w.wX, 0), y: num(w.wY, 0), w: turned ? wh : ww, h: turned ? ww : wh };
}

function unionRect(a, b) {
    if (!a) return b ? { x: b.x, y: b.y, w: b.w, h: b.h } : null;
    if (!b) return { x: a.x, y: a.y, w: a.w, h: a.h };
    var x0 = Math.min(a.x, b.x), y0 = Math.min(a.y, b.y);
    var x1 = Math.max(a.x + a.w, b.x + b.w), y1 = Math.max(a.y + a.h, b.y + b.h);
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
}

function boundsOf(widgets) {
    var out = null;
    if (!widgets) return out;
    for (var i = 0; i < widgets.length; i++) {
        if (widgets[i]) out = unionRect(out, widgetBox(widgets[i]));
    }
    return out;
}

function rectsIntersect(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

function normalizeRect(x0, y0, x1, y1) {
    return { x: Math.min(x0, x1), y: Math.min(y0, y1), w: Math.abs(x1 - x0), h: Math.abs(y1 - y0) };
}

// Screen rectangle of a world box.
function screenRect(box, cam) {
    return { x: (box.x - cam.x) * cam.zoom, y: (box.y - cam.y) * cam.zoom, w: box.w * cam.zoom, h: box.h * cam.zoom };
}

// Is any part of the world box on the monitor (with a margin in screen pixels)?
function isOnScreen(box, cam, viewW, viewH, margin) {
    var m = num(margin, 0);
    var r = screenRect(box, cam);
    return r.x < viewW + m && r.x + r.w > -m && r.y < viewH + m && r.y + r.h > -m;
}

function widgetsInRect(widgets, rect) {
    var ids = [];
    for (var i = 0; i < widgets.length; i++) {
        if (rectsIntersect(widgetBox(widgets[i]), rect)) ids.push(String(widgets[i].wId));
    }
    return ids;
}

function snap(v, step) {
    var s = num(step, 0);
    if (!(s > 0)) return v;
    return Math.round(v / s) * s;
}

// Grid step that is still readable on screen: doubles until one cell is at
// least minPixels wide. Widgets always snap to the real step.
function displayGridStep(step, zoom, minPixels) {
    var s = Math.max(1, num(step, DEFAULTS.gridSize));
    var min = num(minPixels, 10);
    var guard = 0;
    while (s * zoom < min && guard++ < 24) s *= 2;
    return s;
}

// ---------------------------------------------------------------- minimap

// Fits world rect `area` into a mapW x mapH box. Returns the transform
// mini = (world - origin) * scale + offset.
function minimapTransform(area, mapW, mapH, padding) {
    var pad = num(padding, 0);
    var w = Math.max(1, area ? area.w : 1), h = Math.max(1, area ? area.h : 1);
    var scale = Math.min((mapW - pad * 2) / w, (mapH - pad * 2) / h);
    if (!(scale > 0) || !isFinite(scale)) scale = 1;
    return {
        scale: scale,
        originX: area ? area.x : 0,
        originY: area ? area.y : 0,
        offsetX: (mapW - w * scale) / 2,
        offsetY: (mapH - h * scale) / 2
    };
}

function worldToMini(t, wx, wy) {
    return { x: (wx - t.originX) * t.scale + t.offsetX, y: (wy - t.originY) * t.scale + t.offsetY };
}

function miniToWorld(t, mx, my) {
    return { x: (mx - t.offsetX) / t.scale + t.originX, y: (my - t.offsetY) / t.scale + t.originY };
}

// Area the minimap has to show: every widget, the current view and the home screen.
function minimapArea(widgets, cam, viewW, viewH) {
    var area = unionRect(boundsOf(widgets), viewRect(cam, viewW, viewH));
    area = unionRect(area, { x: 0, y: 0, w: viewW, h: viewH });
    var mx = area.w * 0.04, my = area.h * 0.04;
    return { x: area.x - mx, y: area.y - my, w: area.w + mx * 2, h: area.h + my * 2 };
}

// ---------------------------------------------------------------- search

// names: { type: localized name }. Returns widgets ordered by relevance, each as
// { wId, wType, label, score, box }.
function searchWidgets(widgets, query, names) {
    var q = String(query || "").trim().toLowerCase();
    var out = [];
    if (!widgets) return out;
    for (var i = 0; i < widgets.length; i++) {
        var w = widgets[i];
        if (!w) continue;
        var type = String(w.wType || "");
        var label = (names && names[type]) ? String(names[type]) : type;
        var hay = [label, type, String(w.wVariant || ""), String(w.wId || ""), String(w.wGroup || "")];
        var score = q === "" ? 1 : 0;
        for (var j = 0; j < hay.length && q !== ""; j++) {
            var h = hay[j].toLowerCase();
            if (h === "") continue;
            var s = 0;
            if (h === q) s = 100;
            else if (h.indexOf(q) === 0) s = 60;
            else if (h.indexOf(q) > 0) s = 30;
            if (s > 0) score = Math.max(score, s - j);
        }
        if (score > 0) out.push({ wId: String(w.wId), wType: type, label: label, score: score, box: widgetBox(w) });
    }
    out.sort(function (a, b) {
        if (b.score !== a.score) return b.score - a.score;
        if (a.box.y !== b.box.y) return a.box.y - b.box.y;
        return a.box.x - b.box.x;
    });
    return out;
}

// ---------------------------------------------------------------- settings

function normalizeSettingValues(raw) {
    var out = {};
    if (!raw || typeof raw !== "object") return out;
    for (var key in DEFAULTS) {
        if (!Object.prototype.hasOwnProperty.call(raw, key)) continue;
        var v = raw[key];
        var def = DEFAULTS[key];
        if (typeof def === "boolean") {
            if (typeof v === "boolean") out[key] = v;
        } else if (typeof def === "number") {
            var n = num(v, NaN);
            if (isFinite(n)) out[key] = LIMITS[key] ? clamp(n, LIMITS[key][0], LIMITS[key][1]) : n;
        } else if (ENUMS[key]) {
            if (ENUMS[key].indexOf(v) >= 0) out[key] = v;
        }
    }
    return out;
}

// settings.json "canvas" -> { ...global values, monitors: { name: { ...overrides } } }
function normalizeSettings(raw) {
    var out = normalizeSettingValues(raw);
    out.monitors = {};
    var mons = (raw && typeof raw === "object") ? raw.monitors : null;
    if (mons && typeof mons === "object" && !Array.isArray(mons)) {
        for (var name in mons) {
            if (!Object.prototype.hasOwnProperty.call(mons, name)) continue;
            var o = normalizeSettingValues(mons[name]);
            if (Object.keys(o).length > 0) out.monitors[safeName(name)] = o;
        }
    }
    return out;
}

// Effective settings of one monitor: monitor override > global > default.
function resolveSettings(settings, monitor) {
    var out = {};
    var key;
    for (key in DEFAULTS) out[key] = DEFAULTS[key];
    var s = settings || {};
    for (key in DEFAULTS) {
        if (Object.prototype.hasOwnProperty.call(s, key)) out[key] = s[key];
    }
    var o = (s.monitors && s.monitors[safeName(monitor)]) || null;
    out.hasOverride = !!o;
    if (o) {
        for (key in o) {
            if (Object.prototype.hasOwnProperty.call(DEFAULTS, key)) out[key] = o[key];
        }
    }
    return out;
}

// ---------------------------------------------------------------- state file

// widgets/<monitor>/canvas.json
function normalizeState(raw) {
    var out = { schema_version: SCHEMA_VERSION, camera: homeCamera(), screen: { w: 0, h: 0 } };
    if (!raw || typeof raw !== "object") return out;
    // Written by a newer build: do not touch (caller keeps the file as is).
    if (typeof raw.schema_version === "number" && raw.schema_version > SCHEMA_VERSION) return null;
    out.camera = normalizeCamera(raw.camera);
    if (raw.screen && typeof raw.screen === "object") {
        out.screen = { w: Math.max(0, num(raw.screen.w, 0)), h: Math.max(0, num(raw.screen.h, 0)) };
    }
    return out;
}

function parseState(text) {
    if (typeof text !== "string" || text.trim() === "") return normalizeState(null);
    try {
        return normalizeState(JSON.parse(text));
    } catch (e) {
        return normalizeState(null);
    }
}

function serializeState(cam, viewW, viewH) {
    var c = normalizeCamera(cam);
    return JSON.stringify({
        schema_version: SCHEMA_VERSION,
        camera: { x: Math.round(c.x * 100) / 100, y: Math.round(c.y * 100) / 100, zoom: Math.round(c.zoom * 10000) / 10000 },
        screen: { w: Math.round(num(viewW, 0)), h: Math.round(num(viewH, 0)) }
    }, null, 2) + "\n";
}

// ---------------------------------------------------------------- groups

function newId(prefix, taken) {
    var id;
    var guard = 0;
    do {
        id = prefix + "_" + Date.now().toString(36) + "_" + Math.floor(Math.random() * 1e6).toString(36);
    } while (taken && taken[id] && guard++ < 50);
    return id;
}

function groupOf(widgets, id) {
    for (var i = 0; i < widgets.length; i++) {
        if (String(widgets[i].wId) === String(id)) return widgets[i].wGroup ? String(widgets[i].wGroup) : "";
    }
    return "";
}

function groupMembers(widgets, group) {
    var ids = [];
    if (!group) return ids;
    for (var i = 0; i < widgets.length; i++) {
        if (String(widgets[i].wGroup || "") === String(group)) ids.push(String(widgets[i].wId));
    }
    return ids;
}

// Adds every group mate of the given widgets. Order: input ids first.
function expandSelection(widgets, ids) {
    var seen = {};
    var out = [];
    var groups = {};
    var i;
    for (i = 0; i < ids.length; i++) {
        var id = String(ids[i]);
        if (seen[id]) continue;
        seen[id] = true;
        out.push(id);
        var g = groupOf(widgets, id);
        if (g) groups[g] = true;
    }
    for (i = 0; i < widgets.length; i++) {
        var w = widgets[i];
        var wid = String(w.wId);
        if (!seen[wid] && w.wGroup && groups[String(w.wGroup)]) {
            seen[wid] = true;
            out.push(wid);
        }
    }
    return out;
}

// ---------------------------------------------------------------- compositions

var BLOCKED_KEYS = ["__proto__", "constructor", "prototype"];

function sanitizeName(name) {
    var n = String(name === undefined || name === null ? "" : name).replace(/[\u0000-\u001f\u007f]/g, " ").trim();
    if (n.length > MAX_NAME_LENGTH) n = n.substring(0, MAX_NAME_LENGTH).trim();
    return n;
}

// Plain JSON data only: no functions, no prototypes, bounded depth and size.
function sanitizeValue(v, depth) {
    if (v === null) return null;
    var t = typeof v;
    if (t === "string") return v.length > 4096 ? v.substring(0, 4096) : v;
    if (t === "boolean") return v;
    if (t === "number") return isFinite(v) ? v : 0;
    if (t !== "object" || depth > 6) return undefined;
    var i;
    if (Array.isArray(v)) {
        var arr = [];
        for (i = 0; i < v.length && i < 256; i++) {
            var av = sanitizeValue(v[i], depth + 1);
            arr.push(av === undefined ? null : av);
        }
        return arr;
    }
    var out = {};
    var keys = Object.keys(v);
    for (i = 0; i < keys.length && i < 256; i++) {
        if (BLOCKED_KEYS.indexOf(keys[i]) >= 0) continue;
        var ov = sanitizeValue(v[keys[i]], depth + 1);
        if (ov !== undefined) out[keys[i]] = ov;
    }
    return out;
}

var WIDGET_CORE_KEYS = ["wId", "wType", "wVariant", "wX", "wY", "wWidth", "wHeight", "wOpacity", "wRotation", "wImagePath", "wGroup"];
var WIDGET_DROPPED_KEYS = ["id", "type", "variant", "x", "y", "w", "h", "width", "height", "opacity", "rotation",
    "imagePath", "path", "isRemoving", "stretchWidth", "stretchHeight", "wStretchWidth", "wStretchHeight", "objectName"];

function sanitizeWidget(w) {
    if (!w || typeof w !== "object") return null;
    var type = String(w.wType || w.type || "");
    if (!/^[a-zA-Z0-9_-]{1,64}$/.test(type)) return null;
    var out = {
        wId: String(w.wId || ""),
        wType: type,
        wVariant: String(w.wVariant || ""),
        wX: num(w.wX, 0),
        wY: num(w.wY, 0),
        wWidth: clamp(num(w.wWidth, 200), 10, 20000),
        wHeight: clamp(num(w.wHeight, 120), 10, 20000),
        wOpacity: clamp(num(w.wOpacity, 1), 0, 1),
        wRotation: ((Math.round(num(w.wRotation, 0)) % 360) + 360) % 360,
        wImagePath: String(w.wImagePath || ""),
        wGroup: String(w.wGroup || "")
    };
    for (var k in w) {
        if (!Object.prototype.hasOwnProperty.call(w, k)) continue;
        if (WIDGET_CORE_KEYS.indexOf(k) >= 0 || WIDGET_DROPPED_KEYS.indexOf(k) >= 0 || BLOCKED_KEYS.indexOf(k) >= 0) continue;
        if (!/^[a-zA-Z_][a-zA-Z0-9_]{0,63}$/.test(k)) continue;
        var v = sanitizeValue(w[k], 0);
        if (v !== undefined) out[k] = v;
    }
    return out;
}

// Snapshot of some widgets with coordinates relative to their bounding box.
function makeComposition(name, widgets, taken) {
    var list = [];
    for (var i = 0; i < widgets.length && list.length < MAX_COMPOSITION_WIDGETS; i++) {
        var w = sanitizeWidget(widgets[i]);
        if (w) list.push(w);
    }
    if (list.length === 0) return null;
    var b = boundsOf(list);
    for (var j = 0; j < list.length; j++) {
        list[j].wX = Math.round((list[j].wX - b.x) * 100) / 100;
        list[j].wY = Math.round((list[j].wY - b.y) * 100) / 100;
    }
    return {
        id: newId("comp", taken),
        name: sanitizeName(name) || "Composition",
        created: new Date().toISOString(),
        w: Math.round(b.w * 100) / 100,
        h: Math.round(b.h * 100) / 100,
        widgets: list
    };
}

// Widgets of a composition placed with its centre at (cx, cy), with fresh ids
// and fresh group ids (two inserted copies never share a group).
function instantiateComposition(comp, cx, cy, gridStep) {
    var out = [];
    if (!comp || !Array.isArray(comp.widgets)) return out;
    var ox = cx - num(comp.w, 0) / 2;
    var oy = cy - num(comp.h, 0) / 2;
    if (gridStep > 0) {
        ox = snap(ox, gridStep);
        oy = snap(oy, gridStep);
    }
    var groups = {};
    var taken = {};
    for (var i = 0; i < comp.widgets.length; i++) {
        var w = sanitizeWidget(comp.widgets[i]);
        if (!w) continue;
        w.wId = newId("w", taken);
        taken[w.wId] = true;
        w.wX += ox;
        w.wY += oy;
        if (w.wGroup) {
            if (!groups[w.wGroup]) groups[w.wGroup] = newId("g", taken);
            taken[groups[w.wGroup]] = true;
            w.wGroup = groups[w.wGroup];
        }
        out.push(w);
    }
    return out;
}

function normalizeComposition(c, taken) {
    if (!c || typeof c !== "object" || !Array.isArray(c.widgets)) return null;
    var list = [];
    for (var i = 0; i < c.widgets.length && list.length < MAX_COMPOSITION_WIDGETS; i++) {
        var w = sanitizeWidget(c.widgets[i]);
        if (w) list.push(w);
    }
    if (list.length === 0) return null;
    var b = boundsOf(list);
    // Re-base so the stored box always starts at 0,0 whatever the file said.
    for (var j = 0; j < list.length; j++) {
        list[j].wX -= b.x;
        list[j].wY -= b.y;
    }
    var id = (typeof c.id === "string" && /^[a-zA-Z0-9_-]{1,80}$/.test(c.id) && !(taken && taken[c.id])) ? c.id : newId("comp", taken);
    return {
        id: id,
        name: sanitizeName(c.name) || "Composition",
        created: (typeof c.created === "string" && c.created.length <= 40) ? c.created : "",
        w: b.w,
        h: b.h,
        widgets: list
    };
}

// compositions.json -> { schema_version, items: [...] }. Garbage is dropped,
// a file written by a newer build returns null (caller must not overwrite it).
function normalizeCompositions(raw) {
    var out = { schema_version: SCHEMA_VERSION, items: [] };
    if (!raw || typeof raw !== "object") return out;
    if (typeof raw.schema_version === "number" && raw.schema_version > SCHEMA_VERSION) return null;
    var items = Array.isArray(raw.items) ? raw.items : [];
    var taken = {};
    for (var i = 0; i < items.length && out.items.length < MAX_COMPOSITIONS; i++) {
        var c = normalizeComposition(items[i], taken);
        if (c) {
            taken[c.id] = true;
            out.items.push(c);
        }
    }
    return out;
}

function parseCompositions(text) {
    if (typeof text !== "string" || text.trim() === "") return normalizeCompositions(null);
    try {
        return normalizeCompositions(JSON.parse(text));
    } catch (e) {
        return normalizeCompositions(null);
    }
}

function serializeCompositions(items) {
    return JSON.stringify({ schema_version: SCHEMA_VERSION, items: items || [] }, null, 2) + "\n";
}

// Exported for node tests; inside QML (.pragma library) `module` is undefined.
if (typeof module !== "undefined") {
    module.exports = {
        SCHEMA_VERSION: SCHEMA_VERSION, ZOOM_MIN: ZOOM_MIN, ZOOM_MAX: ZOOM_MAX, DEFAULTS: DEFAULTS, LIMITS: LIMITS,
        MAX_COMPOSITIONS: MAX_COMPOSITIONS, MAX_NAME_LENGTH: MAX_NAME_LENGTH,
        clamp: clamp, num: num, safeName: safeName,
        homeCamera: homeCamera, normalizeCamera: normalizeCamera, isHome: isHome,
        worldToScreen: worldToScreen, screenToWorld: screenToWorld, viewRect: viewRect,
        panBy: panBy, zoomAt: zoomAt, setZoomAt: setZoomAt, centerOn: centerOn, fitRect: fitRect,
        onViewportResize: onViewportResize,
        inertiaStep: inertiaStep, smoothDamp: smoothDamp, flyStep: flyStep,
        widgetBox: widgetBox, unionRect: unionRect, boundsOf: boundsOf, rectsIntersect: rectsIntersect,
        normalizeRect: normalizeRect, screenRect: screenRect, isOnScreen: isOnScreen, widgetsInRect: widgetsInRect,
        snap: snap, displayGridStep: displayGridStep,
        minimapTransform: minimapTransform, worldToMini: worldToMini, miniToWorld: miniToWorld, minimapArea: minimapArea,
        searchWidgets: searchWidgets,
        normalizeSettings: normalizeSettings, resolveSettings: resolveSettings,
        normalizeState: normalizeState, parseState: parseState, serializeState: serializeState,
        newId: newId, groupOf: groupOf, groupMembers: groupMembers, expandSelection: expandSelection,
        sanitizeName: sanitizeName, sanitizeWidget: sanitizeWidget,
        makeComposition: makeComposition, instantiateComposition: instantiateComposition,
        normalizeCompositions: normalizeCompositions, parseCompositions: parseCompositions,
        serializeCompositions: serializeCompositions
    };
}
