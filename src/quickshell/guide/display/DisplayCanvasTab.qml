import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../"
import "../../"
import "../../reusables"
import "../../reusables/guide"

// Settings -> Display -> Infinite canvas
GuideTab {
    id: canvasTab
    subTabIndex: 3

    function icon(code) { return String.fromCodePoint(code); }

    // Global value (what monitors without their own settings use).
    function g(key) {
        let s = CanvasState.settings;
        return (s && s[key] !== undefined) ? s[key] : CanvasState.defaults[key];
    }

    // Effective value of one monitor.
    function m(monitor, key) {
        return CanvasState.effective(monitor)[key];
    }

    function setNumber(key, value, monitor) {
        let current = monitor ? canvasTab.m(monitor, key) : canvasTab.g(key);
        if (isNaN(value) || Math.abs(value - current) < 0.0001) return;
        if (monitor) CanvasState.setMonitor(monitor, key, value);
        else CanvasState.setGlobal(key, value);
    }

    readonly property var screenNames: {
        let out = [];
        let list = Quickshell.screens;
        for (let i = 0; i < list.length; i++) out.push(list[i].name);
        return out;
    }
    // Monitor that receives a composition inserted from this page.
    property int insertMonitorIndex: 0
    readonly property string insertMonitor: screenNames.length > 0 ? screenNames[Math.min(insertMonitorIndex, screenNames.length - 1)] : ""

    readonly property var wheelValues: ["zoom", "pan", "none"]
    readonly property var wheelLabels: [
        I18n.t("guide.display.canvas.wheel.zoom", "Zoom"),
        I18n.t("guide.display.canvas.wheel.pan", "Move"),
        I18n.t("guide.display.canvas.wheel.none", "Nothing")
    ]
    readonly property var minimapValues: ["auto", "always", "never"]
    readonly property var minimapLabels: [
        I18n.t("guide.display.canvas.minimap.auto", "While moving"),
        I18n.t("guide.display.canvas.minimap.always", "Always"),
        I18n.t("guide.display.canvas.minimap.never", "Never")
    ]
    readonly property var cornerValues: ["bottom-right", "bottom-left", "top-right", "top-left"]
    readonly property var cornerLabels: [
        I18n.t("guide.display.canvas.corner.bottom_right", "Bottom right"),
        I18n.t("guide.display.canvas.corner.bottom_left", "Bottom left"),
        I18n.t("guide.display.canvas.corner.top_right", "Top right"),
        I18n.t("guide.display.canvas.corner.top_left", "Top left")
    ]

    component CanvasToggle: Toggle {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        accentColor: ThemeBackend.mauve
        baseColor: ThemeBackend.surface1
        handleColor: ThemeBackend.crust
        handleOffColor: ThemeBackend.text
    }

    component CanvasNumber: NumberSelector {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        implicitWidth: canvasTab.rootObj.s(130)
        implicitHeight: canvasTab.rootObj.s(32)
        baseColor: ThemeBackend.surface0
        accentColor: ThemeBackend.mauve
        buttonColor: ThemeBackend.surface1
        buttonTextColor: ThemeBackend.text
        textColor: ThemeBackend.text
        subTextColor: ThemeBackend.subtext0
        borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
        cornerRadius: ThemeBackend.borderRadius
        fontFamily: ThemeBackend.fontFamily
        fontPixelSize: canvasTab.rootObj.s(11)
    }

    component CanvasDropdown: Dropdown {
        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
        implicitWidth: canvasTab.rootObj.s(180)
        implicitHeight: canvasTab.rootObj.s(32)
        accentColor: ThemeBackend.mauve
        baseColor: ThemeBackend.surface0
        hoverColor: ThemeBackend.surface1
        dropdownColor: ThemeBackend.surface0
        borderColor: Qt.alpha(ThemeBackend.surface2, 0.6)
        textColor: ThemeBackend.text
        activeTextColor: ThemeBackend.crust
        fontPixelSize: canvasTab.rootObj.s(11)
        fuzzySearch: false
    }

    component SectionTitle: Text {
        Layout.fillWidth: true
        Layout.topMargin: canvasTab.rootObj.s(8)
        Layout.leftMargin: canvasTab.rootObj.s(4)
        font.family: ThemeBackend.fontFamily
        font.pixelSize: canvasTab.rootObj.s(12)
        font.bold: true
        color: ThemeBackend.subtext0
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(8)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(4)
        contentHeight: canvasCol.implicitHeight + rootObj.s(16)
        contentWidth: width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            active: parent.moving || parent.movingVertically
            width: rootObj.s(4)
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: rootObj.s(4)
                radius: rootObj.s(2)
                color: ThemeBackend.surface2
            }
        }

        ColumnLayout {
            id: canvasCol
            width: parent.width - (parent.contentHeight > parent.height ? rootObj.s(6) : 0)
            spacing: rootObj.s(6)

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_enabled"
                icon: canvasTab.icon(0xF034D)
                title: I18n.t("guide.display.canvas.enabled.title", "Infinite desktop canvas")
                description: I18n.t("guide.display.canvas.enabled.desc", "Widgets live on an endless surface you can move around and zoom. Turned off, the desktop stays fixed to the screen as before; widget positions are kept either way")
                searchKeywords: "canvas infinite desktop endless pan zoom camera widgets world"

                CanvasToggle {
                    checked: canvasTab.g("enabled")
                    onToggled: function(val) { CanvasState.setGlobal("enabled", val); }
                }
            }

            SectionTitle { text: I18n.t("guide.display.canvas.section.movement", "Movement") }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_drag_to_pan"
                icon: canvasTab.icon(0xF01BE)
                title: I18n.t("guide.display.canvas.drag.title", "Drag the desktop to move")
                description: I18n.t("guide.display.canvas.drag.desc", "Hold the left button on an empty spot of the desktop and drag. The middle button always works")
                searchKeywords: "canvas drag pan move desktop mouse left middle button"

                CanvasToggle {
                    checked: canvasTab.g("dragToPan")
                    onToggled: function(val) { CanvasState.setGlobal("dragToPan", val); }
                }
            }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_sensitivity"
                icon: canvasTab.icon(0xF04C5)
                title: I18n.t("guide.display.canvas.sensitivity.title", "Sensitivity")
                description: I18n.t("guide.display.canvas.sensitivity.desc", "How far the canvas moves for the same pointer movement")
                searchKeywords: "canvas sensitivity speed pan drag"

                CanvasNumber {
                    from: CanvasState.limits.sensitivity[0]
                    to: CanvasState.limits.sensitivity[1]
                    stepSize: 0.1
                    decimals: 1
                    suffix: "x"
                    value: canvasTab.g("sensitivity")
                    onValueChanged: canvasTab.setNumber("sensitivity", Math.round(value * 10) / 10, "")
                }
            }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_inertia"
                icon: canvasTab.icon(0xF04E0)
                title: I18n.t("guide.display.canvas.inertia.title", "Inertia")
                description: I18n.t("guide.display.canvas.inertia.desc", "Keep gliding for a moment after the canvas is released")
                searchKeywords: "canvas inertia momentum glide smooth fling"

                CanvasToggle {
                    checked: canvasTab.g("inertia")
                    onToggled: function(val) { CanvasState.setGlobal("inertia", val); }
                }
            }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_friction"
                icon: canvasTab.icon(0xF04E0)
                visible: canvasTab.g("inertia")
                title: I18n.t("guide.display.canvas.friction.title", "Braking")
                description: I18n.t("guide.display.canvas.friction.desc", "Higher values stop the glide sooner")
                searchKeywords: "canvas inertia friction damping braking stop"

                CanvasNumber {
                    from: CanvasState.limits.friction[0]
                    to: CanvasState.limits.friction[1]
                    stepSize: 1
                    decimals: 0
                    value: canvasTab.g("friction")
                    onValueChanged: canvasTab.setNumber("friction", Math.round(value), "")
                }
            }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_wheel"
                icon: canvasTab.icon(0xF037D)
                title: I18n.t("guide.display.canvas.wheel.title", "Mouse wheel on the desktop")
                description: I18n.t("guide.display.canvas.wheel.desc", "Ctrl+wheel always zooms, Shift+wheel moves sideways")
                searchKeywords: "canvas wheel scroll zoom pan touchpad"

                CanvasDropdown {
                    options: canvasTab.wheelLabels
                    currentIndex: Math.max(0, canvasTab.wheelValues.indexOf(canvasTab.g("wheelAction")))
                    onValueChanged: function(index, value) {
                        if (index >= 0 && index < canvasTab.wheelValues.length && canvasTab.wheelValues[index] !== canvasTab.g("wheelAction")) {
                            CanvasState.setGlobal("wheelAction", canvasTab.wheelValues[index]);
                        }
                    }
                }
            }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_zoom_step"
                icon: canvasTab.icon(0xF0349)
                title: I18n.t("guide.display.canvas.zoom_step.title", "Zoom step")
                description: I18n.t("guide.display.canvas.zoom_step.desc", "How much one wheel notch or zoom key changes the scale")
                searchKeywords: "canvas zoom step scale wheel"

                CanvasNumber {
                    from: CanvasState.limits.zoomStep[0]
                    to: CanvasState.limits.zoomStep[1]
                    stepSize: 0.02
                    decimals: 2
                    suffix: "x"
                    value: canvasTab.g("zoomStep")
                    onValueChanged: canvasTab.setNumber("zoomStep", Math.round(value * 100) / 100, "")
                }
            }

            SectionTitle { text: I18n.t("guide.display.canvas.section.layout", "Grid and guides") }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_grid_size"
                icon: canvasTab.icon(0xF02C1)
                title: I18n.t("guide.display.canvas.grid_size.title", "Grid size")
                description: I18n.t("guide.display.canvas.grid_size.desc", "Cell size of the redactor grid, in pixels")
                searchKeywords: "canvas grid size cell step snap redactor"

                CanvasNumber {
                    from: CanvasState.limits.gridSize[0]
                    to: CanvasState.limits.gridSize[1]
                    stepSize: 2
                    decimals: 0
                    suffix: "px"
                    value: canvasTab.g("gridSize")
                    onValueChanged: canvasTab.setNumber("gridSize", Math.round(value), "")
                }
            }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_snap_grid"
                icon: canvasTab.icon(0xF02C1)
                title: I18n.t("guide.display.canvas.snap_grid.title", "Snap to grid")
                description: I18n.t("guide.display.canvas.snap_grid.desc", "Open the redactor with the grid turned on")
                searchKeywords: "canvas snap grid redactor align"

                CanvasToggle {
                    checked: canvasTab.g("snapToGrid")
                    onToggled: function(val) { CanvasState.setGlobal("snapToGrid", val); }
                }
            }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_snap_guides"
                icon: canvasTab.icon(0xF0486)
                title: I18n.t("guide.display.canvas.snap_guides.title", "Snap to guides")
                description: I18n.t("guide.display.canvas.snap_guides.desc", "Align widgets to each other and to the edges of the view while dragging. Hold Ctrl to skip it once")
                searchKeywords: "canvas snap guides align edges widgets redactor"

                CanvasToggle {
                    checked: canvasTab.g("snapToGuides")
                    onToggled: function(val) { CanvasState.setGlobal("snapToGuides", val); }
                }
            }

            SectionTitle { text: I18n.t("guide.display.canvas.section.minimap", "Minimap") }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_minimap"
                icon: canvasTab.icon(0xF034D)
                title: I18n.t("guide.display.canvas.minimap.title", "Show the minimap")
                description: I18n.t("guide.display.canvas.minimap.desc", "A small map of all widgets on the desktop; click it to jump")
                searchKeywords: "canvas minimap map overview navigate widgets"

                CanvasDropdown {
                    options: canvasTab.minimapLabels
                    currentIndex: Math.max(0, canvasTab.minimapValues.indexOf(canvasTab.g("minimap")))
                    onValueChanged: function(index, value) {
                        if (index >= 0 && index < canvasTab.minimapValues.length && canvasTab.minimapValues[index] !== canvasTab.g("minimap")) {
                            CanvasState.setGlobal("minimap", canvasTab.minimapValues[index]);
                        }
                    }
                }
            }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_minimap_corner"
                icon: canvasTab.icon(0xF034D)
                visible: canvasTab.g("minimap") !== "never"
                title: I18n.t("guide.display.canvas.corner.title", "Minimap corner")
                description: I18n.t("guide.display.canvas.corner.desc", "Where the minimap sits on the screen")
                searchKeywords: "canvas minimap corner position"

                CanvasDropdown {
                    options: canvasTab.cornerLabels
                    currentIndex: Math.max(0, canvasTab.cornerValues.indexOf(canvasTab.g("minimapCorner")))
                    onValueChanged: function(index, value) {
                        if (index >= 0 && index < canvasTab.cornerValues.length && canvasTab.cornerValues[index] !== canvasTab.g("minimapCorner")) {
                            CanvasState.setGlobal("minimapCorner", canvasTab.cornerValues[index]);
                        }
                    }
                }
            }

            SectionTitle { text: I18n.t("guide.display.canvas.section.monitors", "Monitors") }

            Repeater {
                model: Quickshell.screens

                delegate: Rectangle {
                    id: monCard
                    required property var modelData
                    readonly property string monName: modelData ? modelData.name : ""
                    readonly property string monKey: monName.toLowerCase().replace(/[^a-z0-9_]/g, "_")
                    readonly property var cam: CanvasState.cameraFor(monName)
                    readonly property bool own: CanvasState.hasOverride(monName)

                    Layout.fillWidth: true
                    implicitHeight: monCol.implicitHeight + canvasTab.rootObj.s(8)
                    radius: ThemeBackend.borderRadius
                    color: monGlass.active ? "transparent" : Qt.alpha(ThemeBackend.surface0, 0.4)
                    clip: true

                    GlassFill {
                        id: monGlass
                        anchors.fill: parent
                        radius: parent.radius
                        tintColor: Qt.alpha(ThemeBackend.surface0, 0.4)
                        tintAmount: 0.25
                    }

                    ColumnLayout {
                        id: monCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 0

                        SettingsRow {
                            rootObj: canvasTab.rootObj
                            settingId: "canvas_monitor_" + monCard.monKey
                            icon: canvasTab.icon(0xF0379)
                            title: monCard.monName
                            description: {
                                if (!monCard.cam || !monCard.cam.active) return I18n.t("guide.display.canvas.monitor.off", "Canvas is off on this monitor");
                                if (monCard.cam.atHome) return I18n.t("guide.display.canvas.monitor.home", "At the home position");
                                return Math.round(monCard.cam.viewX) + ", " + Math.round(monCard.cam.viewY) + "  ·  " + Math.round(monCard.cam.viewZoom * 100) + "%";
                            }
                            searchKeywords: "canvas monitor screen home camera " + monCard.monName.toLowerCase()
                            baseColor: "transparent"
                            hoverColor: "transparent"
                            borderWidth: 0

                            ClickButton {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                implicitHeight: canvasTab.rootObj.s(32)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonText: I18n.t("widgets.canvas.fit_all", "Show all")
                                buttonIcon: canvasTab.icon(0xF0293)
                                iconFontSize: canvasTab.rootObj.s(14)
                                textFontSize: canvasTab.rootObj.s(12)
                                accentColor: ThemeBackend.surface0
                                textColor: ThemeBackend.text
                                enabled: monCard.cam !== null && monCard.cam.active
                                opacity: enabled ? 1.0 : 0.4
                                onClicked: CanvasState.fitAll(monCard.monName)
                            }

                            ClickButton {
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                                implicitHeight: canvasTab.rootObj.s(32)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonText: I18n.t("widgets.canvas.home", "Home")
                                buttonIcon: canvasTab.icon(0xF02DC)
                                iconFontSize: canvasTab.rootObj.s(14)
                                textFontSize: canvasTab.rootObj.s(12)
                                accentColor: ThemeBackend.mauve
                                textColor: ThemeBackend.crust
                                enabled: monCard.cam !== null && monCard.cam.active && !monCard.cam.atHome
                                opacity: enabled ? 1.0 : 0.4
                                onClicked: monCard.cam.home()
                            }
                        }

                        SettingsRow {
                            rootObj: canvasTab.rootObj
                            settingId: "canvas_monitor_own_" + monCard.monKey
                            icon: canvasTab.icon(0xF0493)
                            title: I18n.t("guide.display.canvas.monitor.own.title", "Own settings for this monitor")
                            description: I18n.t("guide.display.canvas.monitor.own.desc", "Use different canvas settings here than on the other monitors")
                            searchKeywords: "canvas monitor own separate override settings " + monCard.monName.toLowerCase()
                            baseColor: "transparent"
                            hoverColor: "transparent"
                            borderWidth: 0

                            CanvasToggle {
                                checked: monCard.own
                                onToggled: function(val) { CanvasState.setOverride(monCard.monName, val); }
                            }
                        }

                        SettingsRow {
                            rootObj: canvasTab.rootObj
                            visible: monCard.own
                            searchable: false
                            icon: canvasTab.icon(0xF034D)
                            title: I18n.t("guide.display.canvas.monitor.enabled", "Canvas on this monitor")
                            baseColor: "transparent"
                            hoverColor: "transparent"
                            borderWidth: 0

                            CanvasToggle {
                                checked: canvasTab.m(monCard.monName, "enabled")
                                onToggled: function(val) { CanvasState.setMonitor(monCard.monName, "enabled", val); }
                            }
                        }

                        SettingsRow {
                            rootObj: canvasTab.rootObj
                            visible: monCard.own
                            searchable: false
                            icon: canvasTab.icon(0xF04C5)
                            title: I18n.t("guide.display.canvas.sensitivity.title", "Sensitivity")
                            baseColor: "transparent"
                            hoverColor: "transparent"
                            borderWidth: 0

                            CanvasNumber {
                                from: CanvasState.limits.sensitivity[0]
                                to: CanvasState.limits.sensitivity[1]
                                stepSize: 0.1
                                decimals: 1
                                suffix: "x"
                                value: canvasTab.m(monCard.monName, "sensitivity")
                                onValueChanged: if (monCard.own) canvasTab.setNumber("sensitivity", Math.round(value * 10) / 10, monCard.monName)
                            }
                        }

                        SettingsRow {
                            rootObj: canvasTab.rootObj
                            visible: monCard.own
                            searchable: false
                            icon: canvasTab.icon(0xF02C1)
                            title: I18n.t("guide.display.canvas.grid_size.title", "Grid size")
                            baseColor: "transparent"
                            hoverColor: "transparent"
                            borderWidth: 0

                            CanvasNumber {
                                from: CanvasState.limits.gridSize[0]
                                to: CanvasState.limits.gridSize[1]
                                stepSize: 2
                                decimals: 0
                                suffix: "px"
                                value: canvasTab.m(monCard.monName, "gridSize")
                                onValueChanged: if (monCard.own) canvasTab.setNumber("gridSize", Math.round(value), monCard.monName)
                            }
                        }

                        SettingsRow {
                            rootObj: canvasTab.rootObj
                            visible: monCard.own
                            searchable: false
                            icon: canvasTab.icon(0xF037D)
                            title: I18n.t("guide.display.canvas.wheel.title", "Mouse wheel on the desktop")
                            baseColor: "transparent"
                            hoverColor: "transparent"
                            borderWidth: 0

                            CanvasDropdown {
                                options: canvasTab.wheelLabels
                                currentIndex: Math.max(0, canvasTab.wheelValues.indexOf(canvasTab.m(monCard.monName, "wheelAction")))
                                onValueChanged: function(index, value) {
                                    if (!monCard.own || index < 0 || index >= canvasTab.wheelValues.length) return;
                                    if (canvasTab.wheelValues[index] !== canvasTab.m(monCard.monName, "wheelAction")) {
                                        CanvasState.setMonitor(monCard.monName, "wheelAction", canvasTab.wheelValues[index]);
                                    }
                                }
                            }
                        }

                        SettingsRow {
                            rootObj: canvasTab.rootObj
                            visible: monCard.own
                            searchable: false
                            icon: canvasTab.icon(0xF034D)
                            title: I18n.t("guide.display.canvas.minimap.title", "Show the minimap")
                            baseColor: "transparent"
                            hoverColor: "transparent"
                            borderWidth: 0

                            CanvasDropdown {
                                options: canvasTab.minimapLabels
                                currentIndex: Math.max(0, canvasTab.minimapValues.indexOf(canvasTab.m(monCard.monName, "minimap")))
                                onValueChanged: function(index, value) {
                                    if (!monCard.own || index < 0 || index >= canvasTab.minimapValues.length) return;
                                    if (canvasTab.minimapValues[index] !== canvasTab.m(monCard.monName, "minimap")) {
                                        CanvasState.setMonitor(monCard.monName, "minimap", canvasTab.minimapValues[index]);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SectionTitle {
                visible: CanvasState.compositions.length > 0
                text: I18n.t("widgets.canvas.compositions", "Compositions")
            }

            SettingsRow {
                rootObj: canvasTab.rootObj
                visible: CanvasState.compositions.length > 0 && canvasTab.screenNames.length > 1
                searchable: false
                icon: canvasTab.icon(0xF0379)
                title: I18n.t("guide.display.canvas.composition.target.title", "Insert on monitor")
                description: I18n.t("guide.display.canvas.composition.target.desc", "Compositions added from this page appear in the middle of this monitor's current view")

                CanvasDropdown {
                    options: canvasTab.screenNames
                    currentIndex: Math.min(canvasTab.insertMonitorIndex, Math.max(0, canvasTab.screenNames.length - 1))
                    onValueChanged: function(index, value) {
                        if (index >= 0) canvasTab.insertMonitorIndex = index;
                    }
                }
            }

            Repeater {
                model: CanvasState.compositions

                delegate: SettingsRow {
                    id: compRow
                    required property var modelData
                    rootObj: canvasTab.rootObj
                    searchable: false
                    icon: canvasTab.icon(0xF02C3)
                    title: compRow.modelData.name
                    description: I18n.t("guide.display.canvas.composition.desc", {
                        count: compRow.modelData.widgets.length,
                        w: Math.round(compRow.modelData.w),
                        h: Math.round(compRow.modelData.h)
                    })

                    ClickButton {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        implicitHeight: canvasTab.rootObj.s(32)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonText: I18n.t("guide.display.canvas.composition.insert", "Insert")
                        buttonIcon: canvasTab.icon(0xF0415)
                        iconFontSize: canvasTab.rootObj.s(14)
                        textFontSize: canvasTab.rootObj.s(12)
                        accentColor: ThemeBackend.mauve
                        textColor: ThemeBackend.crust
                        enabled: canvasTab.insertMonitor !== ""
                        onClicked: CanvasState.insertComposition(canvasTab.insertMonitor, compRow.modelData.id)
                    }

                    DeleteButton {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        size: canvasTab.rootObj.s(32)
                        cornerRadius: ThemeBackend.borderRadius
                        iconFontSize: canvasTab.rootObj.s(16)
                        visible: !CanvasState.compositionsReadOnly
                        onClicked: CanvasState.removeComposition(compRow.modelData.id)
                    }
                }
            }

            SettingsRow {
                rootObj: canvasTab.rootObj
                settingId: "canvas_reset"
                icon: canvasTab.icon(0xF0450)
                title: I18n.t("guide.display.canvas.reset.title", "Restore canvas defaults")
                description: I18n.t("guide.display.canvas.reset.desc", "Resets these settings for all monitors. Widgets, their positions and saved compositions are not touched")
                searchKeywords: "canvas reset defaults restore"

                ClickButton {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    implicitHeight: canvasTab.rootObj.s(32)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonText: I18n.t("guide.display.canvas.reset.button", "Reset")
                    textFontSize: canvasTab.rootObj.s(12)
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: CanvasState.resetSettings()
                }
            }
        }
    }
}
