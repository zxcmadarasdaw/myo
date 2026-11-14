import QtQuick
import Quickshell
import "../../../reusables"
import "../../../"

// Desktop Terminal: a real terminal (PTY + emulator, see TerminalCore.qml)
// inside a desktop widget. Variants differ only in how the card looks.
//
// Keyboard: the widget asks for keyboard focus only after it is clicked and
// gives it back as soon as its window loses focus, so it never steals typing
// from other windows.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 200
    property real minHeight: 110
    property real maxWidth: 3000
    property real maxHeight: 2000
    property real minAspect: 0
    property real maxAspect: 9999
    property bool isRound: false

    // ---- variant (set by the variant files) ----
    property string terminalStyle: "glass"   // transparent | glass | cyber | minimal | card

    // ---- settings (wProps) ----
    property string mode: "interactive"      // interactive | fastfetch | cmatrix | cava | monitor
    property string shell: "auto"
    property string command: ""              // interactive: run at start; monitor: the command
    property real monitorInterval: 5
    property string fontFamily: "monospace"
    property real fontSize: 12
    property string colorScheme: "theme"     // theme | classic | matrix | cyber | amber
    property real backgroundOpacity: -1      // -1: the variant's default
    property real cornerRadius: -1           // -1: the theme's radius
    property string appearAnimation: "fade"  // fade | slide | scale | none
    property bool paused: false

    readonly property bool isLive: !!(parent && parent.liveDesktopWidget === true)
    readonly property bool hasFetchMedia: fetchLoader.item?.ready === true
    readonly property var fetchStyle: FastfetchMedia.style
    readonly property bool wantsKeyboardFocus: isLive && core.engaged && !paused

    readonly property bool cyber: terminalStyle === "cyber"
    readonly property color neonA: "#00f0ff"
    readonly property color neonB: "#ff2bd6"
    readonly property bool hasHeader: terminalStyle === "card" || terminalStyle === "cyber" || terminalStyle === "glass"

    readonly property real defaultOpacity: terminalStyle === "transparent" ? 0
        : terminalStyle === "minimal" ? 0.85
        : terminalStyle === "card" ? 0.95
        : terminalStyle === "cyber" ? 0.88
        : Math.max(0.35, ThemeBackend.elementOpacity * 0.8)
    readonly property real bgOpacity: backgroundOpacity >= 0 ? Math.min(1, backgroundOpacity) : defaultOpacity
    readonly property real radius: cornerRadius >= 0 ? Scaler.s(cornerRadius) : (cyber ? Scaler.s(6) : ThemeBackend.clampedBorderRadius)

    // ---- colours -------------------------------------------------------------------
    function hex(c) {
        function h(v) { let s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s; }
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    readonly property var scheme: {
        switch (root.colorScheme) {
        case "classic": return {
            fg: "#e5e5e5", bg: "#000000", cursor: "#e5e5e5",
            palette: ["#000000", "#cd0000", "#00cd00", "#cdcd00", "#0000ee", "#cd00cd", "#00cdcd", "#e5e5e5",
                      "#7f7f7f", "#ff0000", "#00ff00", "#ffff00", "#5c5cff", "#ff00ff", "#00ffff", "#ffffff"] };
        case "matrix": return {
            fg: "#33ff66", bg: "#020a04", cursor: "#66ff99",
            palette: ["#020a04", "#1f9e3a", "#33ff66", "#7dff9b", "#167a2c", "#2bd456", "#5cffa0", "#a6ffbf",
                      "#0d3a17", "#2bd456", "#66ff99", "#b3ffc6", "#1fbf48", "#40ff7a", "#8cffb3", "#e0ffe9"] };
        case "cyber": return {
            fg: "#d6faff", bg: "#05060f", cursor: "#00f0ff",
            palette: ["#0b0d1f", "#ff2b6d", "#00ffa3", "#ffe600", "#00a2ff", "#ff2bd6", "#00f0ff", "#c8d3f5",
                      "#3b3f66", "#ff5c8d", "#5cffc4", "#fff27a", "#5cc4ff", "#ff6be6", "#7af7ff", "#ffffff"] };
        case "amber": return {
            fg: "#ffb000", bg: "#120a00", cursor: "#ffcc4d",
            palette: ["#120a00", "#ff6a00", "#ffb000", "#ffd27a", "#cc8a00", "#ff9a3d", "#ffc94d", "#ffe0a3",
                      "#4d3300", "#ff8c33", "#ffc233", "#ffe3a3", "#e6a01a", "#ffb366", "#ffd480", "#fff3d6"] };
        default: return {
            fg: root.hex(ThemeBackend.text), bg: root.hex(ThemeBackend.base), cursor: root.hex(ThemeBackend.text),
            palette: [ThemeBackend.surface1, ThemeBackend.red, ThemeBackend.green, ThemeBackend.yellow,
                      ThemeBackend.blue, ThemeBackend.pink, ThemeBackend.teal, ThemeBackend.subtext1,
                      ThemeBackend.surface2, ThemeBackend.red, ThemeBackend.green, ThemeBackend.yellow,
                      ThemeBackend.blue, ThemeBackend.pink, ThemeBackend.teal, ThemeBackend.text].map(c => root.hex(c)) };
        }
    }

    readonly property color schemeBg: scheme.bg

    // ---- appear ----------------------------------------------------------------------
    opacity: isLive && appearAnimation !== "none" ? 0 : 1
    Component.onCompleted: if (isLive && appearAnimation !== "none") appear.start()
    property real slideOffset: isLive && appearAnimation === "slide" ? Scaler.s(24) : 0
    transform: Translate { y: root.slideOffset }
    scale: isLive && appearAnimation === "scale" ? 0.9 : 1
    ParallelAnimation {
        id: appear
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "slideOffset"; to: 0; duration: 460; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; to: 1; duration: 460; easing.type: Easing.OutBack }
    }

    // ---- card --------------------------------------------------------------------------
    Rectangle {
        id: glow
        visible: root.cyber
        anchors.fill: card
        anchors.margins: -Scaler.s(3)
        radius: card.radius + Scaler.s(3)
        color: "transparent"
        border.width: Scaler.s(2)
        border.color: Qt.alpha(root.neonB, root.core_focused ? 0.55 : 0.28)
        Behavior on border.color { ColorAnimation { duration: 200 } }
    }
    readonly property bool core_focused: core.activeFocus

    Rectangle {
        id: card
        anchors.fill: parent
        radius: root.hasFetchMedia ? Math.max(4, root.fetchStyle.radius) : root.radius
        clip: true
        color: root.hasFetchMedia ? Qt.alpha(root.fetchStyle.bg, root.fetchStyle.alpha)
            : root.terminalStyle === "glass"
            ? Qt.alpha(ThemeBackend.surface0, root.bgOpacity)
            : Qt.alpha(root.schemeBg, root.bgOpacity)
        border.width: root.hasFetchMedia ? (root.fetchStyle.border > 0 ? 1 : 0) : root.terminalStyle === "transparent" ? 0 : 1
        border.color: root.hasFetchMedia ? Qt.alpha(root.fetchStyle.accent, root.fetchStyle.border)
            : root.cyber ? Qt.alpha(root.neonA, root.core_focused ? 0.9 : 0.55)
            : root.terminalStyle === "glass" ? Qt.rgba(1, 1, 1, root.core_focused ? 0.3 : 0.16)
            : Qt.alpha(ThemeBackend.text, root.core_focused ? 0.18 : 0.08)
        Behavior on border.color { ColorAnimation { duration: 200 } }

        WallpaperBlur {
            z: -1
            anchors.fill: parent
            radius: parent.radius
            visible: root.hasFetchMedia ? root.fetchStyle.material === "glass" && GpuCompatibility.blurAllowed
                                         : root.terminalStyle === "glass" && root.bgOpacity > 0
        }
        GlassFill {
            anchors.fill: parent
            radius: card.radius
            tintColor: root.fetchStyle.bg
            allowed: root.hasFetchMedia && root.fetchStyle.material === "liquid" && GpuCompatibility.shadersAllowed
        }

        // Cyber: scanlines
        Canvas {
            anchors.fill: parent
            visible: root.cyber && !root.hasFetchMedia
            opacity: 0.06
            onPaint: {
                let ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.fillStyle = "#00f0ff";
                for (let y = 0; y < height; y += 3) ctx.fillRect(0, y, width, 1);
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        // header
        Item {
            id: header
            visible: root.hasHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.hasHeader ? Scaler.s(root.terminalStyle === "glass" ? 22 : 26) : 0

            Rectangle {
                anchors.fill: parent
                visible: root.terminalStyle === "card"
                color: Qt.alpha(ThemeBackend.mantle, 0.6)
            }

            Row {
                visible: root.terminalStyle === "card"
                anchors.left: parent.left
                anchors.leftMargin: Scaler.s(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Scaler.s(6)
                Repeater {
                    model: [ThemeBackend.red, ThemeBackend.yellow, ThemeBackend.green]
                    Rectangle { required property var modelData; width: Scaler.s(10); height: width; radius: width / 2; color: modelData }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: headerButtons.left
                anchors.leftMargin: root.terminalStyle === "card" ? Scaler.s(60) : Scaler.s(10)
                anchors.rightMargin: Scaler.s(6)
                horizontalAlignment: root.terminalStyle === "card" ? Text.AlignHCenter : Text.AlignLeft
                elide: Text.ElideRight
                text: root.cyber ? "▌ " + root.headerTitle.toUpperCase() : root.headerTitle
                font.family: root.cyber ? root.fontFamily : ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(10)
                font.bold: root.cyber
                font.letterSpacing: root.cyber ? 1.5 : 0
                color: root.hasFetchMedia ? root.fetchStyle.accent : root.cyber ? root.neonA : ThemeBackend.subtext0
            }

            Row {
                id: headerButtons
                anchors.right: parent.right
                anchors.rightMargin: Scaler.s(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Scaler.s(4)
                visible: root.isLive
                Text {
                    text: "↻"
                    font.pixelSize: Scaler.s(12)
                    color: restartArea.containsMouse ? (root.cyber ? root.neonA : ThemeBackend.text) : ThemeBackend.subtext0
                    MouseArea { id: restartArea; anchors.fill: parent; anchors.margins: -Scaler.s(4); hoverEnabled: true; onClicked: core.start() }
                }
            }
        }

        Loader {
            id: fetchLoader
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom }
            anchors.margins: root.fetchStyle.gap / 2
            active: (root.mode === "fastfetch" || root.mode === "fetchShell") && root.isLive && !root.paused
                    && FastfetchMedia.enabled && FastfetchMedia.kind !== ""
            sourceComponent: FastfetchMediaPane { active: true; obscured: Wallpaper.sessionLocked }
        }

        TerminalCore {
            id: core
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: root.hasFetchMedia ? fetchLoader.item.leadingSpace + fetchLoader.anchors.leftMargin : 0
            anchors.topMargin: root.hasFetchMedia ? fetchLoader.item.topSpace + fetchLoader.anchors.topMargin : 0
            padding: Scaler.s(root.terminalStyle === "minimal" || root.terminalStyle === "transparent" ? 6 : 8)
            live: root.isLive && !root.paused
            mode: root.mode
            fetchLayout: root.hasFetchMedia ? FastfetchMedia.layout : ""
            shell: root.shell
            command: root.command
            monitorInterval: root.monitorInterval
            fontFamily: root.hasFetchMedia ? root.fetchStyle.font : (root.fontFamily || "monospace")
            fontSize: Math.max(6, Scaler.s(root.fontSize))
            theme: root.hasFetchMedia ? ({ fg: root.fetchStyle.fg, bg: root.fetchStyle.bg,
                                          palette: root.scheme.palette, boldBright: true })
                                       : ({ fg: root.scheme.fg, bg: root.scheme.bg, palette: root.scheme.palette, boldBright: true })
            cursorColor: root.cyber ? root.neonA : root.scheme.cursor
            selectionColor: Qt.alpha(root.cyber ? root.neonB : ThemeBackend.mauve, 0.35)
        }

        // ---- messages ------------------------------------------------------------------
        Rectangle {
            id: messageBox
            readonly property string kind: root.paused && root.isLive ? "paused" : core.status
            visible: ["untrusted", "missing", "nocommand", "error", "paused"].indexOf(kind) !== -1
            anchors.centerIn: core
            width: Math.min(core.width - Scaler.s(16), Scaler.s(420))
            height: msgCol.implicitHeight + Scaler.s(20)
            radius: Math.max(Scaler.s(4), root.radius - Scaler.s(4))
            color: Qt.alpha(ThemeBackend.base, 0.92)
            border.width: 1
            border.color: kind === "error" ? ThemeBackend.red : (kind === "untrusted" ? ThemeBackend.peach : Qt.alpha(ThemeBackend.text, 0.12))

            Column {
                id: msgCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Scaler.s(10)
                spacing: Scaler.s(8)

                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: Scaler.s(11)
                    color: ThemeBackend.text
                    text: {
                        switch (messageBox.kind) {
                        case "paused": return I18n.t("widgets.terminal.paused", "Terminal is paused. Turn \"Paused\" off in the widget settings to start it.");
                        case "untrusted": return I18n.t("widgets.terminal.untrusted", "This widget wants to run a command that has not been approved on this computer:");
                        case "missing": return core.statusDetail + " " + I18n.t("widgets.terminal.missing", "is not installed. Install it with:");
                        case "nocommand": return I18n.t("widgets.terminal.noCommand", "Set the command to watch in the widget settings (Command).");
                        case "error": return core.statusDetail || I18n.t("widgets.terminal.error", "The terminal could not start.");
                        }
                        return "";
                    }
                }

                Text {
                    width: parent.width
                    visible: messageBox.kind === "untrusted" || messageBox.kind === "missing"
                    wrapMode: Text.WrapAnywhere
                    font.family: root.fontFamily
                    font.pixelSize: Scaler.s(11)
                    color: messageBox.kind === "missing" ? ThemeBackend.green : ThemeBackend.peach
                    text: messageBox.kind === "missing" ? "sudo dnf install " + core.statusDetail : core.pendingCommand
                }

                Row {
                    spacing: Scaler.s(6)
                    visible: root.isLive && messageBox.kind !== "paused" && messageBox.kind !== "nocommand"
                    ClickButton {
                        height: Scaler.s(28)
                        visible: messageBox.kind === "untrusted"
                        buttonText: I18n.t("widgets.terminal.runOnce", "Run once")
                        textFontSize: Scaler.s(10)
                        cornerRadius: ThemeBackend.borderRadius
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        onClicked: core.runOnce()
                    }
                    ClickButton {
                        height: Scaler.s(28)
                        visible: messageBox.kind === "untrusted"
                        buttonText: I18n.t("widgets.terminal.trust", "Always allow")
                        textFontSize: Scaler.s(10)
                        cornerRadius: ThemeBackend.borderRadius
                        accentColor: ThemeBackend.peach
                        textColor: ThemeBackend.crust
                        onClicked: core.trustAndRun()
                    }
                    ClickButton {
                        height: Scaler.s(28)
                        visible: messageBox.kind === "untrusted" && root.mode === "interactive"
                        buttonText: I18n.t("widgets.terminal.skip", "Shell only")
                        textFontSize: Scaler.s(10)
                        cornerRadius: ThemeBackend.borderRadius
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        onClicked: core.skipCommand()
                    }
                    ClickButton {
                        height: Scaler.s(28)
                        visible: messageBox.kind === "missing" || messageBox.kind === "error"
                        buttonText: I18n.t("widgets.terminal.retry", "Retry")
                        textFontSize: Scaler.s(10)
                        cornerRadius: ThemeBackend.borderRadius
                        accentColor: ThemeBackend.surface1
                        textColor: ThemeBackend.text
                        onClicked: core.start()
                    }
                }
            }
        }

        // process finished (fastfetch, a shell that exited, ...)
        Rectangle {
            visible: core.status === "exited" && root.isLive && !root.hasFetchMedia
            anchors.left: core.left
            anchors.right: core.right
            anchors.bottom: core.bottom
            anchors.margins: Scaler.s(6)
            height: Scaler.s(22)
            radius: height / 2
            color: Qt.alpha(ThemeBackend.base, 0.85)
            Text {
                anchors.centerIn: parent
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(10)
                color: ThemeBackend.subtext0
                text: I18n.t("widgets.terminal.exited", "Finished") + " (" + core.exitCode + ") · "
                    + I18n.t("widgets.terminal.restartHint", "Enter or click to run again")
            }
            MouseArea { anchors.fill: parent; onClicked: core.start() }
        }
    }

    readonly property string headerTitle: {
        if (core.title !== "" && mode === "interactive") return core.title;
        switch (mode) {
        case "fastfetch": return "fastfetch";
        case "fetchShell": return core.title !== "" ? core.title : "fastfetch";
        case "cmatrix": return "cmatrix";
        case "cava": return "cava";
        case "monitor": return (command.trim() || I18n.t("widgets.terminal.monitor", "Command monitor")) + "  ·  " + monitorInterval + "s";
        }
        return I18n.t("widgets.terminal.name", "Terminal");
    }
}
