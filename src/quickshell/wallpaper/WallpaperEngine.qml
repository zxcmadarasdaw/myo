import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtMultimedia
import "../"
import "../reusables"

ShellRoot {
    id: globalRoot

    Variants {
        id: root
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: barWindow
                GpuBackendObserver { observerKey: "wallpaper:" + barWindow.modelData.name }

                required property var modelData
                screen: modelData

                WlrLayershell.namespace: "wallpaper-bg"
                WlrLayershell.layer: WlrLayer.Background

                focusable: false
                exclusionMode: ExclusionMode.Ignore
                color: "#0a0a0f"

                anchors { top: true; bottom: true; left: true; right: true }

                readonly property string wpCacheDir: Caching.getCacheDir("wallpaper")
                readonly property string wpStatePath: wpCacheDir + "/current_" + barWindow.screen.name
                readonly property string wpCopyDir: wpCacheDir + "/copy_" + barWindow.screen.name
                readonly property string wpSnapshotPath: wpCacheDir + "/current_wallpaper.png"
                readonly property string wpMonitorSnapshotPath: wpCacheDir + "/current_wallpaper_" + barWindow.screen.name + ".png"

                property string currentWallpaperPath: ""
                property string originalFileName: ""
                property int activeLayer: 0
                property string pathA: ""
                property bool isVideoA: false
                property string pathB: ""
                property bool isVideoB: false
                property bool playbackPaused: false
                property bool snapReadyA: false
                property bool snapReadyB: false
                property int snapRevA: 0
                property int snapRevB: 0
                readonly property string layerSnapshotPathA: wpCacheDir + "/layer_" + barWindow.screen.name + "_a.png"
                readonly property string layerSnapshotPathB: wpCacheDir + "/layer_" + barWindow.screen.name + "_b.png"

                property int activeDuration: 1000
                property var pendingChange: null
                property bool capturingFrame: false
                property bool frozenActive: false
                readonly property bool transitionBusy: transitionAnim.running || videoWarmUpTimer.running || capturingFrame
                property real transitionProgress: 1.0
                property bool isPreloading: false
                property int configuredTransitionType: 0
                readonly property int activeTransitionType: GpuCompatibility.effective.wallpaperTransitions && !performanceMode ? configuredTransitionType : 0
                property string failedVideoA: ""
                property string failedVideoB: ""
                readonly property bool staticVideoA: GpuCompatibility.effective.fallback || performanceMode || (pathA !== "" && failedVideoA === pathA)
                readonly property bool staticVideoB: GpuCompatibility.effective.fallback || performanceMode || (pathB !== "" && failedVideoB === pathB)
                property bool wipeIsVertical: false
                property int swipeDirection: 0
                property real transitionOriginX: 0.5
                property real transitionOriginY: 0.5
                property real transitionSeed: 0.0
                property bool isInitialLoad: true
                property bool restoreHistory: true
                // Performance mode keeps the wallpaper but drops animated work:
                // static transitions, video snapshot instead of playback, GIF paused.
                readonly property bool performanceMode: !!(Config.getSetting("general", {}).performance)
                // Human readable reason when the current wallpaper failed to load.
                property string loadError: ""
                function reportLoadError(path, reason) {
                    // Deferred: a GIF fails synchronously while _loadNew() is still
                    // running, before currentWallpaperPath points at the new file.
                    Qt.callLater(function() {
                        if (!path || path !== barWindow.currentWallpaperPath) return;
                        barWindow.loadError = reason + ": " + path;
                        console.warn("[wallpaper] " + (barWindow.screen ? barWindow.screen.name : "?") + ": " + barWindow.loadError);
                    });
                }
                onPathAChanged: { if (!isVideo(pathA)) GpuCompatibility.forgetMedia((screen ? screen.name : "") + ":A"); }
                onPathBChanged: { if (!isVideo(pathB)) GpuCompatibility.forgetMedia((screen ? screen.name : "") + ":B"); }
                onStaticVideoAChanged: {
                    if (staticVideoA && isVideoA && pathA !== "" && failedVideoA !== pathA)
                        GpuCompatibility.observeMedia((screen ? screen.name : "") + ":A", pathA, "static-fallback", "Safe graphics uses a snapshot.");
                }
                onStaticVideoBChanged: {
                    if (staticVideoB && isVideoB && pathB !== "" && failedVideoB !== pathB)
                        GpuCompatibility.observeMedia((screen ? screen.name : "") + ":B", pathB, "static-fallback", "Safe graphics uses a snapshot.");
                }

                Connections {
                    target: GpuCompatibility
                    function onRetryVideoRequested() {
                        barWindow.failedVideoA = "";
                        barWindow.failedVideoB = "";
                    }
                    function onShadersAllowedChanged() {
                        if (!GpuCompatibility.shadersAllowed && barWindow.capturingFrame) {
                            // A shader can fail while an interrupted transition is
                            // waiting for an offscreen capture. Finish without it.
                            const next = barWindow.pendingChange;
                            barWindow.pendingChange = null;
                            captureWait.stop();
                            transitionAnim.stop();
                            videoWarmUpTimer.stop();
                            barWindow.capturingFrame = false;
                            barWindow.frozenActive = false;
                            if (next) barWindow.changeWallpaper(next.path, next.ttype);
                        }
                    }
                }

                Component.onCompleted: {
                    Wallpaper.registerEngine(barWindow.screen ? barWindow.screen.name : "", barWindow);
                }

                Component.onDestruction: {
                    const name = barWindow.screen ? barWindow.screen.name : "";
                    Wallpaper.unregisterEngine(name, barWindow);
                    GpuCompatibility.forgetMedia(name + ":A");
                    GpuCompatibility.forgetMedia(name + ":B");
                }

                onCurrentWallpaperPathChanged: {
                    loadError = "";
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenWallpaperPaths);
                        map[barWindow.screen.name] = currentWallpaperPath;
                        Wallpaper.screenWallpaperPaths = map;
                    }
                }

                onOriginalFileNameChanged: {
                    if (barWindow.screen && barWindow.screen.name) {
                        let map = Object.assign({}, Wallpaper.screenWallpapers);
                        map[barWindow.screen.name] = originalFileName;
                        Wallpaper.screenWallpapers = map;
                    }
                }

                Connections {
                    target: Wallpaper

                    function onWallpaperChanged(screenName, path, transition) {
                        if (screenName === "all" || screenName === barWindow.screen.name)
                            barWindow.changeWallpaper(path, transition);
                    }

                    function onPlaybackChanged(screenName, state) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            if (state === "pause") {
                                barWindow.playbackPaused = true;
                                barWindow.stopA();
                                barWindow.stopB();
                            } else if (state === "play") {
                                barWindow.playbackPaused = false;
                                if (barWindow.activeLayer === 0 && barWindow.isVideoA) barWindow.playA();
                                if (barWindow.activeLayer === 1 && barWindow.isVideoB) barWindow.playB();
                            }
                        }
                    }

                    function onWallpaperCleared(screenName) {
                        if (screenName === "all" || screenName === barWindow.screen.name) {
                            barWindow.clearLayers();
                            Quickshell.execDetached(["rm", "-f", "--", barWindow.wpStatePath, barWindow.wpStatePath + "_name"]);
                        }
                    }
                }

                function adoptFallbackWallpaper() {
                    adoptTimer.restart();
                }

                Timer {
                    id: adoptTimer
                    interval: 1500
                    onTriggered: {
                        if (barWindow.currentWallpaperPath !== "") return;
                        const own = barWindow.screen ? barWindow.screen.name : "";
                        const paths = Wallpaper.screenWallpaperPaths || {};
                        for (const name in paths) {
                            if (name !== own && paths[name] && barWindow.isSupportedMedia(paths[name])) {
                                barWindow.changeWallpaper(paths[name], 0);
                                return;
                            }
                        }
                        if (Wallpaper.lastRequestedAll && barWindow.isSupportedMedia(Wallpaper.lastRequestedAll))
                            barWindow.changeWallpaper(Wallpaper.lastRequestedAll, 0);
                    }
                }

                function clearLayers() {
                    transitionAnim.stop();
                    videoWarmUpTimer.stop();
                    captureWait.stop();
                    pendingChange = null;
                    capturingFrame = false;
                    frozenActive = false;
                    isPreloading = false;
                    transitionProgress = 1.0;
                    currentWallpaperPath = "";
                    originalFileName = "";
                    stopA();
                    stopB();
                    pathA = "";
                    pathB = "";
                    isVideoA = false;
                    isVideoB = false;
                    isInitialLoad = true;
                }

                FileView {
                    id: savedWallpaper
                    path: barWindow.wpStatePath
                    printErrors: false
                    watchChanges: true
                    onFileChanged: wallpaperReload.restart()
                    onLoaded: {
                        const savedPath = text().trim();
                        if (savedPath === barWindow.currentWallpaperPath) return;
                        if (savedPath === "") {
                            barWindow.restoreHistory = false;
                            barWindow.clearLayers();
                            return;
                        }
                        if (!barWindow.isSupportedMedia(savedPath)) {
                            console.warn("[wallpaper] unsupported saved wallpaper ignored: " + savedPath);
                            barWindow.adoptFallbackWallpaper();
                            return;
                        }
                        barWindow.pendingChange = null;
                        captureWait.stop();
                        barWindow.capturingFrame = false;
                        barWindow.frozenActive = false;
                        const fx = Wallpaper.resolveTransition(-1);
                        barWindow.configureTransition(fx, -1, -1);
                        barWindow._loadNew(savedPath, false);
                        savedTitle.reload();
                        if (barWindow.isVideo(savedPath)) {
                            videoSnapshotProcess.targetPath = savedPath;
                            videoSnapshotProcess.running = false;
                            videoSnapshotProcess.running = true;
                        } else if (Matugen.isMatugenTheme()) {
                            Matugen.generate(barWindow.isGif(savedPath) ? barWindow.wpSnapshotPath : savedPath);
                        }
                    }
                    onLoadFailed: {
                        barWindow.restoreHistory = false;
                        barWindow.clearLayers();
                        // No saved wallpaper for this output (first start, new or
                        // renamed monitor): reuse what another output shows so the
                        // screen is not left with the bare fallback color.
                        barWindow.adoptFallbackWallpaper();
                    }
                }

                FileView {
                    id: savedTitle
                    path: barWindow.wpStatePath + "_name"
                    printErrors: false
                    watchChanges: true
                    onFileChanged: reload()
                    onLoaded: {
                        const name = text().trim();
                        if (barWindow.currentWallpaperPath === "" || name === "") return;
                        barWindow.originalFileName = name;
                        if (!barWindow.restoreHistory) return;
                        barWindow.restoreHistory = false;
                        Quickshell.execDetached(["bash", "-c",
                            "if [ \"$(head -n 1 -- \"$1\" 2>/dev/null)\" != \"$2\" ]; then\n    { printf '%s\\n' \"$2\"; grep -v -F -x -- \"$2\" \"$1\" 2>/dev/null || true; } > \"$1.tmp.$$\" &&\n        mv -f -- \"$1.tmp.$$\" \"$1\"\nfi",
                            "_", barWindow.wpCacheDir + "/history.txt", name]);
                    }
                    onLoadFailed: {
                        if (barWindow.currentWallpaperPath !== "") barWindow.restoreHistory = false;
                    }
                }

                Connections {
                    target: Themess
                    function onStoresChanged() {
                        wallpaperReload.restart();
                        savedTitle.reload();
                    }
                }

                Timer {
                    id: wallpaperReload
                    interval: 80
                    onTriggered: savedWallpaper.reload()
                }

                Timer {
                    id: videoWarmUpTimer
                    interval: 250
                    repeat: false
                    onTriggered: barWindow.triggerTransition()
                }

                Process {
                    id: layerSnapshotA
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null",
                        "_",
                        targetPath,
                        barWindow.layerSnapshotPathA
                    ]
                    onExited: exitCode => {
                        if (exitCode === 0) {
                            barWindow.snapReadyA = true;
                            barWindow.snapRevA++;
                        }
                    }
                }

                Process {
                    id: layerSnapshotB
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null",
                        "_",
                        targetPath,
                        barWindow.layerSnapshotPathB
                    ]
                    onExited: exitCode => {
                        if (exitCode === 0) {
                            barWindow.snapReadyB = true;
                            barWindow.snapRevB++;
                        }
                    }
                }

                Process {
                    id: videoSnapshotProcess
                    running: false
                    property string targetPath: ""
                    command: [
                        "bash", "-c",
                        "ffmpeg -y -hide_banner -loglevel error -ss 00:00:01 -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null || ffmpeg -y -hide_banner -loglevel error -i \"$1\" -frames:v 1 -q:v 2 \"$2\" 2>/dev/null; cp -f \"$2\" \"$3\" 2>/dev/null || true",
                        "_",
                        targetPath,
                        barWindow.wpSnapshotPath,
                        barWindow.wpMonitorSnapshotPath
                    ]
                    onExited: exitCode => {
                        if (exitCode === 0 && typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                            Matugen.generate(barWindow.wpSnapshotPath);
                        }
                    }
                }

                function snapshotLayer(slot, path) {
                    let proc = slot === 0 ? layerSnapshotA : layerSnapshotB;
                    if (slot === 0) barWindow.snapReadyA = false;
                    else barWindow.snapReadyB = false;
                    proc.targetPath = path;
                    proc.running = false;
                    proc.running = true;
                }

                function isGif(path) {
                    return path.toLowerCase().endsWith(".gif");
                }

                function isVideo(p) {
                    let lp = p.toLowerCase();
                    return lp.endsWith(".mp4") || lp.endsWith(".mkv") ||
                           lp.endsWith(".mov") || lp.endsWith(".webm");
                }

                function isSupportedMedia(p) {
                    if (!p) return false;
                    let lp = p.toLowerCase();
                    return lp.endsWith(".jpg") || lp.endsWith(".jpeg") || lp.endsWith(".png") ||
                           lp.endsWith(".webp") || lp.endsWith(".gif") || lp.endsWith(".bmp") ||
                           lp.endsWith(".avif") || barWindow.isVideo(p);
                }

                function playA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.play === "function") {
                        videoLoaderA.item.play();
                    }
                }

                function stopA() {
                    if (videoLoaderA.item && typeof videoLoaderA.item.stop === "function") {
                        videoLoaderA.item.stop();
                    }
                }

                function playB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.play === "function") {
                        videoLoaderB.item.play();
                    }
                }

                function stopB() {
                    if (videoLoaderB.item && typeof videoLoaderB.item.stop === "function") {
                        videoLoaderB.item.stop();
                    }
                }

                function triggerTransition() {
                    videoWarmUpTimer.stop();
                    barWindow.isPreloading = false;
                    transitionAnim.restart();
                }

                function clearOutgoingLayer() {
                    if (barWindow.activeLayer === 0) {
                        barWindow.stopB();
                        barWindow.pathB = "";
                        barWindow.isVideoB = false;
                    } else {
                        barWindow.stopA();
                        barWindow.pathA = "";
                        barWindow.isVideoA = false;
                    }
                }

                function completeTransition() {
                    barWindow.clearOutgoingLayer();
                    barWindow.frozenActive = false;
                }

                function applyFrozenFrame() {
                    captureWait.stop();
                    transitionAnim.stop();
                    videoWarmUpTimer.stop();
                    barWindow.capturingFrame = false;
                    barWindow.frozenActive = true;
                    let next = barWindow.pendingChange;
                    barWindow.pendingChange = null;
                    if (!next) return;
                    barWindow.changeWallpaper(next.path, next.ttype);
                    barWindow.clearOutgoingLayer();
                }

                function interruptWith(path, ttype) {
                    if (!GpuCompatibility.shadersAllowed) {
                        transitionAnim.stop();
                        videoWarmUpTimer.stop();
                        captureWait.stop();
                        barWindow.capturingFrame = false;
                        barWindow.completeTransition();
                        barWindow.changeWallpaper(path, ttype);
                        return;
                    }
                    if (typeof DesktopMenuController !== "undefined" && DesktopMenuController.isMenuShuffle) {
                        let isTargetScreen = !DesktopMenuController.screen || !DesktopMenuController.screen.name || (barWindow.screen && DesktopMenuController.screen.name === barWindow.screen.name);
                        if (isTargetScreen) {
                            ttype = { type: 2, originX: DesktopMenuController.menuOriginX, originY: DesktopMenuController.menuOriginY };
                        }
                    }
                    barWindow.pendingChange = { path: path, ttype: ttype };
                    if (barWindow.capturingFrame) return;
                    barWindow.capturingFrame = true;
                    frozenFrame.scheduleUpdate();
                    captureWait.frames = 0;
                    captureWait.restart();
                }

                function _loadNew(path, force) {
                    if (!path) return;
                    if (!force && path === barWindow.currentWallpaperPath) return;

                    let cleanPath = String(path).trim();
                    let vid = barWindow.isVideo(cleanPath);
                    if (vid) barWindow.snapshotLayer(barWindow.activeLayer === 1 ? 0 : 1, cleanPath);

                    let slash = cleanPath.lastIndexOf("/");
                    let filename = cleanPath.substring(slash + 1);
                    if (!filename.startsWith("wallpaper.")) {
                        barWindow.originalFileName = filename;
                    }

                    if (barWindow.isInitialLoad) {
                        barWindow.isInitialLoad = false;
                        barWindow.transitionProgress = 1.0;
                        barWindow.isPreloading = false;
                        if (barWindow.activeLayer === 1) {
                            barWindow.pathA = cleanPath;
                            barWindow.isVideoA = vid;
                            barWindow.activeLayer = 0;
                            if (vid) barWindow.playA();
                        } else {
                            barWindow.pathB = cleanPath;
                            barWindow.isVideoB = vid;
                            barWindow.activeLayer = 1;
                            if (vid) barWindow.playB();
                        }
                        barWindow.currentWallpaperPath = cleanPath;
                        return;
                    }

                    transitionAnim.stop();
                    videoWarmUpTimer.stop();
                    barWindow.transitionProgress = 0.0;
                    barWindow.isPreloading = true;

                    if (barWindow.activeLayer === 1) {
                        barWindow.pathA = cleanPath;
                        barWindow.isVideoA = vid;
                        barWindow.activeLayer = 0;
                        if (vid) {
                            barWindow.playA();
                            videoWarmUpTimer.restart();
                        } else {
                            barWindow.triggerTransition();
                        }
                    } else {
                        barWindow.pathB = cleanPath;
                        barWindow.isVideoB = vid;
                        barWindow.activeLayer = 1;
                        if (vid) {
                            barWindow.playB();
                            videoWarmUpTimer.restart();
                        } else {
                            barWindow.triggerTransition();
                        }
                    }

                    barWindow.currentWallpaperPath = cleanPath;
                }

                function configureTransition(fx, customOriginX, customOriginY) {
                    barWindow.configuredTransitionType = fx.type;
                    barWindow.activeDuration = fx.duration;
                    barWindow.wipeIsVertical = fx.vertical;
                    barWindow.swipeDirection = fx.direction;
                    barWindow.transitionSeed = Math.random() * 100.0;

                    if (customOriginX >= 0 && customOriginY >= 0) {
                        barWindow.transitionOriginX = customOriginX;
                        barWindow.transitionOriginY = customOriginY;
                    } else if (fx.centered) {
                        barWindow.transitionOriginX = 0.5;
                        barWindow.transitionOriginY = 0.5;
                    } else {
                        barWindow.transitionOriginX = 0.15 + Math.random() * 0.70;
                        barWindow.transitionOriginY = 0.15 + Math.random() * 0.70;
                    }
                }

                function changeWallpaper(path, ttype) {
                    if (!path) return;
                    if (barWindow.transitionBusy) {
                        barWindow.interruptWith(path, ttype);
                        return;
                    }

                    barWindow.isInitialLoad = false;

                    let fromMenu = false;
                    let customOriginX = -1;
                    let customOriginY = -1;
                    let chosenType = -1;

                    if (typeof ttype === "object" && ttype !== null) {
                        if (ttype.type !== undefined) chosenType = Number(ttype.type);
                        if (ttype.originX !== undefined) customOriginX = Number(ttype.originX);
                        if (ttype.originY !== undefined) customOriginY = Number(ttype.originY);
                        fromMenu = true;
                    } else if (typeof ttype === "string" && ttype.indexOf("circle") !== -1) {
                        chosenType = 2;
                        let parts = ttype.split(":");
                        if (parts.length >= 3) {
                            customOriginX = parseFloat(parts[1]);
                            customOriginY = parseFloat(parts[2]);
                        }
                        fromMenu = true;
                    } else if (typeof ttype === "number" && ttype >= 0) {
                        chosenType = ttype;
                    }

                    if (typeof DesktopMenuController !== "undefined" && DesktopMenuController.isMenuShuffle) {
                        let isTargetScreen = !DesktopMenuController.screen || !DesktopMenuController.screen.name || (barWindow.screen && DesktopMenuController.screen.name === barWindow.screen.name);
                        if (isTargetScreen) {
                            fromMenu = true;
                            chosenType = 2;
                            customOriginX = DesktopMenuController.menuOriginX;
                            customOriginY = DesktopMenuController.menuOriginY;
                        }
                    }

                    let fx = Wallpaper.resolveTransition(chosenType);
                    barWindow.configureTransition(fx, fromMenu ? customOriginX : -1, fromMenu ? customOriginY : -1);

                    if (typeof DesktopMenuController !== "undefined") {
                        DesktopMenuController.isMenuShuffle = false;
                    }

                    let cleanPath = String(path).trim();
                    let slash = cleanPath.lastIndexOf("/");
                    let origName = cleanPath.substring(slash + 1);
                    let dot = cleanPath.lastIndexOf(".");
                    let ext = (dot !== -1 && dot > slash) ? cleanPath.substring(dot) : "";
                    let dest = wpCopyDir + "/wallpaper" + ext;
                    let histFile = wpCacheDir + "/history.txt";
                    let vid = barWindow.isVideo(cleanPath);
                    let snapshotPath = barWindow.wpSnapshotPath;
                    let monSnapshotPath = barWindow.wpMonitorSnapshotPath;
                    Quickshell.execDetached(["bash", "-c",
                        "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3\" && printf '%s' \"$4\" > \"${3}_name\" && cp -f \"$2\" \"$5\"" +
                        " && if [ \"$9\" != 1 ]; then cp -f \"$2\" \"$6\" && cp -f \"$2\" \"$7\"; fi" +
                        " && ( HIST=\"$8\"; if [ -f \"$HIST\" ]; then grep -v -F -x -- \"$4\" \"$HIST\" > \"$HIST.tmp\" 2>/dev/null || true; printf '%s\\n' \"$4\" | cat - \"$HIST.tmp\" > \"$HIST\"; rm -f \"$HIST.tmp\"; else printf '%s\\n' \"$4\" > \"$HIST\"; fi )",
                        "_", wpCopyDir, cleanPath, wpStatePath, origName, dest, snapshotPath, monSnapshotPath, histFile, vid ? "1" : "0"
                    ]);

                    if (vid) {
                        videoSnapshotProcess.targetPath = cleanPath;
                        videoSnapshotProcess.running = false;
                        videoSnapshotProcess.running = true;
                    } else {
                        if (typeof Matugen !== "undefined" && typeof Matugen.generate === "function") {
                            Matugen.generate(cleanPath);
                        }
                    }

                    barWindow._loadNew(cleanPath, true);
                }

                function handleDrop(drop) {
                    let raw = "";
                    if (drop.hasUrls && drop.urls.length > 0) {
                        raw = drop.urls[0].toString();
                    } else if (drop.hasText && drop.text.length > 0) {
                        let lines = drop.text.trim().split("\n");
                        raw = lines[0].trim();
                    }
                    if (!raw) return;

                    let cleanPath = decodeURIComponent(raw.replace(/^file:\/\//, "")).trim();
                    if (!barWindow.isSupportedMedia(cleanPath)) return;

                    let scrW = barWindow.width > 0 ? barWindow.width : (barWindow.screen && barWindow.screen.geometry ? barWindow.screen.geometry.width : 1920);
                    let scrH = barWindow.height > 0 ? barWindow.height : (barWindow.screen && barWindow.screen.geometry ? barWindow.screen.geometry.height : 1080);
                    let normX = scrW > 0 ? Math.max(0.0, Math.min(1.0, drop.x / scrW)) : 0.5;
                    let normY = scrH > 0 ? Math.max(0.0, Math.min(1.0, drop.y / scrH)) : 0.5;

                    barWindow.changeWallpaper(cleanPath, {
                        type: 2,
                        originX: normX,
                        originY: normY
                    });
                }

                NumberAnimation {
                    id: transitionAnim
                    target: barWindow
                    property: "transitionProgress"
                    from: 0.0
                    to: 1.0
                    duration: barWindow.activeDuration
                    easing.type: Easing.InOutCubic
                    onFinished: barWindow.completeTransition()
                }

                FrameAnimation {
                    id: captureWait
                    property int frames: 0
                    onTriggered: {
                        captureWait.frames++;
                        if (captureWait.frames >= 60) barWindow.applyFrozenFrame();
                    }
                }


                Component {
                    id: videoLayerCompA
                    Item {
                        anchors.fill: parent
                        function play() { if (!barWindow.staticVideoA) playerA.play(); }
                        function stop() { playerA.stop(); }

                        MediaPlayer {
                            id: playerA
                            source: barWindow.isVideoA && barWindow.pathA ? Caching.fileUrl(barWindow.pathA) : ""
                            videoOutput: videoOutputA
                            loops: MediaPlayer.Infinite
                            onSourceChanged: GpuCompatibility.observeMedia(barWindow.screen.name + ":A", barWindow.pathA, "loading", "")
                            onErrorOccurred: function(error, errorString) {
                                GpuCompatibility.observeMedia(barWindow.screen.name + ":A", barWindow.pathA, "error", errorString);
                                const failedPath = barWindow.pathA;
                                barWindow.reportLoadError(failedPath, "Video playback failed (" + errorString + "); codec may be missing, e.g. H.264 with ffmpeg-free");
                                Qt.callLater(function() { barWindow.failedVideoA = failedPath; });
                            }
                            onPlaybackStateChanged: {
                                if (playbackState === MediaPlayer.PlayingState)
                                    GpuCompatibility.observeMedia(barWindow.screen.name + ":A", barWindow.pathA, "playing", "Qt playback started; hardware decoding and visible frames are not confirmed.");
                            }
                            onMediaStatusChanged: {
                                if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && barWindow.activeLayer === 0 && barWindow.isVideoA && !barWindow.playbackPaused) {
                                    playerA.play();
                                }
                            }
                        }

                        VideoOutput {
                            id: videoOutputA
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Component {
                    id: videoLayerCompB
                    Item {
                        anchors.fill: parent
                        function play() { if (!barWindow.staticVideoB) playerB.play(); }
                        function stop() { playerB.stop(); }

                        MediaPlayer {
                            id: playerB
                            source: barWindow.isVideoB && barWindow.pathB ? Caching.fileUrl(barWindow.pathB) : ""
                            videoOutput: videoOutputB
                            loops: MediaPlayer.Infinite
                            onSourceChanged: GpuCompatibility.observeMedia(barWindow.screen.name + ":B", barWindow.pathB, "loading", "")
                            onErrorOccurred: function(error, errorString) {
                                GpuCompatibility.observeMedia(barWindow.screen.name + ":B", barWindow.pathB, "error", errorString);
                                const failedPath = barWindow.pathB;
                                barWindow.reportLoadError(failedPath, "Video playback failed (" + errorString + "); codec may be missing, e.g. H.264 with ffmpeg-free");
                                Qt.callLater(function() { barWindow.failedVideoB = failedPath; });
                            }
                            onPlaybackStateChanged: {
                                if (playbackState === MediaPlayer.PlayingState)
                                    GpuCompatibility.observeMedia(barWindow.screen.name + ":B", barWindow.pathB, "playing", "Qt playback started; hardware decoding and visible frames are not confirmed.");
                            }
                            onMediaStatusChanged: {
                                if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && barWindow.activeLayer === 1 && barWindow.isVideoB && !barWindow.playbackPaused) {
                                    playerB.play();
                                }
                            }
                        }

                        VideoOutput {
                            id: videoOutputB
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                        }
                    }
                }

                Item {
                    id: scene
                    anchors.fill: parent
                    clip: true

                    ShaderEffectSource {
                        id: frozenFrame
                        anchors.fill: parent
                        z: 0
                        sourceItem: GpuCompatibility.shadersAllowed && (barWindow.capturingFrame || barWindow.frozenActive) ? scene : null
                        live: false
                        recursive: true
                        hideSource: false
                        visible: GpuCompatibility.shadersAllowed && (barWindow.capturingFrame || barWindow.frozenActive)
                        onScheduledUpdateCompleted: {
                            if (barWindow.capturingFrame) barWindow.applyFrozenFrame();
                        }
                    }

                    ShaderEffect {
                        id: transitionShaderA
                        onStatusChanged: GpuCompatibility.observeShader("wallpaper-transitionShaderA", status, log)
                        anchors.fill: parent
                        visible: false
                        layer.enabled: layerA.layer.enabled

                        property vector2d itemSize: Qt.vector2d(width, height)
                        property real progress: barWindow.transitionProgress
                        property real transitionType: barWindow.activeTransitionType
                        property vector2d origin: Qt.vector2d(barWindow.transitionOriginX, barWindow.transitionOriginY)
                        property vector4d params: Qt.vector4d(barWindow.wipeIsVertical ? 1.0 : 0.0, barWindow.swipeDirection, barWindow.transitionSeed, 0.0)
                        property color tint: "transparent"

                        fragmentShader: GpuCompatibility.shadersAllowed ? Caching.fileUrl(Caching.serpantinumDir + "/assets/shaders/transitions/wallpaper_transition.frag.qsb") : ""
                    }

                    Item {
                        id: layerA
                        width: parent.width
                        height: parent.height

                        readonly property bool isIncoming: barWindow.activeLayer === 0
                        readonly property real p: barWindow.transitionProgress

                        z: isIncoming ? 2 : 1
                        visible: isIncoming || (p < 1.0 && !barWindow.frozenActive)

                        opacity: {
                            if (barWindow.isPreloading && isIncoming) return 0.0;
                            if (barWindow.activeTransitionType !== 0) return 1.0;
                            return isIncoming ? p : 1.0 - p;
                        }

                        layer.enabled: barWindow.activeTransitionType !== 0 && isIncoming && !barWindow.isPreloading && p < 1.0
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: transitionShaderA
                            maskThresholdMin: 0.0
                            maskSpreadAtMin: 0.0
                        }

                        Image {
                            id: imgA
                            anchors.fill: parent
                            onStatusChanged: if (status === Image.Error) barWindow.reportLoadError(barWindow.pathA, "Cannot decode image (missing Qt image plugin, e.g. qt6-qtimageformats for WebP, or damaged file)")
                            source: !barWindow.isVideoA && !barWindow.isGif(barWindow.pathA) && barWindow.pathA ? Caching.fileUrl(barWindow.pathA) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: !barWindow.isVideoA && !barWindow.isGif(barWindow.pathA) && barWindow.pathA !== ""
                            cache: true
                            sourceSize.width: parent.width > 0 ? Math.ceil(parent.width * (Screen.devicePixelRatio || 1)) : 0
                            sourceSize.height: parent.height > 0 ? Math.ceil(parent.height * (Screen.devicePixelRatio || 1)) : 0
                        }

                        // GIF layer, loaded by URL: wallpaper/ has no qmldir, so under
                        // Quickshell (qs: URLs) WallpaperGif is not a type here, and a
                        // broken GIF layer must not stop the whole shell.
                        Loader {
                            id: gifLayerA
                            anchors.fill: parent
                            source: Qt.resolvedUrl("WallpaperGif.qml")
                            onStatusChanged: if (status === Loader.Error) console.warn("[wallpaper] WallpaperGif.qml failed to load; GIF wallpapers are unavailable")
                            Binding { target: gifLayerA.item; when: gifLayerA.item !== null; property: "imageUrl"; value: Caching.fileUrl(barWindow.pathA) }
                            Binding { target: gifLayerA.item; when: gifLayerA.item !== null; property: "playing"; value: !barWindow.playbackPaused && !GpuCompatibility.effective.fallback && !barWindow.performanceMode }
                            Connections {
                                target: gifLayerA.item
                                function onFailed(reason) { barWindow.reportLoadError(barWindow.pathA, reason) }
                            }
                        }

                        Image {
                            anchors.fill: parent
                            visible: barWindow.isVideoA && barWindow.staticVideoA && barWindow.snapReadyA
                            source: visible ? Caching.fileUrl(barWindow.layerSnapshotPathA) + "?rev=" + barWindow.snapRevA : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: barWindow.isVideoA && barWindow.staticVideoA && !barWindow.snapReadyA
                            text: "Video wallpaper unavailable — open Display → GPU compatibility"
                            color: "white"
                            width: parent.width * 0.8
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Loader {
                            id: videoLoaderA
                            anchors.fill: parent
                            active: barWindow.isVideoA && barWindow.pathA !== "" && !barWindow.staticVideoA
                            asynchronous: false
                            sourceComponent: videoLayerCompA
                            visible: barWindow.isVideoA
                            onLoaded: {
                                if (item && barWindow.activeLayer === 0 && barWindow.isVideoA && !barWindow.playbackPaused) {
                                    item.play();
                                }
                            }
                        }
                    }

                    ShaderEffect {
                        id: transitionShaderB
                        onStatusChanged: GpuCompatibility.observeShader("wallpaper-transitionShaderB", status, log)
                        anchors.fill: parent
                        visible: false
                        layer.enabled: layerB.layer.enabled

                        property vector2d itemSize: Qt.vector2d(width, height)
                        property real progress: barWindow.transitionProgress
                        property real transitionType: barWindow.activeTransitionType
                        property vector2d origin: Qt.vector2d(barWindow.transitionOriginX, barWindow.transitionOriginY)
                        property vector4d params: Qt.vector4d(barWindow.wipeIsVertical ? 1.0 : 0.0, barWindow.swipeDirection, barWindow.transitionSeed, 0.0)
                        property color tint: "transparent"

                        fragmentShader: GpuCompatibility.shadersAllowed ? Caching.fileUrl(Caching.serpantinumDir + "/assets/shaders/transitions/wallpaper_transition.frag.qsb") : ""
                    }

                    Item {
                        id: layerB
                        width: parent.width
                        height: parent.height

                        readonly property bool isIncoming: barWindow.activeLayer === 1
                        readonly property real p: barWindow.transitionProgress

                        z: isIncoming ? 2 : 1
                        visible: isIncoming || (p < 1.0 && !barWindow.frozenActive)

                        opacity: {
                            if (barWindow.isPreloading && isIncoming) return 0.0;
                            if (barWindow.activeTransitionType !== 0) return 1.0;
                            return isIncoming ? p : 1.0 - p;
                        }

                        layer.enabled: barWindow.activeTransitionType !== 0 && isIncoming && !barWindow.isPreloading && p < 1.0
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: transitionShaderB
                            maskThresholdMin: 0.0
                            maskSpreadAtMin: 0.0
                        }

                        Image {
                            id: imgB
                            anchors.fill: parent
                            onStatusChanged: if (status === Image.Error) barWindow.reportLoadError(barWindow.pathB, "Cannot decode image (missing Qt image plugin, e.g. qt6-qtimageformats for WebP, or damaged file)")
                            source: !barWindow.isVideoB && !barWindow.isGif(barWindow.pathB) && barWindow.pathB ? Caching.fileUrl(barWindow.pathB) : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: !barWindow.isVideoB && !barWindow.isGif(barWindow.pathB) && barWindow.pathB !== ""
                            cache: true
                            sourceSize.width: parent.width > 0 ? Math.ceil(parent.width * (Screen.devicePixelRatio || 1)) : 0
                            sourceSize.height: parent.height > 0 ? Math.ceil(parent.height * (Screen.devicePixelRatio || 1)) : 0
                        }

                        // GIF layer, loaded by URL (see gifLayerA).
                        Loader {
                            id: gifLayerB
                            anchors.fill: parent
                            source: Qt.resolvedUrl("WallpaperGif.qml")
                            onStatusChanged: if (status === Loader.Error) console.warn("[wallpaper] WallpaperGif.qml failed to load; GIF wallpapers are unavailable")
                            Binding { target: gifLayerB.item; when: gifLayerB.item !== null; property: "imageUrl"; value: Caching.fileUrl(barWindow.pathB) }
                            Binding { target: gifLayerB.item; when: gifLayerB.item !== null; property: "playing"; value: !barWindow.playbackPaused && !GpuCompatibility.effective.fallback && !barWindow.performanceMode }
                            Connections {
                                target: gifLayerB.item
                                function onFailed(reason) { barWindow.reportLoadError(barWindow.pathB, reason) }
                            }
                        }

                        Image {
                            anchors.fill: parent
                            visible: barWindow.isVideoB && barWindow.staticVideoB && barWindow.snapReadyB
                            source: visible ? Caching.fileUrl(barWindow.layerSnapshotPathB) + "?rev=" + barWindow.snapRevB : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: barWindow.isVideoB && barWindow.staticVideoB && !barWindow.snapReadyB
                            text: "Video wallpaper unavailable — open Display → GPU compatibility"
                            color: "white"
                            width: parent.width * 0.8
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Loader {
                            id: videoLoaderB
                            anchors.fill: parent
                            active: barWindow.isVideoB && barWindow.pathB !== "" && !barWindow.staticVideoB
                            asynchronous: false
                            sourceComponent: videoLayerCompB
                            visible: barWindow.isVideoB
                            onLoaded: {
                                if (item && barWindow.activeLayer === 1 && barWindow.isVideoB && !barWindow.playbackPaused) {
                                    item.play();
                                }
                            }
                        }
                    }

                    ShaderEffect {
                        id: paintGlow
                        onStatusChanged: GpuCompatibility.observeShader("wallpaper-paintGlow", status, log)
                        anchors.fill: parent
                        z: 3
                        visible: barWindow.activeTransitionType === 4 && !barWindow.isPreloading && barWindow.transitionProgress < 1.0

                        property vector2d itemSize: Qt.vector2d(width, height)
                        property real progress: barWindow.transitionProgress
                        property real transitionType: barWindow.activeTransitionType
                        property vector2d origin: Qt.vector2d(barWindow.transitionOriginX, barWindow.transitionOriginY)
                        property vector4d params: Qt.vector4d(0.0, 0.0, barWindow.transitionSeed, 1.0)
                        property color tint: ThemeBackend.mauve

                        fragmentShader: GpuCompatibility.shadersAllowed ? Caching.fileUrl(Caching.serpantinumDir + "/assets/shaders/transitions/wallpaper_transition.frag.qsb") : ""
                    }
                }

                // Safe fallback: the window color stays visible and the user gets
                // a readable reason instead of an unexplained empty desktop.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: parent.height * 0.12
                    width: parent.width * 0.7
                    z: 10
                    visible: barWindow.loadError !== ""
                    text: barWindow.loadError + "\nChoose another wallpaper with Super+W. Details: serpantinum logs"
                    color: "#e0e0e0"
                    style: Text.Outline
                    styleColor: "#000000"
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }

                DropArea {
                    anchors.fill: parent

                    onEntered: drag => {
                        if (drag.hasUrls || drag.hasText) {
                            if (typeof drag.acceptProposedAction === "function") {
                                drag.acceptProposedAction();
                            } else if (typeof drag.accept === "function") {
                                drag.accept();
                            }
                            drag.accepted = true;
                        }
                    }

                    onDropped: drop => {
                        barWindow.handleDrop(drop);
                        if (typeof drop.acceptProposedAction === "function") {
                            drop.acceptProposedAction();
                        } else if (typeof drop.accept === "function") {
                            drop.accept();
                        }
                        drop.accepted = true;
                    }

                    MouseArea {
                        id: desktopArea
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton | Qt.LeftButton | Qt.MiddleButton

                        // Infinite canvas: dragging the empty desktop moves the camera
                        // of this monitor, the wheel zooms or pans it (see settings).
                        // Clicks keep their old meaning.
                        readonly property var canvasCamera: CanvasState.cameraFor(barWindow.screen ? barWindow.screen.name : "")
                        property real pressX: 0
                        property real pressY: 0
                        property real lastX: 0
                        property real lastY: 0
                        property bool panArmed: false
                        property bool panning: false
                        property bool swallowClick: false

                        function endPan() {
                            if (panning && canvasCamera) canvasCamera.dragEnd();
                            swallowClick = panning;
                            panning = false;
                            panArmed = false;
                        }

                        onPressed: mouse => {
                            pressX = mouse.x;
                            pressY = mouse.y;
                            lastX = mouse.x;
                            lastY = mouse.y;
                            panning = false;
                            swallowClick = false;
                            panArmed = canvasCamera !== null && canvasCamera.active
                                && (mouse.button === Qt.MiddleButton || (mouse.button === Qt.LeftButton && canvasCamera.cfg.dragToPan));
                        }

                        onPositionChanged: mouse => {
                            if (!pressed || !panArmed) return;
                            if (!panning) {
                                if (Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) < 6) return;
                                panning = true;
                                DesktopMenuController.hide();
                                canvasCamera.dragStart();
                            }
                            canvasCamera.dragMove(mouse.x - lastX, mouse.y - lastY);
                            lastX = mouse.x;
                            lastY = mouse.y;
                        }

                        onReleased: endPan()
                        onCanceled: endPan()

                        onWheel: wheel => {
                            let used = canvasCamera !== null && canvasCamera.handleWheel(
                                wheel.x, wheel.y, wheel.angleDelta.x, wheel.angleDelta.y, wheel.pixelDelta.x, wheel.pixelDelta.y,
                                (wheel.modifiers & Qt.ControlModifier) !== 0, (wheel.modifiers & Qt.ShiftModifier) !== 0);
                            wheel.accepted = !!used;
                        }

                        onClicked: mouse => {
                            if (swallowClick) {
                                swallowClick = false;
                                return;
                            }
                            if (mouse.button === Qt.RightButton) {
                                DesktopMenuController.toggle(barWindow.screen, mouse.x, mouse.y, "desktop");
                            } else if (mouse.button === Qt.LeftButton) {
                                DesktopMenuController.hide();
                            }
                        }
                    }
                }
            }
        }
    }
}
