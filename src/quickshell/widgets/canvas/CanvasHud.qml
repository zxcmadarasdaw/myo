import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import "../../"
import "../../reusables"
import "CanvasMath.js" as CM

// Desktop side of the infinite canvas:
//  - a small minimap per monitor (auto / always / never, see settings)
//  - the navigator: search a widget and fly to it
//  - the "canvas" IPC target used by keybinds and `serpantinum canvas ...`
Scope {
    id: hud

    function s(val) { return Scaler.s(val); }
    function icon(code) { return String.fromCodePoint(code); }

    function focusedMonitor() {
        try {
            if (typeof Hyprland !== "undefined" && Hyprland.focusedMonitor && Hyprland.focusedMonitor.name) {
                return Hyprland.focusedMonitor.name;
            }
        } catch (e) {}
        return (Quickshell.screens && Quickshell.screens.length > 0) ? Quickshell.screens[0].name : "";
    }

    // "" or an unknown name means the focused monitor.
    function resolveMonitor(monitor) {
        let m = String(monitor === undefined || monitor === null ? "" : monitor).trim();
        if (m !== "" && CanvasState.cameraFor(m)) return CM.safeName(m);
        return CM.safeName(hud.focusedMonitor());
    }

    function activeCamera(monitor) {
        let cam = CanvasState.cameraFor(hud.resolveMonitor(monitor));
        return (cam && cam.active) ? cam : null;
    }

    // ---- navigator ----------------------------------------------------------

    property string navigatorMonitor: ""

    function openNavigator(monitor) {
        let m = hud.resolveMonitor(monitor);
        if (!hud.activeCamera(m)) return false;
        hud.navigatorMonitor = m;
        return true;
    }

    function closeNavigator() {
        hud.navigatorMonitor = "";
    }

    Connections {
        target: CanvasState
        function onNavigatorRequested(monitor) { hud.openNavigator(monitor); }
    }

    // ---- IPC ----------------------------------------------------------------

    IpcHandler {
        target: "canvas"

        function home(monitor: string): string {
            let cam = hud.activeCamera(monitor);
            if (!cam) return "disabled";
            cam.home();
            return "ok";
        }

        function fit(monitor: string): string {
            let m = hud.resolveMonitor(monitor);
            if (!hud.activeCamera(m)) return "disabled";
            CanvasState.fitAll(m);
            return "ok";
        }

        // Moves the view by screen pixels: positive dx looks further right.
        function pan(monitor: string, dx: string, dy: string): string {
            let cam = hud.activeCamera(monitor);
            if (!cam) return "disabled";
            let x = parseFloat(dx);
            let y = parseFloat(dy);
            if (isNaN(x) || isNaN(y)) return "invalid";
            cam.panBy(-x, -y);
            return "ok";
        }

        // factor: "in", "out", "reset" or a multiplier such as 1.25.
        function zoom(monitor: string, factor: string): string {
            let cam = hud.activeCamera(monitor);
            if (!cam) return "disabled";
            let f = String(factor).trim().toLowerCase();
            if (f === "reset") {
                cam.resetZoom();
                return "ok";
            }
            let value = f === "in" ? cam.cfg.zoomStep : (f === "out" ? 1 / cam.cfg.zoomStep : parseFloat(f));
            if (isNaN(value) || value <= 0) return "invalid";
            cam.zoomBy(value);
            return "ok";
        }

        function center(monitor: string, x: string, y: string): string {
            let cam = hud.activeCamera(monitor);
            if (!cam) return "disabled";
            let wx = parseFloat(x);
            let wy = parseFloat(y);
            if (isNaN(wx) || isNaN(wy)) return "invalid";
            cam.centerOnWorld(wx, wy);
            return "ok";
        }

        function go(monitor: string, widgetId: string): string {
            let m = hud.resolveMonitor(monitor);
            if (!hud.activeCamera(m)) return "disabled";
            return CanvasState.goToWidget(m, String(widgetId).trim()) ? "ok" : "not_found";
        }

        function search(monitor: string): string {
            if (hud.navigatorMonitor !== "") {
                hud.closeNavigator();
                return "closed";
            }
            return hud.openNavigator(monitor) ? "ok" : "disabled";
        }

        function minimap(action: string): string {
            let a = String(action).trim().toLowerCase();
            if (a === "on") CanvasState.minimapPinned = true;
            else if (a === "off") CanvasState.minimapPinned = false;
            else CanvasState.minimapPinned = !CanvasState.minimapPinned;
            return CanvasState.minimapPinned ? "on" : "off";
        }

        function state(monitor: string): string {
            let m = hud.resolveMonitor(monitor);
            let cam = CanvasState.cameraFor(m);
            if (!cam) return "{}";
            return JSON.stringify({
                monitor: m,
                enabled: cam.active,
                x: Math.round(cam.viewX * 100) / 100,
                y: Math.round(cam.viewY * 100) / 100,
                zoom: Math.round(cam.viewZoom * 10000) / 10000,
                home: cam.atHome,
                widgets: CanvasState.widgetsFor(m).length
            });
        }
    }

    // ---- minimap ------------------------------------------------------------

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: mapWindow

            required property var modelData
            screen: modelData

            readonly property string mon: CM.safeName(modelData ? modelData.name : "")
            readonly property var cam: CanvasState.cameraFor(mon)
            readonly property var cfg: CanvasState.effective(mon)
            property bool redacting: false
            readonly property bool wanted: {
                if (!cam || !cam.active || redacting) return false;
                if (CanvasState.minimapPinned || cfg.minimap === "always") return true;
                if (cfg.minimap !== "auto") return false;
                return cam.recentlyMoved || cam.moving || mapHover.hovered;
            }

            Connections {
                target: WidgetSync
                function onRedactModeChanged(monitor, active) {
                    if (CM.safeName(monitor) === mapWindow.mon) mapWindow.redacting = active;
                }
            }

            visible: wanted
            color: "transparent"
            focusable: false

            WlrLayershell.namespace: "qs-canvas-minimap"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Normal

            readonly property bool atTop: cfg.minimapCorner.indexOf("top") === 0
            readonly property bool atLeft: cfg.minimapCorner.indexOf("left") > 0
            anchors.top: atTop
            anchors.bottom: !atTop
            anchors.left: atLeft
            anchors.right: !atLeft
            margins.top: hud.s(16)
            margins.bottom: hud.s(16)
            margins.left: hud.s(16)
            margins.right: hud.s(16)

            implicitWidth: hud.s(232)
            implicitHeight: hud.s(176)

            Item {
                id: mapRoot
                anchors.fill: parent
                property Item glassBackdropItem: mapBackdrop

                HoverHandler { id: mapHover }

                WallpaperBlur {
                    id: mapBackdrop
                    standalone: true
                    opacity: 0
                    anchors.fill: mapCard
                    radius: mapCard.radius
                }

                Rectangle {
                    id: mapCard
                    anchors.fill: parent
                    radius: ThemeBackend.borderRadius
                    color: mapGlass.active ? "transparent" : Qt.alpha(ThemeBackend.base, 0.9)
                    border.width: mapGlass.active ? 0 : 1
                    border.color: Qt.alpha(ThemeBackend.surface1, 0.8)

                    GlassFill {
                        id: mapGlass
                        anchors.fill: parent
                        radius: parent.radius
                        tintColor: ThemeBackend.base
                        tintAmount: 0.4
                    }

                    CanvasMinimap {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: mapBar.top
                        anchors.margins: hud.s(6)
                        widgets: CanvasState.widgetsFor(mapWindow.mon)
                        camX: mapWindow.cam ? mapWindow.cam.viewX : 0
                        camY: mapWindow.cam ? mapWindow.cam.viewY : 0
                        camZoom: mapWindow.cam ? mapWindow.cam.viewZoom : 1
                        screenW: mapWindow.cam ? mapWindow.cam.screenW : 1920
                        screenH: mapWindow.cam ? mapWindow.cam.screenH : 1080
                        onNavigate: (worldX, worldY) => {
                            let c = mapWindow.cam;
                            if (c) c.jumpTo(CM.centerOn(worldX, worldY, c.screenW, c.screenH, c.rawZoom));
                        }
                    }

                    RowLayout {
                        id: mapBar
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: hud.s(6)
                        spacing: hud.s(4)

                        IconButton {
                            size: hud.s(26)
                            cornerRadius: ThemeBackend.borderRadius
                            buttonIcon: hud.icon(0xF02DC)
                            iconFontSize: hud.s(13)
                            accentColor: (mapWindow.cam && mapWindow.cam.atHome) ? ThemeBackend.surface0 : ThemeBackend.mauve
                            textColor: (mapWindow.cam && mapWindow.cam.atHome) ? ThemeBackend.text : ThemeBackend.crust
                            onClicked: if (mapWindow.cam) mapWindow.cam.home()
                        }

                        IconButton {
                            size: hud.s(26)
                            cornerRadius: ThemeBackend.borderRadius
                            buttonIcon: hud.icon(0xF0293)
                            iconFontSize: hud.s(13)
                            accentColor: ThemeBackend.surface0
                            textColor: ThemeBackend.text
                            onClicked: CanvasState.fitAll(mapWindow.mon)
                        }

                        IconButton {
                            size: hud.s(26)
                            cornerRadius: ThemeBackend.borderRadius
                            buttonIcon: hud.icon(0xF0349)
                            iconFontSize: hud.s(13)
                            accentColor: ThemeBackend.surface0
                            textColor: ThemeBackend.text
                            onClicked: hud.openNavigator(mapWindow.mon)
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: Math.round((mapWindow.cam ? mapWindow.cam.viewZoom : 1) * 100) + "%"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: hud.s(11)
                            font.bold: true
                            color: ThemeBackend.text
                            Layout.rightMargin: hud.s(4)

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -hud.s(6)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (mapWindow.cam) mapWindow.cam.resetZoom()
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- navigator window ---------------------------------------------------

    Loader {
        active: hud.navigatorMonitor !== ""

        sourceComponent: Component {
            PanelWindow {
                id: navWindow

                readonly property string mon: hud.navigatorMonitor
                readonly property var cam: CanvasState.cameraFor(mon)
                property string query: ""
                readonly property var results: CanvasState.search(mon, query).slice(0, 8)

                screen: {
                    let scr = Quickshell.screens.find(sc => CM.safeName(sc.name) === navWindow.mon);
                    return scr || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
                }

                color: "transparent"
                focusable: true

                WlrLayershell.namespace: "qs-canvas-navigator"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                exclusionMode: ExclusionMode.Ignore

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                function go(widgetId) {
                    CanvasState.goToWidget(navWindow.mon, widgetId);
                    hud.closeNavigator();
                }

                Shortcut {
                    sequence: "Escape"
                    onActivated: hud.closeNavigator()
                }

                Component.onCompleted: Qt.callLater(() => navInput.forceInputFocus())

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(ThemeBackend.crust.r, ThemeBackend.crust.g, ThemeBackend.crust.b, 0.35)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: hud.closeNavigator()
                    }
                }

                Item {
                    id: navRoot
                    width: hud.s(440)
                    height: navCard.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(hud.s(40), parent.height * 0.18)
                    property Item glassBackdropItem: navBackdrop

                    WallpaperBlur {
                        id: navBackdrop
                        standalone: true
                        opacity: 0
                        anchors.fill: navCard
                        radius: navCard.radius
                    }

                    Rectangle {
                        id: navCard
                        width: parent.width
                        height: navColumn.implicitHeight + hud.s(24)
                        radius: ThemeBackend.borderRadius
                        color: navGlass.active ? "transparent" : Qt.alpha(ThemeBackend.base, 0.96)
                        border.width: navGlass.active ? 0 : 1
                        border.color: Qt.alpha(ThemeBackend.surface1, 0.8)

                        GlassFill {
                            id: navGlass
                            anchors.fill: parent
                            radius: parent.radius
                            tintColor: ThemeBackend.base
                            tintAmount: 0.4
                        }

                        MouseArea { anchors.fill: parent }

                        ColumnLayout {
                            id: navColumn
                            x: hud.s(12)
                            y: hud.s(12)
                            width: parent.width - hud.s(24)
                            spacing: hud.s(8)

                            Input {
                                id: navInput
                                Layout.fillWidth: true
                                Layout.preferredHeight: hud.s(38)
                                unfocusOnOutsideClick: false
                                placeholderText: I18n.t("widgets.canvas.search_placeholder", "Find a widget...")
                                leadingIcon: hud.icon(0xF0349)
                                baseColor: ThemeBackend.surface0
                                accentColor: ThemeBackend.mauve
                                textColor: ThemeBackend.text
                                subTextColor: ThemeBackend.subtext0
                                borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
                                cornerRadius: ThemeBackend.borderRadius
                                fontPixelSize: hud.s(13)
                                onTextEdited: newText => navWindow.query = newText
                                onCleared: navWindow.query = ""
                                onAccepted: {
                                    if (navWindow.results.length > 0) navWindow.go(navWindow.results[0].wId);
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: hud.s(170)
                                radius: ThemeBackend.borderRadius
                                color: Qt.alpha(ThemeBackend.crust, 0.45)

                                CanvasMinimap {
                                    anchors.fill: parent
                                    anchors.margins: hud.s(6)
                                    widgets: CanvasState.widgetsFor(navWindow.mon)
                                    camX: navWindow.cam ? navWindow.cam.viewX : 0
                                    camY: navWindow.cam ? navWindow.cam.viewY : 0
                                    camZoom: navWindow.cam ? navWindow.cam.viewZoom : 1
                                    screenW: navWindow.cam ? navWindow.cam.screenW : 1920
                                    screenH: navWindow.cam ? navWindow.cam.screenH : 1080
                                    selectedIds: navWindow.query.trim() === "" ? [] : navWindow.results.map(r => r.wId)
                                    onNavigate: (worldX, worldY) => {
                                        let c = navWindow.cam;
                                        if (c) c.jumpTo(CM.centerOn(worldX, worldY, c.screenW, c.screenH, c.rawZoom));
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: hud.s(3)

                                Repeater {
                                    model: navWindow.results
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: hud.s(32)
                                        radius: ThemeBackend.borderRadius
                                        color: navResultMa.containsMouse
                                            ? ThemeBackend.surface1
                                            : ((index === 0 && navWindow.query.trim() !== "") ? Qt.alpha(ThemeBackend.mauve, 0.22) : Qt.alpha(ThemeBackend.surface0, 0.7))

                                        Text {
                                            anchors.left: parent.left
                                            anchors.right: navResultPos.left
                                            anchors.leftMargin: hud.s(10)
                                            anchors.rightMargin: hud.s(8)
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.label
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: hud.s(12)
                                            color: ThemeBackend.text
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            id: navResultPos
                                            anchors.right: parent.right
                                            anchors.rightMargin: hud.s(10)
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Math.round(modelData.box.x) + ", " + Math.round(modelData.box.y)
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: hud.s(10)
                                            color: ThemeBackend.subtext0
                                        }

                                        MouseArea {
                                            id: navResultMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: navWindow.go(modelData.wId)
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: navWindow.results.length === 0
                                    text: CanvasState.widgetsFor(navWindow.mon).length === 0
                                        ? I18n.t("widgets.redactor.no_widgets_active", "No widgets active")
                                        : I18n.t("widgets.redactor.no_results", "Nothing found")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: hud.s(12)
                                    color: ThemeBackend.subtext0
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: hud.s(6)

                                ClickButton {
                                    implicitHeight: hud.s(30)
                                    horizontalPadding: hud.s(10)
                                    cornerRadius: ThemeBackend.borderRadius
                                    buttonText: I18n.t("widgets.canvas.home", "Home")
                                    buttonIcon: hud.icon(0xF02DC)
                                    iconFontSize: hud.s(13)
                                    textFontSize: hud.s(11)
                                    accentColor: ThemeBackend.surface0
                                    textColor: ThemeBackend.text
                                    onClicked: {
                                        if (navWindow.cam) navWindow.cam.home();
                                        hud.closeNavigator();
                                    }
                                }

                                ClickButton {
                                    implicitHeight: hud.s(30)
                                    horizontalPadding: hud.s(10)
                                    cornerRadius: ThemeBackend.borderRadius
                                    buttonText: I18n.t("widgets.canvas.fit_all", "Show all")
                                    buttonIcon: hud.icon(0xF0293)
                                    iconFontSize: hud.s(13)
                                    textFontSize: hud.s(11)
                                    accentColor: ThemeBackend.surface0
                                    textColor: ThemeBackend.text
                                    onClicked: {
                                        CanvasState.fitAll(navWindow.mon);
                                        hud.closeNavigator();
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: I18n.t("widgets.canvas.navigator_hint", "Enter: go  ·  Esc: close")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: hud.s(10)
                                    color: ThemeBackend.subtext0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
