import QtQuick
import Quickshell
import "../../../reusables"
import "../../../"
import "../common"

// Terminal for the Restrained and Lush looks (TerminalRestrained.qml,
// TerminalLush.qml). Wires the same TerminalCore with the same settings as
// TerminalFace; TerminalFace itself is left as it is (its appear animation
// overshoots), so the new looks only fade (Restrained) or fade and settle with
// OutQuint (Lush). No process runs in previews: TerminalCore.live needs isLive.
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

    // ---- look (set by the variant files) ----
    property string look: "restrained"       // restrained | lush
    readonly property bool lush: look === "lush"

    // ---- settings (wProps), same names as TerminalFace ----
    property string mode: "interactive"      // interactive | fastfetch | cmatrix | cava | monitor
    property string shell: "auto"
    property string command: ""
    property real monitorInterval: 5
    property string fontFamily: "monospace"
    property real fontSize: 12
    property string colorScheme: "theme"     // theme | classic | matrix | cyber | amber
    property real backgroundOpacity: -1
    property real cornerRadius: -1
    property string appearAnimation: "fade"  // accepted for compatibility; these looks always fade
    property bool paused: false

    readonly property bool isLive: !!(parent && parent.liveDesktopWidget === true)
    readonly property bool wantsKeyboardFocus: isLive && core.engaged && !paused
    readonly property bool focused: core.activeFocus
    readonly property FaceTone tone: FaceTone {}

    readonly property real bgOpacity: backgroundOpacity >= 0 ? Math.min(1, backgroundOpacity)
        : (lush ? Math.max(0.6, Math.min(0.88, ThemeBackend.elementOpacity * 0.9)) : 0.86)
    readonly property real radius: cornerRadius >= 0 ? Scaler.s(cornerRadius)
        : (lush ? Math.max(Scaler.s(14), Math.min(Scaler.s(22), ThemeBackend.clampedBorderRadius * 1.5))
                : Math.min(Scaler.s(3), ThemeBackend.clampedBorderRadius))

    // ---- colours (same schemes as TerminalFace) -------------------------------------
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
            fg: root.hex(ThemeBackend.text), bg: root.hex(ThemeBackend.base), cursor: root.hex(root.lush ? ThemeBackend.mauve : ThemeBackend.text),
            palette: [ThemeBackend.surface1, ThemeBackend.red, ThemeBackend.green, ThemeBackend.yellow,
                      ThemeBackend.blue, ThemeBackend.pink, ThemeBackend.teal, ThemeBackend.subtext1,
                      ThemeBackend.surface2, ThemeBackend.red, ThemeBackend.green, ThemeBackend.yellow,
                      ThemeBackend.blue, ThemeBackend.pink, ThemeBackend.teal, ThemeBackend.text].map(c => root.hex(c)) };
        }
    }

    readonly property string headerTitle: {
        if (core.title !== "" && mode === "interactive") return core.title;
        switch (mode) {
        case "fastfetch": return "fastfetch";
        case "cmatrix": return "cmatrix";
        case "cava": return "cava";
        case "monitor": return (command.trim() || I18n.t("widgets.terminal.monitor", "Command monitor")) + "  ·  " + monitorInterval + "s";
        }
        return I18n.t("widgets.terminal.name", "Terminal");
    }

    // ---- background ----------------------------------------------------------------
    Loader {
        anchors.fill: parent
        z: -1
        sourceComponent: root.lush ? lushBg : minimalBg
    }
    Component {
        id: minimalBg
        Rectangle {
            radius: root.radius
            color: Qt.alpha(root.scheme.bg, root.bgOpacity)
            border.width: 1
            border.color: root.focused ? root.tone.hairlineStrong : root.tone.hairline
            Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
    }
    Component {
        id: lushBg
        LushCard {
            radius: root.radius
            bodyOpacity: root.bgOpacity
            intensity: root.focused ? 0.85 : 0.5
            ornate: Math.min(root.width, root.height) >= Scaler.s(160)
        }
    }

    // ---- header --------------------------------------------------------------------
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Scaler.s(root.lush ? 14 : 8)
        anchors.rightMargin: Scaler.s(root.lush ? 12 : 8)
        anchors.topMargin: Scaler.s(root.lush ? 6 : 0)
        height: Scaler.s(root.lush ? 24 : 20)

        // lush: a small gradient seal before the title
        Rectangle {
            id: seal
            visible: root.lush
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? Scaler.s(7) : 0
            height: width
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: root.tone.accent }
                GradientStop { position: 1.0; color: root.tone.accent2 }
            }
            opacity: root.focused ? 1 : 0.6
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        }

        Text {
            anchors.left: seal.right
            anchors.leftMargin: root.lush ? Scaler.s(8) : 0
            anchors.right: restartBtn.left
            anchors.rightMargin: Scaler.s(6)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.lush ? root.headerTitle : root.headerTitle.toUpperCase()
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(root.lush ? 11 : 9)
            font.italic: root.lush
            font.letterSpacing: root.lush ? 0 : Scaler.s(1.5)
            color: root.focused ? root.tone.ink : root.tone.muted
        }

        Text {
            id: restartBtn
            visible: root.isLive
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "↻"
            font.pixelSize: Scaler.s(12)
            color: restartArea.containsMouse ? root.tone.ink : root.tone.faint
            MouseArea { id: restartArea; anchors.fill: parent; anchors.margins: -Scaler.s(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: core.start() }
        }

        // rule under the header: 1 px hairline, or a gradient fading to the right
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: root.lush ? "transparent" : root.tone.hairline
            gradient: root.lush ? ruleGradient : null
            Gradient {
                id: ruleGradient
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.alpha(root.tone.accent, 0.6) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
    }

    TerminalCore {
        id: core
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.lush ? Scaler.s(6) : 0
        anchors.rightMargin: root.lush ? Scaler.s(6) : 0
        anchors.bottomMargin: root.lush ? Scaler.s(6) : 0
        clip: true
        padding: Scaler.s(root.lush ? 8 : 6)
        live: root.isLive && !root.paused
        mode: root.mode
        shell: root.shell
        command: root.command
        monitorInterval: root.monitorInterval
        fontFamily: root.fontFamily !== "" ? root.fontFamily : "monospace"
        fontSize: Math.max(6, Scaler.s(root.fontSize))
        theme: ({ fg: root.scheme.fg, bg: root.scheme.bg, palette: root.scheme.palette, boldBright: true })
        cursorColor: root.scheme.cursor
        selectionColor: Qt.alpha(ThemeBackend.mauve, 0.35)
    }

    // ---- messages (same texts and actions as TerminalFace) ------------------------
    Rectangle {
        id: messageBox
        readonly property string kind: root.paused && root.isLive ? "paused" : core.status
        visible: ["untrusted", "missing", "nocommand", "error", "paused"].indexOf(kind) !== -1
        anchors.centerIn: core
        width: Math.min(core.width - Scaler.s(16), Scaler.s(420))
        height: msgCol.implicitHeight + Scaler.s(20)
        radius: root.lush ? Scaler.s(12) : Scaler.s(2)
        color: Qt.alpha(ThemeBackend.base, 0.94)
        border.width: 1
        border.color: kind === "error" ? ThemeBackend.red : (kind === "untrusted" ? ThemeBackend.peach : root.tone.hairline)

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

            Flow {
                width: parent.width
                spacing: Scaler.s(6)
                visible: root.isLive && messageBox.kind !== "paused" && messageBox.kind !== "nocommand"
                FaceButton {
                    visible: messageBox.kind === "untrusted"
                    lush: root.lush
                    text: I18n.t("widgets.terminal.runOnce", "Run once"); iconFont: ThemeBackend.fontFamily; fontSize: Scaler.s(10)
                    onClicked: core.runOnce()
                }
                FaceButton {
                    visible: messageBox.kind === "untrusted"
                    lush: root.lush; primary: true; accent: ThemeBackend.peach
                    text: I18n.t("widgets.terminal.trust", "Always allow"); iconFont: ThemeBackend.fontFamily; fontSize: Scaler.s(10)
                    onClicked: core.trustAndRun()
                }
                FaceButton {
                    visible: messageBox.kind === "untrusted" && root.mode === "interactive"
                    lush: root.lush
                    text: I18n.t("widgets.terminal.skip", "Shell only"); iconFont: ThemeBackend.fontFamily; fontSize: Scaler.s(10)
                    onClicked: core.skipCommand()
                }
                FaceButton {
                    visible: messageBox.kind === "missing" || messageBox.kind === "error"
                    lush: root.lush
                    text: I18n.t("widgets.terminal.retry", "Retry"); iconFont: ThemeBackend.fontFamily; fontSize: Scaler.s(10)
                    onClicked: core.start()
                }
            }
        }
    }

    // process finished (fastfetch, a shell that exited, ...)
    Rectangle {
        visible: core.status === "exited" && root.isLive
        anchors.left: core.left
        anchors.right: core.right
        anchors.bottom: core.bottom
        anchors.margins: Scaler.s(6)
        height: Scaler.s(22)
        radius: root.lush ? height / 2 : Scaler.s(2)
        color: Qt.alpha(ThemeBackend.base, 0.88)
        border.width: 1
        border.color: root.tone.hairline
        Text {
            anchors.centerIn: parent
            font.family: ThemeBackend.fontFamily
            font.pixelSize: Scaler.s(10)
            color: root.tone.muted
            text: I18n.t("widgets.terminal.exited", "Finished") + " (" + core.exitCode + ") · "
                + I18n.t("widgets.terminal.restartHint", "Enter or click to run again")
        }
        MouseArea { anchors.fill: parent; onClicked: core.start() }
    }
}
