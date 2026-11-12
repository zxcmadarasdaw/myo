import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "CanvasMath.js" as CM

// Camera of one monitor's infinite canvas.
// One instance per monitor lives in the CanvasState singleton; desktop widgets,
// the widget redactor, the wallpaper window and the minimap all read the same
// object, so they can never disagree about where the desktop currently is.
//
// screen = (world - (viewX, viewY)) * viewZoom
Item {
    id: cam
    visible: false

    required property string monitorName
    property real screenW: 0
    property real screenH: 0
    // Effective settings of this monitor (CanvasMath.resolveSettings).
    property var cfg: CM.resolveSettings(null, "")

    readonly property string safeName: CM.safeName(monitorName)
    readonly property bool active: !!(cfg && cfg.enabled)

    // Stored camera. Kept while the canvas is disabled, so re-enabling it
    // brings the user back to where they were.
    property real rawX: 0
    property real rawY: 0
    property real rawZoom: 1

    // Camera everybody renders with. Disabled canvas == permanent home camera,
    // which is pixel for pixel the classic Serpantinum desktop.
    readonly property real viewX: active ? rawX : 0
    readonly property real viewY: active ? rawY : 0
    readonly property real viewZoom: active ? rawZoom : 1

    readonly property bool atHome: Math.abs(viewX) < 0.01 && Math.abs(viewY) < 0.01 && Math.abs(viewZoom - 1) < 0.0005
    readonly property real viewWorldW: screenW / viewZoom
    readonly property real viewWorldH: screenH / viewZoom

    property bool dragging: false
    readonly property bool moving: dragging || ticker.running
    // True shortly after any camera change; the minimap uses it to show itself.
    property bool recentlyMoved: false

    property bool loaded: false
    // canvas.json was written by a newer build: use it, never overwrite it.
    property bool readOnly: false

    // Inertia (screen px/s) and animated flight state.
    property real velX: 0
    property real velY: 0
    property bool coasting: false
    property bool flying: false
    property var flyTarget: null
    property real flyVx: 0
    property real flyVy: 0
    property real flyVz: 0
    property real lastDragMs: 0

    property real knownW: 0
    property real knownH: 0

    function current() {
        return { x: cam.rawX, y: cam.rawY, zoom: cam.rawZoom };
    }

    function view() {
        return { x: cam.viewX, y: cam.viewY, zoom: cam.viewZoom };
    }

    function apply(c) {
        let n = CM.normalizeCamera(c);
        if (n.x === cam.rawX && n.y === cam.rawY && n.zoom === cam.rawZoom) return;
        cam.rawX = n.x;
        cam.rawY = n.y;
        cam.rawZoom = n.zoom;
        cam.recentlyMoved = true;
        recentTimer.restart();
        if (cam.loaded) saveTimer.restart();
    }

    function stop() {
        cam.coasting = false;
        cam.flying = false;
        cam.velX = 0;
        cam.velY = 0;
        cam.flyVx = 0;
        cam.flyVy = 0;
        cam.flyVz = 0;
    }

    // Immediate move by screen pixels (keyboard, IPC, touchpad scroll).
    function panBy(dx, dy) {
        if (!cam.active) return;
        cam.stop();
        cam.apply(CM.panBy(cam.current(), dx, dy, 1));
    }

    function dragStart() {
        if (!cam.active) return;
        cam.stop();
        cam.dragging = true;
        cam.lastDragMs = Date.now();
    }

    // Pointer moved by (dx, dy) screen pixels while dragging the canvas.
    function dragMove(dx, dy) {
        if (!cam.active || !cam.dragging) return;
        let s = cam.cfg.sensitivity;
        let now = Date.now();
        let dt = Math.max(1, now - cam.lastDragMs) / 1000;
        cam.lastDragMs = now;
        cam.velX = cam.velX * 0.55 + (dx * s / dt) * 0.45;
        cam.velY = cam.velY * 0.55 + (dy * s / dt) * 0.45;
        cam.apply(CM.panBy(cam.current(), dx, dy, s));
    }

    function dragEnd() {
        if (!cam.dragging) return;
        cam.dragging = false;
        let idle = Date.now() - cam.lastDragMs;
        let speed = Math.sqrt(cam.velX * cam.velX + cam.velY * cam.velY);
        // Released while still moving: keep gliding. Held still before the
        // release: the user parked the canvas on purpose, stop dead.
        if (cam.active && cam.cfg.inertia && idle < 90 && speed > 80) {
            let cap = 6000;
            if (speed > cap) {
                cam.velX *= cap / speed;
                cam.velY *= cap / speed;
            }
            cam.coasting = true;
        } else {
            cam.velX = 0;
            cam.velY = 0;
        }
    }

    function zoomAtPoint(sx, sy, factor) {
        if (!cam.active) return;
        cam.stop();
        cam.apply(CM.zoomAt(cam.current(), sx, sy, factor));
    }

    function zoomBy(factor) {
        cam.zoomAtPoint(cam.screenW / 2, cam.screenH / 2, factor);
    }

    // Shared wheel policy for the desktop and the redactor. Returns true when
    // the event was used. Ctrl always zooms, Shift turns a vertical wheel into
    // horizontal panning.
    function handleWheel(sx, sy, angleX, angleY, pixelX, pixelY, ctrl, shift) {
        if (!cam.active) return false;
        let action = ctrl ? "zoom" : cam.cfg.wheelAction;
        if (action === "none") return false;
        if (action === "zoom") {
            let steps = angleY !== 0 ? angleY / 120 : pixelY / 60;
            if (steps === 0) return false;
            cam.zoomAtPoint(sx, sy, Math.pow(cam.cfg.zoomStep, steps));
            return true;
        }
        let dx = pixelX !== 0 ? pixelX : angleX / 120 * 90;
        let dy = pixelY !== 0 ? pixelY : angleY / 120 * 90;
        if (shift && dx === 0) {
            dx = dy;
            dy = 0;
        }
        if (dx === 0 && dy === 0) return false;
        cam.panBy(dx * cam.cfg.sensitivity, dy * cam.cfg.sensitivity);
        return true;
    }

    // Animated move to a camera.
    function flyTo(c) {
        if (!cam.active) return;
        cam.coasting = false;
        cam.velX = 0;
        cam.velY = 0;
        cam.flyTarget = CM.normalizeCamera(c);
        cam.flying = true;
    }

    function jumpTo(c) {
        if (!cam.active) return;
        cam.stop();
        cam.apply(c);
    }

    function home() {
        cam.flyTo(CM.homeCamera());
    }

    function resetZoom() {
        let c = CM.setZoomAt(cam.current(), cam.screenW / 2, cam.screenH / 2, 1);
        cam.flyTo(c);
    }

    function centerOnWorld(wx, wy) {
        cam.flyTo(CM.centerOn(wx, wy, cam.screenW, cam.screenH, cam.rawZoom));
    }

    // Bring a world box into view: centred, zoomed out only if it does not fit.
    function focusBox(box) {
        if (!box) return;
        let pad = 96;
        let z = cam.rawZoom;
        if (box.w * z > cam.screenW - pad * 2 || box.h * z > cam.screenH - pad * 2) {
            cam.flyTo(CM.fitRect(box, cam.screenW, cam.screenH, pad));
        } else {
            cam.flyTo(CM.centerOn(box.x + box.w / 2, box.y + box.h / 2, cam.screenW, cam.screenH, z));
        }
    }

    function fitBounds(bounds) {
        if (!bounds) {
            cam.home();
            return;
        }
        cam.flyTo(CM.fitRect(bounds, cam.screenW, cam.screenH, 96));
    }

    function screenToWorld(sx, sy) {
        return CM.screenToWorld(cam.view(), sx, sy);
    }

    function worldToScreen(wx, wy) {
        return CM.worldToScreen(cam.view(), wx, wy);
    }

    FrameAnimation {
        id: ticker
        running: cam.active && (cam.coasting || cam.flying)
        onTriggered: {
            let dt = frameTime > 0 ? frameTime : 0.016;
            if (cam.flying && cam.flyTarget) {
                let st = CM.flyStep({ x: cam.rawX, y: cam.rawY, zoom: cam.rawZoom, vx: cam.flyVx, vy: cam.flyVy, vz: cam.flyVz }, cam.flyTarget, 0.16, dt);
                cam.flyVx = st.vx;
                cam.flyVy = st.vy;
                cam.flyVz = st.vz;
                cam.apply(st);
                if (st.done) cam.flying = false;
            } else if (cam.coasting) {
                let st = CM.inertiaStep(cam.velX, cam.velY, dt, cam.cfg.friction);
                cam.velX = st.vx;
                cam.velY = st.vy;
                cam.apply(CM.panBy(cam.current(), st.dx, st.dy, 1));
                if (st.done) cam.coasting = false;
            } else {
                cam.flying = false;
            }
        }
    }

    Timer {
        id: recentTimer
        interval: 1800
        onTriggered: cam.recentlyMoved = false
    }

    // ---- resolution changes -------------------------------------------------

    function syncViewport() {
        if (!cam.loaded || !(cam.screenW > 0) || !(cam.screenH > 0)) return;
        if (cam.knownW > 0 && cam.knownH > 0 && (cam.knownW !== cam.screenW || cam.knownH !== cam.screenH)) {
            cam.stop();
            cam.apply(CM.onViewportResize(cam.current(), cam.knownW, cam.knownH, cam.screenW, cam.screenH));
        }
        if (cam.knownW !== cam.screenW || cam.knownH !== cam.screenH) {
            cam.knownW = cam.screenW;
            cam.knownH = cam.screenH;
            saveTimer.restart();
        }
    }

    onScreenWChanged: Qt.callLater(cam.syncViewport)
    onScreenHChanged: Qt.callLater(cam.syncViewport)

    // ---- persistence --------------------------------------------------------

    function applyStateText(text) {
        let st = CM.parseState(text);
        if (st === null) {
            cam.readOnly = true;
            try {
                let raw = JSON.parse(text);
                st = { camera: CM.normalizeCamera(raw.camera), screen: { w: 0, h: 0 } };
            } catch (e) {
                st = CM.normalizeState(null);
            }
        }
        cam.rawX = st.camera.x;
        cam.rawY = st.camera.y;
        cam.rawZoom = st.camera.zoom;
        cam.knownW = st.screen.w;
        cam.knownH = st.screen.h;
        cam.loaded = true;
        cam.syncViewport();
    }

    function saveNow() {
        saveTimer.stop();
        if (!cam.loaded || cam.readOnly || cam.safeName === "") return;
        stateFile.setText(CM.serializeState(cam.current(), cam.screenW, cam.screenH));
    }

    FileView {
        id: stateFile
        printErrors: false
        path: cam.safeName !== "" ? (Caching.getStateDir("widgets/" + cam.safeName) + "/canvas.json") : ""
        onLoaded: {
            if (!cam.loaded) cam.applyStateText(text());
        }
        onLoadFailed: {
            if (!cam.loaded) {
                cam.loaded = true;
                cam.syncViewport();
            }
        }
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: cam.saveNow()
    }

    Component.onDestruction: {
        if (saveTimer.running) cam.saveNow();
    }
}
