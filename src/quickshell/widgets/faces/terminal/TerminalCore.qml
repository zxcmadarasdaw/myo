import QtQuick
import Quickshell
import Quickshell.Io
import "../../../"
import "TerminalEmulator.js" as Vt

// The terminal itself: a PTY (scripts/system/serp_pty.py) feeding the
// emulator in TerminalEmulator.js, drawn as a character grid.
//
// Only a live desktop widget starts a process. Previews (widget picker,
// presets, settings) show a static sample instead. Anything that fails here
// (no python3, program missing, PTY error) becomes a message inside the
// widget; the shell is never affected.
Item {
    id: core

    // ---- configuration (set by TerminalFace) -------------------------------------
    property bool live: false
    property bool viewOnly: false
    property string mode: "interactive"       // interactive | fastfetch | cmatrix | cava | monitor
    property string fetchLayout: ""
    readonly property string fetchVariant: fetchLayout === "" ? "" : fetchLayout === "minimal" ? "minimal" : "full"
    property string shell: "auto"             // auto | bash | zsh
    property string command: ""               // interactive: start command; monitor: the command
    property real monitorInterval: 5           // seconds
    property string fontFamily: "monospace"
    property int fontSize: 12
    property var theme: ({ fg: "#cdd6f4", bg: "#1e1e2e", palette: [], boldBright: true })
    property color cursorColor: "#f5e0dc"
    property color selectionColor: Qt.rgba(0.5, 0.6, 1, 0.35)
    property int scrollbackLines: 3000
    property int padding: 0

    // ---- state ---------------------------------------------------------------------
    property bool engaged: false              // the user clicked in: keyboard wanted
    readonly property bool running: pty.running
    property string status: "idle"            // idle | running | exited | missing | untrusted | error | preview | nocommand
    property string statusDetail: ""
    property string title: ""
    property int exitCode: 0
    property int viewOffset: 0                // lines scrolled back from the live bottom
    property bool sessionTrusted: false       // "Run once" for an unapproved command

    readonly property bool needsCommand: mode === "monitor"
    readonly property string pendingCommand: mode === "monitor" || mode === "interactive" ? command.trim() : ""
    readonly property bool commandAllowed: pendingCommand === "" || sessionTrusted || TerminalTrust.isTrusted(pendingCommand)

    signal bell()

    TextMetrics { id: cellMetrics; font.family: core.fontFamily; font.pixelSize: core.fontSize; text: "MMMMMMMMMM" }
    FontMetrics { id: fontMetrics; font.family: core.fontFamily; font.pixelSize: core.fontSize }
    readonly property real cellW: Math.max(1, cellMetrics.advanceWidth / 10)
    readonly property real cellH: Math.max(1, Math.ceil(fontMetrics.height))
    readonly property int cols: Math.max(10, Math.floor((width - 2 * padding) / cellW))
    readonly property int rows: Math.max(3, Math.floor((height - 2 * padding) / cellH))

    property var term: null
    property int renderTick: 0
    property bool dirty: true
    property var rowData: []

    function makeTerm() {
        let t = new Vt.Terminal(core.cols, core.rows, { scrollback: core.scrollbackLines });
        t.onResponse = function(s) { core.send({ t: "in", d: s }); };
        t.onTitle = function(s) { core.title = s; };
        t.onBell = function() { core.bell(); };
        return t;
    }

    // ---- process ---------------------------------------------------------------------
    function buildCommand() {
        let script = Caching.serpantinumDir + "/scripts/system/serp_pty.py";
        let argv = ["python3", script, "--cols", String(core.cols), "--rows", String(core.rows)];
        if (core.mode === "fastfetch" || core.mode === "fetchShell") {
            const layouts = {
                full: "OS:Kernel:Uptime:CPU:GPU:Memory:Disk:Shell:WM:Terminal",
                minimal: "OS:CPU:GPU:Memory"
            };
            const modules = layouts[core.fetchVariant];
            const command = modules ? "TERM_PROGRAM=Serpantinum fastfetch --config none --logo none --structure " + modules : "fastfetch";
            argv.push("--require", "fastfetch", "--cmd", command);
            // fetchShell: Fastfetch once, then the user's shell on the same PTY (a fixed,
            // built-in command, so no approval is involved; nothing repeats on a timer).
            if (core.mode === "fetchShell")
                argv.push("--then-shell", "--shell", ["bash", "zsh"].indexOf(core.shell) !== -1 ? core.shell : "auto");
        }
        else if (core.mode === "cmatrix") argv.push("--require", "cmatrix", "--cmd", "cmatrix");
        else if (core.mode === "cava") argv.push("--require", "cava", "--cmd", "cava");
        else if (core.mode === "monitor") argv.push("--cmd", core.command.trim(), "--repeat", String(Math.max(1, core.monitorInterval)));
        else argv.push("--shell", ["bash", "zsh"].indexOf(core.shell) !== -1 ? core.shell : "auto");
        return argv;
    }

    property bool startQueued: false

    function start() {
        if (pty.running) {
            // the old process must exit before a new one starts
            core.startQueued = true;
            stop();
            return;
        }
        core.term = makeTerm();
        core.viewOffset = 0;
        core.clearSelection();
        core.title = "";
        if (!core.live) { showPreview(); return; }
        if (core.needsCommand && core.command.trim() === "") { core.status = "nocommand"; markDirty(); return; }
        // Commands are never run unless the user approved them on this machine
        // (typed them in the widget settings, or pressed Run here). Imported
        // themes and presets cannot pre-approve anything.
        if (!core.commandAllowed) { core.status = "untrusted"; markDirty(); return; }
        core.status = "running";
        core.statusDetail = "";
        core.startCommandPending = core.mode === "interactive" && core.pendingCommand !== "";
        pty.command = buildCommand();
        pty.running = true;
        markDirty();
    }

    function stop() {
        if (!pty.running) return;
        if (core.status === "running") core.status = "idle";
        pty.running = false;
    }

    function restart() { restartTimer.restart(); }

    function runOnce() { core.sessionTrusted = true; start(); }
    function trustAndRun() { TerminalTrust.approve(core.pendingCommand); start(); }
    function skipCommand() {
        // interactive mode: open the shell without the start command
        if (pty.running) return;
        core.sessionTrusted = false;
        core.status = "running";
        core.term = makeTerm();
        core.startCommandPending = false;
        pty.command = buildCommand();
        pty.running = true;
        markDirty();
    }

    property bool startCommandPending: false

    function send(obj) {
        if (pty.running) pty.write(JSON.stringify(obj) + "\n");
    }

    function sendText(s) {
        if (!s || core.status !== "running") return;
        core.viewOffset = 0;
        send({ t: "in", d: s });
    }

    Process {
        id: pty
        running: false
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => core.handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => console.warn("Terminal widget:", data)
        }
        onExited: (code, exitStatus) => {
            if (core.startQueued) {
                core.startQueued = false;
                Qt.callLater(core.start);
                return;
            }
            if (core.status === "running") {
                core.status = "error";
                core.statusDetail = code === 127 || code === -1
                    ? I18n.t("widgets.terminal.noPython", "python3 is required for the terminal widget.")
                    : I18n.t("widgets.terminal.backendStopped", "The terminal stopped unexpectedly") + " (" + code + ")";
                core.markDirty();
            }
        }
    }

    function handleLine(data) {
        let msg;
        try { msg = JSON.parse(data); } catch (e) { return; }
        if (!msg || !core.term) return;
        switch (msg.t) {
        case "out": {
            let before = core.term.pushed;
            core.term.write(msg.d);
            // keep a scrolled-back view still while output arrives
            if (core.viewOffset > 0) core.viewOffset = Math.min(core.term.scrollbackLength(), core.viewOffset + (core.term.pushed - before));
            markDirty();
            break;
        }
        case "started":
            if (core.startCommandPending) {
                core.startCommandPending = false;
                send({ t: "in", d: core.command.trim() + "\r" });
            }
            break;
        case "exit":
            core.status = "exited";
            core.exitCode = msg.code || 0;
            if (core.mode === "fastfetch" && core.fetchVariant !== "")
                core.viewOffset = core.term.scrollbackLength();
            markDirty();
            break;
        case "missing":
            core.status = "missing";
            core.statusDetail = String(msg.prog || "");
            markDirty();
            break;
        case "error":
            core.status = "error";
            core.statusDetail = String(msg.msg || "");
            markDirty();
            break;
        }
    }

    // ---- lifecycle -------------------------------------------------------------------
    readonly property bool wantRunning: live && visible && width > 0 && height > 0
    onWantRunningChanged: wantRunning ? restart() : stop()
    onModeChanged: restart()
    onFetchVariantChanged: if (mode === "fastfetch" || mode === "fetchShell") restart()
    onShellChanged: if (mode === "interactive" || mode === "fetchShell") restart()
    onCommandChanged: { core.sessionTrusted = false; if (mode === "monitor" || mode === "interactive") restart(); }
    onMonitorIntervalChanged: if (mode === "monitor") restart()
    onLiveChanged: restart()

    Timer {
        id: restartTimer
        interval: 250
        onTriggered: {
            if (core.wantRunning || !core.live) core.start();
        }
    }

    Component.onCompleted: {
        core.term = makeTerm();
        if (!core.live) showPreview();
        else if (core.wantRunning) restart();
    }
    Component.onDestruction: stop()

    onColsChanged: resizeTimer.restart()
    onRowsChanged: resizeTimer.restart()
    Timer {
        id: resizeTimer
        interval: 60
        onTriggered: {
            if (!core.term) return;
            core.term.resize(core.cols, core.rows);
            core.send({ t: "resize", c: core.cols, r: core.rows });
            if (!core.live) core.showPreview();
            core.markDirty();
        }
    }

    // ---- preview ---------------------------------------------------------------------
    function showPreview() {
        core.status = "preview";
        let t = core.term || makeTerm();
        core.term = t;
        t.reset();
        let prompt = "\x1b[1;32muser@serpantinum\x1b[0m:\x1b[1;34m~\x1b[0m$ ";
        if (core.mode === "cmatrix") {
            let chars = "0123456789ABCDEFXZ$#%&";
            let s = "";
            for (let r = 0; r < core.rows; r++) {
                s += "\x1b[" + (r + 1) + ";1H";
                for (let c = 0; c < core.cols; c++)
                    s += ((r * 7 + c * 13) % 5 === 0) ? "\x1b[" + ((r + c) % 3 === 0 ? "1;32" : "32") + "m" + chars[(r * 3 + c) % chars.length] : " ";
            }
            t.write(s + "\x1b[0m");
        } else if (core.mode === "cava") {
            let s = "";
            for (let r = 0; r < core.rows; r++) {
                s += "\x1b[" + (r + 1) + ";1H";
                for (let c = 0; c < core.cols; c++) {
                    let h = Math.round((Math.sin(c * 0.45) * 0.5 + 0.5) * core.rows * 0.8);
                    s += core.rows - r <= h ? "\x1b[3" + (r < core.rows / 3 ? 5 : 6) + "m\u2588" : " ";
                }
            }
            t.write(s + "\x1b[0m");
        } else if (core.mode === "fastfetch" || core.mode === "fetchShell") {
            t.write("\x1b[1;34m   .--.   \x1b[0m \x1b[1;34muser\x1b[0m@\x1b[1;34mserpantinum\x1b[0m\r\n"
                + "\x1b[1;34m  |o_o |  \x1b[0m -----------------\r\n"
                + "\x1b[1;34m  |:_/ |  \x1b[0m \x1b[1;34mOS\x1b[0m: Fedora Linux\r\n"
                + "\x1b[1;34m //   \\ \\ \x1b[0m \x1b[1;34mWM\x1b[0m: Hyprland\r\n"
                + "\x1b[1;34m(|     | )\x1b[0m \x1b[1;34mShell\x1b[0m: Serpantinum\r\n"
                + "\x1b[1;34m/'\\_   _/`\\\x1b[0m\x1b[1;34mTerminal\x1b[0m: desktop widget\r\n"
                + "           \x1b[40m   \x1b[41m   \x1b[42m   \x1b[43m   \x1b[44m   \x1b[45m   \x1b[46m   \x1b[47m   \x1b[0m");
        } else if (core.mode === "monitor") {
            t.write("\x1b[2mevery " + core.monitorInterval + "s:\x1b[0m " + (core.command || "uptime") + "\r\n\r\n"
                + " 14:02:11 up 3 days,  2:14,  1 user,  load average: 0.42, 0.38, 0.31");
        } else {
            t.write(prompt + "ls\r\n\x1b[1;34mDocuments\x1b[0m  \x1b[1;34mDownloads\x1b[0m  \x1b[1;32mbuild.sh\x1b[0m  notes.md\r\n" + prompt);
        }
        markDirty();
    }

    // ---- rendering -------------------------------------------------------------------
    function markDirty() { core.dirty = true; if (!renderTimer.running) renderTimer.start(); }

    Timer {
        id: renderTimer
        interval: 16
        onTriggered: core.refresh()
    }

    function refresh() {
        if (!core.term) return;
        core.dirty = false;
        let t = core.term;
        let first = Math.max(0, t.scrollbackLength() - core.viewOffset);
        let data = new Array(core.rows);
        for (let i = 0; i < core.rows; i++) {
            let r = Vt.renderRow(t.line(first + i), core.cols, core.theme);
            let key = "";
            for (let s of r.segs) key += s.col + "\u0001" + s.html + "\u0002";
            key += "|";
            for (let b of r.bgs) key += b.col + "," + b.len + "," + b.color + ";";
            r.key = key;
            data[i] = r;
        }
        core.rowData = data;
        core.renderTick++;
    }

    onThemeChanged: markDirty()
    onViewOffsetChanged: markDirty()

    // ---- selection -------------------------------------------------------------------
    // Positions are "global" lines (term.lineBase + absolute line) so they stay
    // put when old scrollback is dropped.
    property var selStart: null
    property var selEnd: null
    readonly property bool hasSelection: selStart !== null && selEnd !== null
        && (selStart.line !== selEnd.line || selStart.col !== selEnd.col)

    function clearSelection() { core.selStart = null; core.selEnd = null; }

    function posAt(x, y) {
        let t = core.term;
        let row = Math.max(0, Math.min(core.rows - 1, Math.floor((y - core.padding) / core.cellH)));
        let col = Math.max(0, Math.min(core.cols, Math.round((x - core.padding) / core.cellW)));
        let first = Math.max(0, t.scrollbackLength() - core.viewOffset);
        return { line: t.lineBase + first + row, col: col };
    }

    function ordered() {
        let a = core.selStart, b = core.selEnd;
        if (a.line > b.line || (a.line === b.line && a.col > b.col)) return [b, a];
        return [a, b];
    }

    function selectedText() {
        if (!core.hasSelection || !core.term) return "";
        let o = ordered();
        let base = core.term.lineBase;
        return core.term.textRange({ line: o[0].line - base, col: o[0].col }, { line: o[1].line - base, col: o[1].col });
    }

    function selectWord(x, y) {
        let p = posAt(x, y);
        let t = core.term;
        let row = t.line(p.line - t.lineBase);
        if (!row) return;
        let isWord = c => /[\w.\-\/~:@%+]/.test(c.ch);
        let c0 = Math.min(Math.floor((x - core.padding) / core.cellW), row.cells.length - 1);
        if (c0 < 0 || !isWord(row.cells[c0])) return;
        let a = c0, b = c0;
        while (a > 0 && isWord(row.cells[a - 1])) a--;
        while (b < row.cells.length - 1 && isWord(row.cells[b + 1])) b++;
        core.selStart = { line: p.line, col: a };
        core.selEnd = { line: p.line, col: b + 1 };
    }

    function copySelection() {
        let text = selectedText();
        if (text === "") return false;
        clipCopy.command = ["wl-copy", "--", text];
        clipCopy.running = true;
        return true;
    }

    function paste() {
        if (core.status !== "running") return;
        clipPaste.running = true;
    }

    Process { id: clipCopy; running: false }
    Process {
        id: clipPaste
        running: false
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text && core.term) core.sendText(Vt.pasteSequence(text, core.term.bracketedPaste));
            }
        }
    }

    // ---- keyboard ----------------------------------------------------------------------
    focus: !viewOnly
    Keys.onPressed: event => {
        if (core.viewOnly) return;
        let ctrlShift = (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier);
        if (ctrlShift && event.key === Qt.Key_C) { core.copySelection(); event.accepted = true; return; }
        if ((ctrlShift && event.key === Qt.Key_V) || ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Insert)) {
            core.paste(); event.accepted = true; return;
        }
        if ((event.modifiers & Qt.ShiftModifier) && (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown)) {
            core.scrollView(event.key === Qt.Key_PageUp ? core.rows - 1 : -(core.rows - 1));
            event.accepted = true; return;
        }
        if (core.status === "exited" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            core.start(); event.accepted = true; return;
        }
        if (core.status !== "running" || !core.term) return;
        let seq = Vt.keySequence(event.key, event.text, event.modifiers, core.term.appCursor);
        if (seq !== "") {
            core.clearSelection();
            core.sendText(seq);
            cursorBlink.restart();
            core.cursorOn = true;
            event.accepted = true;
        }
    }

    function scrollView(lines) {
        if (!core.term) return;
        core.viewOffset = Math.max(0, Math.min(core.term.scrollbackLength(), core.viewOffset + lines));
    }

    // ---- mouse ---------------------------------------------------------------------------
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: core.live && !core.viewOnly
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.IBeamCursor
        property bool dragging: false
        onPressed: m => {
            core.engaged = true;
            core.forceActiveFocus();
            if (m.button === Qt.MiddleButton) { core.paste(); return; }
            core.selStart = core.posAt(m.x, m.y);
            core.selEnd = core.selStart;
            dragging = true;
        }
        onPositionChanged: m => {
            if (!dragging) return;
            if (m.y < 0) core.scrollView(1);
            else if (m.y > height) core.scrollView(-1);
            core.selEnd = core.posAt(m.x, m.y);
        }
        onReleased: dragging = false
        onDoubleClicked: m => core.selectWord(m.x, m.y)
        onWheel: w => {
            let lines = Math.round(w.angleDelta.y / 40) || (w.angleDelta.y > 0 ? 1 : -1);
            if (core.term && core.term.altActive && core.status === "running") {
                // full-screen programs (less, vim) scroll with arrow keys
                let k = lines > 0 ? (core.term.appCursor ? "\x1bOA" : "\x1b[A") : (core.term.appCursor ? "\x1bOB" : "\x1b[B");
                core.sendText(k.repeat(Math.min(10, Math.abs(lines))));
            } else {
                core.scrollView(lines);
            }
        }
    }

    // Drop the keyboard as soon as the widget window loses focus.
    Connections {
        target: core.Window.window
        ignoreUnknownSignals: true
        function onActiveChanged() {
            if (core.Window.window && !core.Window.window.active) core.engaged = false;
        }
    }

    // ---- drawing ---------------------------------------------------------------------------
    Item {
        id: grid
        x: core.padding
        y: core.padding
        width: core.cols * core.cellW
        height: core.rows * core.cellH
        clip: true

        Repeater {
            model: core.rows
            delegate: Item {
                id: rowItem
                required property int index
                y: index * core.cellH
                width: grid.width
                height: core.cellH

                property string key: ""
                property var segs: []
                property var bgs: []
                function sync() {
                    let d = core.rowData[rowItem.index];
                    if (!d) { if (rowItem.key !== "") { rowItem.key = ""; rowItem.segs = []; rowItem.bgs = []; } return; }
                    if (d.key === rowItem.key) return;
                    rowItem.key = d.key;
                    rowItem.segs = d.segs;
                    rowItem.bgs = d.bgs;
                }
                Connections {
                    target: core
                    function onRenderTickChanged() { rowItem.sync(); }
                }
                Component.onCompleted: sync()

                Repeater {
                    model: rowItem.bgs
                    Rectangle {
                        required property var modelData
                        x: modelData.col * core.cellW
                        width: modelData.len * core.cellW
                        height: core.cellH
                        color: modelData.color
                    }
                }
                Repeater {
                    model: rowItem.segs
                    Text {
                        required property var modelData
                        x: modelData.col * core.cellW
                        height: core.cellH
                        verticalAlignment: Text.AlignVCenter
                        textFormat: Text.StyledText
                        text: modelData.html
                        color: core.theme.fg
                        font.family: core.fontFamily
                        font.pixelSize: core.fontSize
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        // selection
        Repeater {
            model: core.hasSelection ? core.rows : 0
            Rectangle {
                required property int index
                readonly property var span: {
                    core.renderTick;
                    if (!core.hasSelection || !core.term) return null;
                    let o = core.ordered();
                    let line = core.term.lineBase + Math.max(0, core.term.scrollbackLength() - core.viewOffset) + index;
                    if (line < o[0].line || line > o[1].line) return null;
                    let a = line === o[0].line ? o[0].col : 0;
                    let b = line === o[1].line ? o[1].col : core.cols;
                    return b > a ? { a: a, b: b } : null;
                }
                visible: span !== null
                x: span ? span.a * core.cellW : 0
                y: index * core.cellH
                width: span ? (span.b - span.a) * core.cellW : 0
                height: core.cellH
                color: core.selectionColor
            }
        }

        // cursor
        Rectangle {
            id: cursorRect
            readonly property var t: core.term
            readonly property int row: {
                core.renderTick;
                return t ? t.scrollbackLength() + t.y - Math.max(0, t.scrollbackLength() - core.viewOffset) : -1;
            }
            readonly property string shape: { core.renderTick; return t ? t.cursorShape : "block"; }
            visible: core.status === "running" && !!t && (core.renderTick, t.cursorVisible) && row >= 0 && row < core.rows
                     && (core.cursorOn || !core.activeFocus)
            x: (core.renderTick, t ? t.x : 0) * core.cellW
            y: row * core.cellH + (shape === "underline" ? core.cellH - height : 0)
            width: shape === "bar" ? Math.max(2, core.cellW / 6) : core.cellW
            height: shape === "underline" ? Math.max(2, core.cellH / 8) : core.cellH
            color: core.activeFocus ? core.cursorColor : "transparent"
            border.width: core.activeFocus ? 0 : 1
            border.color: core.cursorColor
            opacity: core.activeFocus && shape === "block" ? 0.75 : 1
        }
    }

    property bool cursorOn: true
    Timer {
        id: cursorBlink
        interval: 530
        repeat: true
        running: core.activeFocus && core.status === "running"
        onTriggered: core.cursorOn = !core.cursorOn
        onRunningChanged: core.cursorOn = true
    }

    // scrolled-back indicator
    Rectangle {
        visible: core.viewOffset > 0 && !core.viewOnly
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Scaler.s(6)
        radius: height / 2
        height: Scaler.s(20)
        width: scrollLabel.implicitWidth + Scaler.s(14)
        color: Qt.rgba(0, 0, 0, 0.55)
        Text {
            id: scrollLabel
            anchors.centerIn: parent
            text: "↑ " + core.viewOffset
            color: "white"
            font.pixelSize: Scaler.s(10)
            font.family: core.fontFamily
        }
        MouseArea { anchors.fill: parent; onClicked: core.viewOffset = 0 }
    }
}
