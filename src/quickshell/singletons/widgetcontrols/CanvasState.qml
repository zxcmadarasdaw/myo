pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "../../widgets"
import "../../widgets/canvas"
import "../../widgets/canvas/CanvasMath.js" as CM

// Infinite desktop canvas: shared state.
//  - one CanvasCamera per monitor
//  - settings (settings.json -> "canvas", with per-monitor overrides)
//  - the list of widgets each monitor currently shows (for minimap and search)
//  - saved compositions
Item {
    id: root
    visible: false

    // ---- settings -----------------------------------------------------------

    readonly property var settings: CM.normalizeSettings(Config.getSetting("canvas", {}))
    readonly property var defaults: CM.DEFAULTS
    readonly property var limits: CM.LIMITS

    function effective(monitor) {
        return CM.resolveSettings(root.settings, monitor);
    }

    function rawSettings() {
        let s = Config.getSetting("canvas", {});
        return (s && typeof s === "object" && !Array.isArray(s)) ? s : {};
    }

    function setGlobal(key, value) {
        if (!Object.prototype.hasOwnProperty.call(CM.DEFAULTS, key)) return;
        let s = root.rawSettings();
        s[key] = value;
        Config.setSetting("canvas", s);
    }

    function hasOverride(monitor) {
        return !!root.settings.monitors[CM.safeName(monitor)];
    }

    // Turning the override on copies the current effective values, so nothing
    // changes on screen until the user edits something.
    function setOverride(monitor, on) {
        let name = CM.safeName(monitor);
        if (name === "") return;
        let s = root.rawSettings();
        if (!s.monitors || typeof s.monitors !== "object" || Array.isArray(s.monitors)) s.monitors = {};
        if (on) {
            let eff = root.effective(monitor);
            let o = {};
            for (let k in CM.DEFAULTS) o[k] = eff[k];
            s.monitors[name] = o;
        } else {
            delete s.monitors[name];
        }
        Config.setSetting("canvas", s);
    }

    function setMonitor(monitor, key, value) {
        if (!Object.prototype.hasOwnProperty.call(CM.DEFAULTS, key)) return;
        let name = CM.safeName(monitor);
        if (name === "") return;
        let s = root.rawSettings();
        if (!s.monitors || typeof s.monitors !== "object" || Array.isArray(s.monitors)) s.monitors = {};
        let o = (s.monitors[name] && typeof s.monitors[name] === "object") ? s.monitors[name] : {};
        o[key] = value;
        s.monitors[name] = o;
        Config.setSetting("canvas", s);
    }

    // Writes to the monitor override when it exists, to the global value otherwise.
    function setValue(monitor, key, value) {
        if (monitor && root.hasOverride(monitor)) root.setMonitor(monitor, key, value);
        else root.setGlobal(key, value);
    }

    function resetSettings() {
        Config.setSetting("canvas", {});
    }

    // ---- cameras ------------------------------------------------------------

    property var cameras: ({})
    property int revision: 0

    // Reactive: bindings that call this re-evaluate when monitors come and go.
    function cameraFor(monitor) {
        let rev = root.revision;
        let c = root.cameras[CM.safeName(monitor)];
        return c ? c : null;
    }

    function monitorNames() {
        let rev = root.revision;
        return Object.keys(root.cameras);
    }

    function registerCamera(camera) {
        let map = root.cameras;
        map[camera.safeName] = camera;
        root.cameras = map;
        root.revision++;
    }

    function unregisterCamera(camera) {
        let map = root.cameras;
        if (map[camera.safeName] === camera) delete map[camera.safeName];
        root.cameras = map;
        root.revision++;
    }

    // Same per-screen instancing Shell.qml uses for WidgetLoader.
    Variants {
        model: Quickshell.screens
        delegate: CanvasCamera {
            id: screenCamera
            required property var modelData
            monitorName: modelData ? modelData.name : ""
            screenW: modelData ? modelData.width : 0
            screenH: modelData ? modelData.height : 0
            cfg: CM.resolveSettings(root.settings, monitorName)
            Component.onCompleted: root.registerCamera(screenCamera)
            Component.onDestruction: root.unregisterCamera(screenCamera)
        }
    }

    // ---- widgets on each monitor (published by WidgetLoader) ----------------

    property var widgetLists: ({})
    property int widgetsRevision: 0

    function publishWidgets(monitor, list) {
        let map = root.widgetLists;
        map[CM.safeName(monitor)] = list || [];
        root.widgetLists = map;
        root.widgetsRevision++;
    }

    function widgetsFor(monitor) {
        let rev = root.widgetsRevision;
        return root.widgetLists[CM.safeName(monitor)] || [];
    }

    function typeNames() {
        let out = {};
        let types = WidgetRegistry.types;
        for (let k in types) out[k] = types[k].name || k;
        return out;
    }

    function search(monitor, query) {
        return CM.searchWidgets(root.widgetsFor(monitor), query, root.typeNames());
    }

    function findWidget(monitor, widgetId) {
        let list = root.widgetsFor(monitor);
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].wId) === String(widgetId)) return list[i];
        }
        return null;
    }

    // Fly the camera of `monitor` to a widget. Returns false when it is unknown.
    function goToWidget(monitor, widgetId) {
        let cam = root.cameraFor(monitor);
        let w = root.findWidget(monitor, widgetId);
        if (!cam || !w) return false;
        cam.focusBox(CM.widgetBox(w));
        return true;
    }

    function fitAll(monitor) {
        let cam = root.cameraFor(monitor);
        if (!cam) return;
        cam.fitBounds(CM.boundsOf(root.widgetsFor(monitor)));
    }

    // ---- overlays -----------------------------------------------------------

    // Minimap forced on by the user (IPC / keybind), regardless of the setting.
    property bool minimapPinned: false
    signal navigatorRequested(string monitor)

    function requestNavigator(monitor) {
        root.navigatorRequested(CM.safeName(monitor));
    }

    // ---- compositions -------------------------------------------------------

    property var compositions: []
    property bool compositionsLoaded: false
    // File written by a newer build: listed, never overwritten.
    property bool compositionsReadOnly: false

    function compositionById(id) {
        for (let i = 0; i < root.compositions.length; i++) {
            if (root.compositions[i].id === id) return root.compositions[i];
        }
        return null;
    }

    function writeCompositions(items) {
        if (root.compositionsReadOnly) return false;
        root.compositions = items;
        compositionsFile.setText(CM.serializeCompositions(items));
        return true;
    }

    // widgets: records with wId, wType, wX ... (world coordinates). Returns the
    // new composition id, or "" when nothing could be saved.
    function saveComposition(name, widgets) {
        if (root.compositionsReadOnly || !widgets || widgets.length === 0) return "";
        if (root.compositions.length >= CM.MAX_COMPOSITIONS) return "";
        let taken = {};
        for (let i = 0; i < root.compositions.length; i++) taken[root.compositions[i].id] = true;
        let comp = CM.makeComposition(name, widgets, taken);
        if (!comp) return "";
        let items = root.compositions.slice();
        items.push(comp);
        return root.writeCompositions(items) ? comp.id : "";
    }

    function removeComposition(id) {
        let items = root.compositions.filter(c => c.id !== id);
        if (items.length === root.compositions.length) return false;
        return root.writeCompositions(items);
    }

    function renameComposition(id, name) {
        let clean = CM.sanitizeName(name);
        if (clean === "") return false;
        let found = false;
        let items = root.compositions.map(c => {
            if (c.id !== id) return c;
            found = true;
            return Object.assign({}, c, { name: clean });
        });
        return found ? root.writeCompositions(items) : false;
    }

    // Records ready to be added, centred in the current view of `monitor`.
    function instantiate(monitor, id) {
        let comp = root.compositionById(id);
        let cam = root.cameraFor(monitor);
        if (!comp) return [];
        let cx = cam ? cam.viewX + cam.viewWorldW / 2 : 960;
        let cy = cam ? cam.viewY + cam.viewWorldH / 2 : 540;
        let eff = root.effective(monitor);
        return CM.instantiateComposition(comp, cx, cy, eff.snapToGrid ? eff.gridSize : 0);
    }

    // Adds a composition straight to the desktop (used when the redactor is closed).
    function insertComposition(monitor, id) {
        let name = CM.safeName(monitor);
        let list = root.instantiate(monitor, id);
        let keys = WidgetRegistry.standardKeys;
        let added = 0;
        for (let i = 0; i < list.length; i++) {
            let w = list[i];
            if (!WidgetRegistry.types[w.wType]) continue;
            WidgetSync.addWidget(name, w.wId, w.wType, w.wX, w.wY, w.wWidth, w.wHeight, w.wOpacity, w.wImagePath, w.wRotation, w.wVariant);
            for (let k in w) {
                if (keys.includes(k)) continue;
                if (k === "wGroup" && w[k] === "") continue;
                WidgetSync.setProperty(name, w.wId, k, w[k]);
            }
            added++;
        }
        return added;
    }

    FileView {
        id: compositionsFile
        printErrors: false
        path: Caching.getStateDir("widgets") + "/compositions.json"
        onLoaded: {
            let text = compositionsFile.text();
            let parsed = CM.parseCompositions(text);
            if (parsed === null) {
                root.compositionsReadOnly = true;
                try {
                    let raw = JSON.parse(text);
                    raw.schema_version = CM.SCHEMA_VERSION;
                    parsed = CM.normalizeCompositions(raw);
                } catch (e) {
                    parsed = CM.normalizeCompositions(null);
                }
            }
            root.compositions = parsed.items;
            root.compositionsLoaded = true;
        }
        onLoadFailed: root.compositionsLoaded = true
    }
}
