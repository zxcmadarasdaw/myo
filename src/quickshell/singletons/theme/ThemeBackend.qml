pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    readonly property string defaultFontFamily: "Adwaita Mono"
    readonly property int defaultBorderRadius: 8
    property string fontFamily: defaultFontFamily
    property int borderRadius: defaultBorderRadius
    property int clampedBorderRadius: {
        const r = borderRadius;
        return Math.floor(
            r <= 24
                ? r
                : 24 + Math.pow(r - 24, 0.55)
        );
    }

    property real configuredElementOpacity: 1.0
    property bool configuredBlurBackground: false
    readonly property real elementOpacity: GpuCompatibility.effective.fallback ? 1.0 : (liquidGlass ? liquidGlassOpacity : configuredElementOpacity)
    readonly property bool blurBackground: configuredBlurBackground && GpuCompatibility.blurAllowed
    property string blurStyle: "blur"
    readonly property real liquidGlassOpacity: 0.1
    readonly property bool glassActive: blurBackground && elementOpacity < 0.999
    readonly property bool liquidGlass: blurBackground && blurStyle === "liquid"

    readonly property var defaultColors: ({
        base: "#1e1e2e", mantle: "#181825", crust: "#11111b",
        text: "#cdd6f4", subtext0: "#a6adc8", subtext1: "#bac2de",
        surface0: "#313244", surface1: "#45475a", surface2: "#585b70",
        overlay0: "#6c7086", overlay1: "#7f849c", overlay2: "#9399b2",
        blue: "#89b4fa", sapphire: "#74c7ec", peach: "#fab387", green: "#a6e3a1", red: "#f38ba8",
        mauve: "#cba6f7", pink: "#f5c2e7", yellow: "#f9e2af", maroon: "#eba0ac", teal: "#94e2d5"
    })
    property color base: defaultColors.base
    property color mantle: defaultColors.mantle
    property color crust: defaultColors.crust
    property color _text: defaultColors.text
    property color _subtext0: defaultColors.subtext0
    property color _subtext1: defaultColors.subtext1
    readonly property color text: liquidGlass ? "#ffffff" : _text
    readonly property color subtext0: liquidGlass ? "#ffffff" : _subtext0
    readonly property color subtext1: liquidGlass ? "#ffffff" : _subtext1
    property color surface0: defaultColors.surface0
    property color surface1: defaultColors.surface1
    property color surface2: defaultColors.surface2
    property color overlay0: defaultColors.overlay0
    property color overlay1: defaultColors.overlay1
    property color overlay2: defaultColors.overlay2
    property color blue: defaultColors.blue
    readonly property color primary: blue
    property color sapphire: defaultColors.sapphire
    property color peach: defaultColors.peach
    property color green: defaultColors.green
    property color red: defaultColors.red
    property color mauve: defaultColors.mauve
    property color pink: defaultColors.pink
    property color yellow: defaultColors.yellow
    property color maroon: defaultColors.maroon
    property color teal: defaultColors.teal

    property string configPath: Quickshell.env("QS_COLORS_JSON") ?? "~/.local/state/serpantinum/qs_colors.json"
    property string matugenConfigPath: (typeof Caching !== "undefined" && Caching.stateDir ? Caching.stateDir : ((Quickshell.env("HOME") ?? "") + "/.local/state/serpantinum")) + "/qs_matugen_colors.json"

    property bool _readInProgress: false
    property var matugenColors: null
    property var _colorQueue: []
    property int colorsPerFrame: 3

    property var availableFontPaths: ({})
    property var bundledNames: []
    property string activeFontPath: ""

    FontLoader {
        id: iconFontLoader
        source: (typeof Caching !== "undefined" && Caching.serpantinumDir && Caching.serpantinumDir !== "")
            ? ("file://" + Caching.serpantinumDir + "/assets/fonts/SymbolsNerdFontMono-Regular.ttf")
            : ""
    }

    readonly property string iconFont: (iconFontLoader.status === FontLoader.Ready && iconFontLoader.name !== "")
        ? iconFontLoader.name
        : (root.fontFamily !== "" ? root.fontFamily : "sans-serif")
    readonly property bool iconFontReady: iconFontLoader.status === FontLoader.Ready

    onFontFamilyChanged: {
        root.updateActiveFontLoader();
    }

    function isMatugenTheme() {
        if (typeof Matugen !== "undefined" && typeof Matugen.isMatugenTheme === "function") {
            return Matugen.isMatugenTheme();
        }
        let themeConfig = Config.getSetting("theme", { "matugen": true, "activePreset": "Matugen" });
        if (themeConfig.matugen !== undefined) {
            return themeConfig.matugen === true;
        }
        return themeConfig.theme === "matugen"
            || themeConfig.name === "matugen"
            || themeConfig.currentTheme === "matugen"
            || themeConfig.current === "matugen"
            || themeConfig.activePreset === "Matugen"
            || themeConfig.activePreset === undefined;
    }

    function updateActiveFontLoader() {
        if (!root.fontFamily || root.fontFamily === "") return;
        let key = root.fontFamily.toLowerCase();
        let path = root.availableFontPaths ? root.availableFontPaths[key] : "";

        if (path && root.activeFontPath !== path) {
            root.activeFontPath = path;
        }
    }

    FontLoader {
        id: staticFontLoader
        source: (root.activeFontPath && root.activeFontPath !== "") ? ("file://" + root.activeFontPath) : ""
        onStatusChanged: {
            if (status === FontLoader.Ready) {
                let cur = root.fontFamily;
                root.fontFamily = "";
                root.fontFamily = cur;
            }
        }
    }

    Process {
        id: fontFetcher
        property bool forceRescan: false

        command: {
            let sys = Caching.serpantinumDir ? (Caching.serpantinumDir + "/assets/fonts") : "";
            let usr = Caching.stateDir ? (Caching.stateDir + "/fonts") : (Caching.home + "/.local/state/serpantinum/fonts");
            let cacheFile = Caching.stateDir ? (Caching.stateDir + "/fonts_cache.txt") : (Caching.home + "/.local/state/serpantinum/fonts_cache.txt");
            let force = forceRescan ? "true" : "false";

            let cmd = "CACHE=\"" + cacheFile + "\"; ";
            cmd += "if [ \"" + force + "\" = \"true\" ] || [ ! -f \"$CACHE\" ]; then ";
            cmd += "mkdir -p \"$(dirname \"$CACHE\")\"; ";
            cmd += "find ";
            if (sys !== "") cmd += "\"" + sys + "\" ";
            cmd += "\"" + usr + "\" -type f \\( -iname \"*.ttf\" -o -iname \"*.otf\" -o -iname \"*.ttc\" \\) -print0 2>/dev/null | sort -z | ";
            cmd += "xargs -0 -r fc-scan -f '%{family[0]}\\t%{style[0]}\\t%{file}\\n' 2>/dev/null | ";
            cmd += "awk -F'\\t' '{ fam=$1; stl=$2; f=$3; if (fam==\"\") { n=split(f,a,\"/\"); fam=a[n]; sub(/\\.[^.]*$/,\"\",fam) } if (stl!=\"\" && stl!=\"Regular\") print fam \" \" stl \"|\" f; else print fam \"|\" f }' ";
            cmd += "> \"$CACHE.tmp\" || true; mv \"$CACHE.tmp\" \"$CACHE\"; ";
            cmd += "fi; ";
            cmd += "cat \"$CACHE\" || true";

            return ["bash", "-c", cmd];
        }
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                fontFetcher.forceRescan = false;

                let lines = this.text.trim().split('\n');
                let newPaths = {};
                let names = [];
                let seen = new Set();

                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i].trim();
                    if (line === "") continue;

                    let idx = line.indexOf('|');
                    if (idx !== -1) {
                        let fName = line.substring(0, idx).trim();
                        if (fName.toLowerCase().indexOf("symbols nerd font") !== -1) continue;

                        let fPath = line.substring(idx + 1).trim();
                        let key = fName.toLowerCase();

                        newPaths[key] = fPath;

                        if (!seen.has(key)) {
                            seen.add(key);
                            names.push(fName);
                        }
                    }
                }

                root.availableFontPaths = newPaths;
                root.bundledNames = names;
                root.updateActiveFontLoader();
                if (staticFontLoader.status === FontLoader.Ready) {
                    let cur = root.fontFamily;
                    root.fontFamily = "";
                    root.fontFamily = cur;
                }
            }
        }
    }

    function scanFonts() {
        fontFetcher.running = false;
        fontFetcher.forceRescan = true;
        fontFetcher.running = true;
    }

    function reloadColors() {
        if (root._readInProgress) return;
        root._readInProgress = true;
        root.updateColors();
    }

    IpcHandler {
        target: "theme"

        function reloadColors() {
            root.reloadColors();
        }
    }

    IpcHandler {
        target: "fonts"
        function rescan() {
            root.scanFonts();
        }
    }

    Connections {
        target: Config
        function onSettingsLoaded() {
            root.updateColors();
        }
        function onRawSettingsChanged() {
            root.syncElementOpacity();
        }
    }

    Connections {
        target: typeof Matugen !== "undefined" ? Matugen : null
        function onGenerationFinished(success) {
            root._readInProgress = false;
            if (success) {
                themeWatcher.reload();
                matugenColorsWatcher.reload();
            }
        }
    }

    function applyMatugenColors(): bool {
        if (root.matugenColors) {
            root.applyColorObject(root.matugenColors);
            return true;
        }
        return false;
    }

    function faded(c) {
        return Qt.alpha(c, root.elementOpacity);
    }

    function syncElementOpacity() {
        const themeConfig = Config.getSetting("theme", {});
        const pct = themeConfig.elementOpacity !== undefined ? Number(themeConfig.elementOpacity) : 100;
        root.configuredBlurBackground = themeConfig.blurBackground !== undefined ? Boolean(themeConfig.blurBackground) : false;
        root.blurStyle = themeConfig.blurStyle === "liquid" ? "liquid" : "blur";
        root.configuredElementOpacity = isNaN(pct) ? 1.0 : Math.max(0, Math.min(1.0, pct / 100.0));
    }

    function updateColors() {
        let themeConfig = Config.getSetting("theme", {});

        root.fontFamily = themeConfig.fontFamily ?? root.defaultFontFamily;
        root.borderRadius = themeConfig.borderRadius ?? root.defaultBorderRadius;
        root.syncElementOpacity();

        let customColors = themeConfig.colors || themeConfig.palette || (themeConfig.base !== undefined ? themeConfig : null);

        if (root.isMatugenTheme()) {
            const fallback = root.matugenColors || root.defaultColors;
            root.applyColorObject(fallback);
            const wp = themeConfig.wallpaper || Config.getSetting("wallpaper", "");
            if (typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                if (typeof wp === "string" && wp !== "") {
                    Matugen.generate(wp, themeConfig.mode, themeConfig.schemeType);
                } else if (Config.dataReady && !Matugen.generatingWallpaper) {
                    Matugen.generateFromStatic(fallback, themeConfig.mode);
                }
            }
            root._readInProgress = false;
        } else {
            root._readInProgress = false;
            if (customColors) {
                root.applyColorObject(customColors);
                if (typeof Matugen !== "undefined" && typeof Matugen.generateFromStatic === "function") {
                    Matugen.generateFromStatic(customColors, themeConfig.mode);
                }
            } else {
                themeWatcher.reload();
            }
        }
    }

    function applyColorObject(c) {
        if (!c) return;

        let resolveHex = function(val) {
            if (!val) return "";
            if (typeof val === "string") return val;
            if (typeof val === "object") {
                if (val.hex) return val.hex;
                if (val.color) return val.color;
                if (val.default && val.default.hex) return val.default.hex;
            }
            return val.toString();
        };

        let names = ["base", "mantle", "crust", "surface0", "surface1", "surface2",
                     "overlay0", "overlay1", "overlay2", "text", "subtext0", "subtext1",
                     "blue", "sapphire", "peach", "green", "red", "mauve", "pink",
                     "yellow", "maroon", "teal"];

        let queue = [];
        for (let i = 0; i < names.length; i++) {
            let hexColor = resolveHex(c[names[i]]);
            if (!hexColor) continue;
            let nextColor = Qt.color(hexColor);
            let slot = (names[i] === "text" || names[i] === "subtext0" || names[i] === "subtext1") ? "_" + names[i] : names[i];
            if (root[slot].toString() !== nextColor.toString()) {
                queue.push({ name: slot, value: nextColor });
            }
        }

        root._colorQueue = queue;
        if (queue.length > 0) {
            root._flushColorQueue();
            if (root._colorQueue.length > 0) colorStepTimer.restart();
        }
    }

    function _flushColorQueue() {
        let n = Math.min(root.colorsPerFrame, root._colorQueue.length);
        for (let i = 0; i < n; i++) {
            let item = root._colorQueue[i];
            root[item.name] = item.value;
        }
        root._colorQueue = root._colorQueue.slice(n);
    }

    FrameAnimation {
        id: colorStepTimer
        onTriggered: {
            root._flushColorQueue();
            if (root._colorQueue.length === 0) stop();
        }
    }

    FileView {
        id: matugenColorsWatcher
        path: root.matugenConfigPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let txt = text().trim();
            if (txt !== "") {
                try {
                    let c = JSON.parse(txt);
                    let target = c && c.colors ? c.colors : c;
                    if (target) {
                        root.matugenColors = target;
                        if (root.isMatugenTheme()) {
                            root.applyColorObject(target);
                        }
                    }
                } catch(e) {}
            }
        }
    }

    FileView {
        id: themeWatcher
        path: root.configPath.startsWith("~") ? (Quickshell.env("HOME") ?? "") + root.configPath.slice(1) : root.configPath
        watchChanges: false

        onLoaded: {
            root._readInProgress = false;
            if (root.isMatugenTheme()) return;
            let txt = text().trim();
            if (txt !== "") {
                try {
                    let c = JSON.parse(txt);
                    let target = c && c.colors ? c.colors : c;
                    if (target) {
                        root.applyColorObject(target);
                    }
                } catch(e) {}
            }
        }
    }

    Component.onCompleted: {
        root._readInProgress = true;
        root.updateColors();
        root.updateActiveFontLoader();
    }
}
