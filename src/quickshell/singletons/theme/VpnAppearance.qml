pragma Singleton
import QtQuick
import Quickshell
import "../../"

// Appearance of the VPN panel (Super+N -> VPN). Data only: colours, material, lines,
// layout. Stored in settings.json under "vpnAppearance"; never contains a subscription
// link, token or server (those live in ~/.config/serpantinum/vpn/, mode 600), so a
// Themess package or an exported settings file cannot carry them.
//
//   { "theme": "obsidian_glass" | "custom" | "user:<id>",
//     "custom": { ...style },                   // the last edited style
//     "presets": [ { "id", "name", "style" } ] } // "Save as custom theme"
//
// Editing works on a draft: the settings tab calls preview(...) for every change (the open
// panel shows it live), then apply() stores it, cancel() drops it, reset() goes back to the
// theme's own values.
QtObject {
    id: root

    readonly property var materials: ["matte", "glass", "liquid", "obsidian", "minimal", "neon"]
    readonly property var layouts: ["auto", "centered", "vertical", "horizontal", "compact", "expanded"]
    readonly property var lineStyles: ["straight", "curved", "circuit", "flow", "minimal"]
    readonly property var buttonShapes: ["circle", "squircle", "pill"]
    readonly property var typographies: ["light", "regular", "bold"]
    readonly property var colorKeys: ["background", "button", "line", "active", "inactive", "text", "glowColor", "border"]

    readonly property var defaults: ({
        material: "glass", layout: "auto", lineStyle: "curved", buttonShape: "circle", typography: "regular",
        background: "#0b0d12", button: "#e8ecf4", line: "#d9e0ee", active: "#7fd4ff", inactive: "#5c6370",
        text: "#eef1f6", glowColor: "#7fd4ff", border: "#ffffff",
        opacity: 0.78, blur: 0.9, borderOpacity: 0.12, lineWidth: 1.4, glow: 0.35, animSpeed: 1.0,
        animate: true, radius: 22
    })

    // Six built-in themes. Each changes the material, the button, the lines, the type and
    // the layout, not only the colours.
    readonly property var themes: [
        { id: "obsidian_glass", name: "Obsidian Glass", style: {
            material: "glass", layout: "centered", lineStyle: "straight", buttonShape: "circle", typography: "light",
            background: "#0b0d12", button: "#e8ecf4", line: "#d9e0ee", active: "#9fdcff", inactive: "#4f5562",
            text: "#eef1f6", glowColor: "#9fdcff", border: "#ffffff",
            opacity: 0.72, blur: 0.95, borderOpacity: 0.14, lineWidth: 1.1, glow: 0.25, animSpeed: 1.0,
            animate: true, radius: 24 } },
        { id: "liquid_noir", name: "Liquid Noir", style: {
            material: "liquid", layout: "centered", lineStyle: "curved", buttonShape: "squircle", typography: "regular",
            background: "#050507", button: "#f2f2f4", line: "#a9a9b6", active: "#c9b6ff", inactive: "#45454f",
            text: "#f5f5f7", glowColor: "#b39dff", border: "#ffffff",
            opacity: 0.52, blur: 1.0, borderOpacity: 0.22, lineWidth: 2.2, glow: 0.45, animSpeed: 0.75,
            animate: true, radius: 30 } },
        { id: "midnight_blue", name: "Midnight Blue", style: {
            material: "glass", layout: "expanded", lineStyle: "flow", buttonShape: "circle", typography: "regular",
            background: "#06122b", button: "#2f6bff", line: "#3a5ea8", active: "#4cc3ff", inactive: "#26375a",
            text: "#dbe7ff", glowColor: "#4cc3ff", border: "#8fb4ff",
            opacity: 0.88, blur: 0.6, borderOpacity: 0.18, lineWidth: 1.8, glow: 0.6, animSpeed: 1.1,
            animate: true, radius: 20 } },
        { id: "graphite", name: "Graphite", style: {
            material: "matte", layout: "horizontal", lineStyle: "circuit", buttonShape: "squircle", typography: "bold",
            background: "#1b1c1f", button: "#c9ccd1", line: "#6b6f76", active: "#e0e3e8", inactive: "#4a4d53",
            text: "#e6e7ea", glowColor: "#c9ccd1", border: "#9a9ea6",
            opacity: 0.97, blur: 0.0, borderOpacity: 0.16, lineWidth: 1.5, glow: 0.0, animSpeed: 0.6,
            animate: true, radius: 10 } },
        { id: "soft_neon", name: "Soft Neon", style: {
            material: "neon", layout: "centered", lineStyle: "flow", buttonShape: "pill", typography: "bold",
            background: "#07060d", button: "#ff4fd8", line: "#7a4fd6", active: "#39f3ff", inactive: "#3b2f5a",
            text: "#f4eaff", glowColor: "#ff4fd8", border: "#ff4fd8",
            opacity: 0.92, blur: 0.3, borderOpacity: 0.55, lineWidth: 2.0, glow: 0.85, animSpeed: 1.3,
            animate: true, radius: 18 } },
        { id: "pure_minimal", name: "Pure Minimal", style: {
            material: "minimal", layout: "vertical", lineStyle: "minimal", buttonShape: "circle", typography: "light",
            background: "#000000", button: "#ffffff", line: "#8a8a8a", active: "#ffffff", inactive: "#5a5a5a",
            text: "#ffffff", glowColor: "#ffffff", border: "#ffffff",
            opacity: 0.18, blur: 0.35, borderOpacity: 0.0, lineWidth: 1.0, glow: 0.0, animSpeed: 1.0,
            animate: false, radius: 16 } }
    ]
    readonly property string defaultTheme: "obsidian_glass"

    // ---- stored state ------------------------------------------------------------------
    readonly property var stored: {
        let v = Config.getSetting("vpnAppearance", null);
        return (v && typeof v === "object" && !Array.isArray(v)) ? v : {};
    }
    readonly property string themeId: typeof stored.theme === "string" && stored.theme !== "" ? stored.theme : defaultTheme
    readonly property var presets: Array.isArray(stored.presets)
        ? stored.presets.filter(p => p && typeof p.id === "string" && typeof p.name === "string" && p.style) : []
    readonly property var applied: resolve(themeId, stored, presets)

    // ---- draft (settings tab) ------------------------------------------------------------
    property var draft: null
    property string draftTheme: ""
    readonly property bool previewing: draft !== null
    readonly property var style: draft !== null ? draft : applied
    readonly property string currentTheme: draft !== null ? draftTheme : themeId

    function themeById(id) {
        for (let i = 0; i < themes.length; i++) if (themes[i].id === id) return themes[i];
        return null;
    }

    function presetById(id, list) {
        let l = list || presets;
        for (let i = 0; i < l.length; i++) if (l[i].id === id) return l[i];
        return null;
    }

    function resolve(id, st, list) {
        let s = st || stored;
        if (id === "custom") return sanitize(s.custom);
        if (id.indexOf("user:") === 0) {
            let p = presetById(id.slice(5), list);
            if (p) return sanitize(p.style);
        }
        let t = themeById(id) || themeById(defaultTheme);
        return sanitize(t.style);
    }

    function themeName(id) {
        let t = themeById(id);
        if (t) return t.name;
        if (id.indexOf("user:") === 0) {
            let p = presetById(id.slice(5));
            if (p) return p.name;
        }
        return "Custom";
    }

    function isColor(v) { return typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v); }
    function clampNum(v, lo, hi, d) {
        let n = Number(v);
        return (v !== null && v !== "" && isFinite(n)) ? Math.max(lo, Math.min(hi, n)) : d;
    }

    // Everything from settings.json, Themess or the editor goes through here.
    function sanitize(s) {
        let src = (s && typeof s === "object") ? s : {};
        let out = {};
        let d = defaults;
        out.material = materials.indexOf(src.material) >= 0 ? src.material : d.material;
        out.layout = layouts.indexOf(src.layout) >= 0 ? src.layout : d.layout;
        out.lineStyle = lineStyles.indexOf(src.lineStyle) >= 0 ? src.lineStyle : d.lineStyle;
        out.buttonShape = buttonShapes.indexOf(src.buttonShape) >= 0 ? src.buttonShape : d.buttonShape;
        out.typography = typographies.indexOf(src.typography) >= 0 ? src.typography : d.typography;
        for (let i = 0; i < colorKeys.length; i++) {
            let k = colorKeys[i];
            out[k] = isColor(src[k]) ? src[k].toLowerCase() : d[k];
        }
        out.opacity = clampNum(src.opacity, 0, 1, d.opacity);
        out.blur = clampNum(src.blur, 0, 1, d.blur);
        out.borderOpacity = clampNum(src.borderOpacity, 0, 1, d.borderOpacity);
        out.lineWidth = clampNum(src.lineWidth, 0.5, 6, d.lineWidth);
        out.glow = clampNum(src.glow, 0, 1, d.glow);
        out.animSpeed = clampNum(src.animSpeed, 0.25, 3, d.animSpeed);
        out.animate = typeof src.animate === "boolean" ? src.animate : d.animate;
        out.radius = Math.round(clampNum(src.radius, 0, 40, d.radius));
        return out;
    }

    function copy(o) { return JSON.parse(JSON.stringify(o)); }

    function save(patch) {
        let next = copy(stored);
        for (let k in patch) next[k] = patch[k];
        Config.setSetting("vpnAppearance", next);
    }

    // ---- editor API ------------------------------------------------------------------------
    function beginEdit() {
        if (draft === null) {
            draft = copy(applied);
            draftTheme = themeId;
        }
    }

    // Preview one key (becomes a custom style) or a whole style; nothing is stored yet.
    function preview(key, value) {
        beginEdit();
        let next = copy(draft);
        next[key] = value;
        draft = sanitize(next);
        draftTheme = "custom";
    }

    function previewTheme(id) {
        draft = resolve(id);
        draftTheme = id;
    }

    function apply() {
        if (draft === null) return;
        let id = draftTheme || themeId;
        let known = themeById(id) !== null || (id.indexOf("user:") === 0 && presetById(id.slice(5)) !== null);
        if (id === "custom" || !known)
            save({ theme: "custom", custom: copy(draft) });
        else
            save({ theme: id });
        draft = null;
        draftTheme = "";
    }

    function cancel() {
        draft = null;
        draftTheme = "";
    }

    // Back to the selected built-in theme's own values (the default theme for a custom style).
    function reset() {
        let id = draftTheme || themeId;
        previewTheme(themeById(id) ? id : defaultTheme);
    }

    function saveAsPreset(name) {
        let clean = String(name || "").replace(/\s+/g, " ").trim().slice(0, 40);
        if (clean === "") return "";
        let id = Date.now().toString(36);
        let list = presets.concat([{ id: id, name: clean, style: copy(style) }]).slice(-24);
        save({ presets: list, theme: "user:" + id });
        draft = null;
        draftTheme = "";
        return id;
    }

    function deletePreset(id) {
        let list = presets.filter(p => p.id !== id);
        let patch = { presets: list };
        if (themeId === "user:" + id) patch.theme = defaultTheme;
        save(patch);
        if (draftTheme === "user:" + id) cancel();
    }

    // ---- derived values for the panel ---------------------------------------------------
    readonly property int fontWeight: style.typography === "light" ? Font.Light
        : style.typography === "bold" ? Font.Bold : Font.Normal
    readonly property real letterSpacing: style.typography === "light" ? 2.6 : (style.typography === "bold" ? 1.2 : 1.8)
}
