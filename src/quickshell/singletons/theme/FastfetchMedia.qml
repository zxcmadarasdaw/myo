pragma Singleton
import QtQuick
import "../../"

Item {
    id: root
    readonly property var presets: ({
        obsidian: {name: "Obsidian", layout: "classic", width: 43, height: 88, radius: 14, gap: 12, bg: "#0e1118", fg: "#e6edf6", accent: "#8badde", alpha: 0.96, border: 0.28, font: "IBM Plex Mono", material: "solid"},
        glass_noir: {name: "Glass Noir", layout: "floating", width: 48, height: 88, radius: 18, gap: 14, bg: "#11131e", fg: "#e9e5f9", accent: "#b9a3ea", alpha: 0.62, border: 0.42, font: "Cutive Mono", material: "glass"},
        minimal: {name: "Minimal", layout: "minimal", width: 36, height: 76, radius: 4, gap: 8, bg: "#171919", fg: "#e7ece8", accent: "#a2b8aa", alpha: 0.87, border: 0, font: "monospace", material: "solid"},
        liquid_shadow: {name: "Liquid Shadow", layout: "vertical", width: 90, height: 45, radius: 20, gap: 14, bg: "#191226", fg: "#f0e5fa", accent: "#d6a6e5", alpha: 0.74, border: 0.36, font: "Martian Mono", material: "liquid"},
        terminal_classic: {name: "Terminal Classic", layout: "classic", width: 36, height: 96, radius: 0, gap: 6, bg: "#09120b", fg: "#b4efb4", accent: "#67b77b", alpha: 1, border: 0.55, font: "Courier Prime", material: "solid"},
        floating_media: {name: "Floating Media", layout: "wide", width: 58, height: 93, radius: 16, gap: 10, bg: "#102020", fg: "#dcf0e9", accent: "#8dd4bc", alpha: 0.76, border: 0.32, font: "Space Mono", material: "glass"},
        // Matte, never glass: the presets of the Mochi Night and ERROR//OVERDRIVE themes.
        mochi: {name: "Mochi", layout: "classic", width: 40, height: 86, radius: 14, gap: 12, bg: "#141219", fg: "#ece6f0", accent: "#e7a4c6", alpha: 0.94, border: 0.3, font: "JetBrains Mono", material: "solid"},
        overdrive: {name: "Overdrive", layout: "classic", width: 42, height: 94, radius: 2, gap: 10, bg: "#0b0c12", fg: "#dfe6f2", accent: "#ff5fa2", alpha: 0.95, border: 0.55, font: "JetBrains Mono", material: "solid"}
    })
    readonly property var layouts: ["classic", "wide", "vertical", "floating", "minimal"]
    readonly property var layoutSize: ({
        classic: [43, 88], wide: [58, 94], vertical: [90, 44], floating: [48, 88], minimal: [36, 76]
    })
    readonly property var positions: ["start", "center", "end"]
    readonly property var raw: Config.getSetting("fastfetchMedia", {}) || ({})
    readonly property var appearance: raw.appearance || ({})
    readonly property string theme: Object.keys(presets).includes(appearance.theme) ? appearance.theme : "obsidian"
    readonly property var style: presets[theme]
    readonly property string layout: layouts.includes(appearance.layout) ? appearance.layout : style.layout
    readonly property string position: positions.includes(appearance.position) ? appearance.position : "center"
    readonly property int mediaWidth: bound(appearance.width, layout === style.layout ? style.width : layoutSize[layout][0], 15, 100)
    readonly property int mediaHeight: bound(appearance.height, layout === style.layout ? style.height : layoutSize[layout][1], 15, 100)
    readonly property int radius: bound(appearance.radius, style.radius, 0, 40)
    readonly property real zoom: bound(appearance.zoom, 1, 0.5, 2)
    readonly property real opacityValue: bound(appearance.opacity, 1, 0, 1)
    readonly property bool enabled: raw.enabled === true
    readonly property string path: typeof raw.path === "string" ? raw.path : ""
    readonly property string kind: {
        if (!/^\/(?!\/)/.test(path) || /[\x00-\x1f]/.test(path)) return "";
        if (/\.(gif|webp)$/i.test(path)) return "animated";
        if (/\.(png|jpe?g|bmp)$/i.test(path)) return "image";
        if (/\.(mp4|webm|mkv|mov|m4v|avi|mpg|mpeg|ogv)$/i.test(path)) return "video";
        return "";
    }
    readonly property var filters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp", "*.gif",
                                    "*.mp4", "*.webm", "*.mkv", "*.mov", "*.m4v", "*.avi", "*.mpg", "*.mpeg", "*.ogv"]
    readonly property real speed: bound(raw.speed, 1, 0.25, 2)
    readonly property int animationFps: bound(raw.animationFps, 0, 0, 60)
    readonly property bool loop: raw.loop !== false
    readonly property bool autoplay: raw.autoplay !== false
    readonly property bool pauseWhenHidden: raw.pauseWhenHidden !== false
    readonly property bool playAudio: raw.playAudio === true
    readonly property bool mixWallpaperAudio: raw.mixWallpaperAudio === true
    readonly property bool allowMotion: !GpuCompatibility.effective.fallback
                                       && !Config.getSetting("general.performance", false) && !Wallpaper.captureLite
    readonly property bool wallpaperAudible: Wallpaper.audioEngine?.audioPlaying === true
    property var audioOwner: null

    function bound(value, fallback, minimum, maximum) {
        return typeof value === "number" && isFinite(value) ? Math.max(minimum, Math.min(maximum, value)) : fallback;
    }

    function set(key, value) {
        Config.setSetting("fastfetchMedia." + key, value);
    }

    function setStyle(key, value) {
        set("appearance." + key, value);
    }
}
