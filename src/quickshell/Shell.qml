import QtQuick
import Quickshell
import Quickshell.Io
import "widgets"
import "widgets/canvas"
import "notifications/weather"
import "notifications/battery"

ShellRoot {
    readonly property bool performanceMode: !!(Config.getSetting("general", {}).performance)
    readonly property bool quickactionsEnabled: Config.getSetting("general", {}).quickactions !== false
    readonly property bool dockEnabled: Config.getSetting("dock", {}).enabled !== false

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
        function onReloadFailed(errorString) { Quickshell.inhibitReloadPopup() }
    }

    LazyLoader {
        id: screenshotLoader
        ScreenshotOverlay {}
    }

    function ensureScreenshotOverlay() {
        if (!screenshotLoader.item) screenshotLoader.active = true;
        return screenshotLoader.item;
    }

    IpcHandler {
        target: "screenshotOverlay"

        function toggle(img: string, editMode: string, audioPrefs: string, cGeom: string, cGeomVideo: string, cMode: string, cBackend: string, targetMon: string): void {
            let overlay = ensureScreenshotOverlay();
            if (overlay) overlay.toggleOverlay(img, editMode, audioPrefs, cGeom, cGeomVideo, cMode, cBackend, targetMon);
        }

        function activate(img: string, editMode: string, audioPrefs: string, cGeom: string, cGeomVideo: string, cMode: string, cBackend: string, targetMon: string): void {
            let overlay = ensureScreenshotOverlay();
            if (overlay) overlay.activate(img, editMode, audioPrefs, cGeom, cGeomVideo, cMode, cBackend, targetMon);
        }

        function deactivate(): void {
            if (screenshotLoader.item) screenshotLoader.item.deactivate();
        }
    }

    Main { onSettingsOpening: widgetRedactor.close() }
    Bar {}
    Lock {}
    WidgetRedactor { id: widgetRedactor }
    LockRedactor {}

    Launcher {}
    Clipboard {}    
    Dashboard {}

    // Process Explorer exists only while open (or closing), so it holds no
    // keyboard focus and runs no sampler in the background.
    LazyLoader {
        active: ProcessExplorerController.loaded
        ProcessExplorer {}
    }

    Polkit {}
    WellbeingLimitOverlay {}
    PopoutManager {}

    Loader {
        active: dockEnabled
        sourceComponent: Dock {}
    }

    Idle {}
    Variants {
        model: performanceMode ? [] : Quickshell.screens
        delegate: WidgetLoader {
            required property var modelData
            screen: modelData
            monitorName: modelData.name
        }
    }
    // The wallpaper is always loaded. Performance mode used to unload it, which
    // left a bare black desktop; the engine itself now skips animations,
    // transitions and video playback while performance mode is on.
    Loader {
        active: true
        sourceComponent: WallpaperEngine {}
    }
    // Infinite canvas: minimap, widget navigator and the "canvas" IPC target.
    Loader {
        active: !performanceMode
        sourceComponent: CanvasHud {}
    }
    Loader {
        active: !performanceMode && quickactionsEnabled
        sourceComponent: Floating {}
    }

    Component.onCompleted: {
        Qt.application.organization = "serpantinum";
        Qt.application.domain = "serpantinum.org";
        Qt.application.name = "serpantinum";
        FirstLaunch.checkFirstLaunch();
        SysNotif.checkBattery();
        WeatherAlerts.isQuietNow();
        GovAlerts.refresh();
        GpuCompatibility.start();
    }
}
