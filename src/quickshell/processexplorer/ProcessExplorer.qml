import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../"
import "../reusables"

// Process Explorer: a compact task manager opened with a hotkey.
//
// Data comes from scripts/system/serp_procs.py, which reads /proc and runs
// only while this window exists. The window exists only while the panel is
// open or closing (Shell.qml loads it lazily), so the keyboard is taken only
// then. Ending a process: own processes only, after a confirmation, via `kill`.
PanelWindow {
    id: win

    screen: ProcessExplorerController.screen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-process-explorer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: ProcessExplorerController.isVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region {
        width: win.open ? win.width : 0
        height: win.open ? win.height : 0
    }

    function s(v) { return Scaler.s(v); }

    readonly property bool open: ProcessExplorerController.isVisible
    readonly property string material: ProcessExplorerController.material
    readonly property bool neon: material === "neon"
    readonly property color neonA: "#00f0ff"
    readonly property color neonB: "#ff2bd6"
    readonly property color accent: neon ? neonA : ThemeBackend.mauve

    SpringProgress {
        id: reveal
        open: win.open
        openDuration: 520
        closeDuration: 180
        onActiveChanged: ProcessExplorerController.lingering = active && !win.open
    }
    onOpenChanged: {
        if (!open) ProcessExplorerController.lingering = reveal.active;
        else panel.forceActiveFocus();
    }

    // ---- data ----------------------------------------------------------------
    property var snapshot: null
    property var detail: null
    property string backendError: ""
    property string sortKey: "cpu"          // cpu | mem | name | pid
    property bool sortDesc: true
    property int selectedPid: -1
    readonly property string search: searchInput.text
    property string actionMessage: ""
    property var confirmTarget: null        // { pid, name }

    readonly property var rows: {
        let snap = win.snapshot;
        if (!snap || !snap.procs) return [];
        let q = win.search.trim().toLowerCase();
        let list = q === "" ? snap.procs.slice() : snap.procs.filter(p =>
            p.name.toLowerCase().indexOf(q) !== -1 || String(p.pid) === q || (p.cmd || "").toLowerCase().indexOf(q) !== -1);
        let k = win.sortKey;
        let dir = win.sortDesc ? -1 : 1;
        list.sort((a, b) => {
            let r;
            if (k === "name") r = a.name.localeCompare(b.name);
            else if (k === "pid") r = a.pid - b.pid;
            else if (k === "mem") r = a.mem - b.mem;
            else r = (a.cpu - b.cpu) || (a.mem - b.mem);
            return r * dir;
        });
        return list;
    }

    readonly property var heaviest: {
        let snap = win.snapshot;
        if (!snap || !snap.procs) return null;
        let best = null;
        for (let p of snap.procs) if (p.pid !== snap.self && (!best || p.cpu > best.cpu)) best = p;
        return best && best.cpu >= 1 ? best : null;
    }

    readonly property var selected: {
        if (!win.snapshot || win.selectedPid < 0) return null;
        for (let p of win.snapshot.procs) if (p.pid === win.selectedPid) return p;
        return null;
    }

    function canEnd(p) {
        return !!p && p.own === true && p.pid > 1 && !!win.snapshot && p.pid !== win.snapshot.self;
    }

    function formatBytes(b) {
        let v = Number(b) || 0;
        if (v < 1048576) return (v / 1024).toFixed(0) + " KB";
        if (v < 1073741824) return (v / 1048576).toFixed(v < 104857600 ? 1 : 0) + " MB";
        return (v / 1073741824).toFixed(2) + " GB";
    }

    function send(line) {
        if (backend.running) backend.write(line + "\n");
    }

    function selectPid(pid) {
        win.selectedPid = pid;
        win.detail = null;
        if (pid > 0) send("detail " + pid);
    }

    // icons from desktop entries, cached per process name
    property var iconCache: ({})
    function iconFor(name) {
        if (win.iconCache[name] !== undefined) return win.iconCache[name];
        let path = "";
        try {
            let ent = AppMatcher.entry(AppMatcher.resolve(name));
            if (ent && ent.icon) path = Quickshell.iconPath(ent.icon, true) || "";
        } catch (e) {}
        win.iconCache[name] = path;
        return path;
    }

    Process {
        id: backend
        running: true
        stdinEnabled: true
        command: ["python3", Caching.serpantinumDir + "/scripts/system/serp_procs.py", "--interval", String(ProcessExplorerController.interval)]
        stdout: SplitParser {
            onRead: data => {
                let obj;
                try { obj = JSON.parse(data); } catch (e) { return; }
                if (obj.detail) {
                    if (obj.detail.pid === win.selectedPid) win.detail = obj.detail;
                } else {
                    win.backendError = "";
                    win.snapshot = obj;
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                win.backendError = I18n.t("processexplorer.backendError", "Could not read processes (python3 is required).");
                console.warn("ProcessExplorer: serp_procs.py exited with code " + exitCode);
            }
        }
    }

    // `kill` for the user's own processes, after the confirmation below
    Process {
        id: killer
        property string label: ""
        running: false
        stderr: StdioCollector { id: killErr }
        onExited: (exitCode, exitStatus) => {
            win.actionMessage = exitCode === 0
                ? I18n.t("processexplorer.signalSent", "Signal sent to") + " " + killer.label
                : (I18n.t("processexplorer.signalFailed", "Could not end") + " " + killer.label + ": " + (killErr.text || "").trim());
            messageTimer.restart();
            win.send("refresh");
        }
    }
    Timer { id: messageTimer; interval: 4000; onTriggered: win.actionMessage = "" }

    function endProcess(pid, sig) {
        let p = null;
        for (let q of (win.snapshot ? win.snapshot.procs : [])) if (q.pid === pid) p = q;
        win.confirmTarget = null;
        if (!canEnd(p) || killer.running) return;
        killer.label = p.name + " (" + p.pid + ")";
        killer.command = ["kill", sig === "KILL" ? "-KILL" : "-TERM", String(p.pid)];
        killer.running = true;
    }

    function openLocation() {
        let exe = win.detail && win.detail.exe ? String(win.detail.exe) : "";
        if (exe === "" || exe[0] !== "/") return;
        let dir = exe.substring(0, exe.lastIndexOf("/")) || "/";
        Quickshell.execDetached(["xdg-open", dir]);
    }

    // ---- backdrop -------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.28 * reveal.value)
        MouseArea { anchors.fill: parent; onClicked: ProcessExplorerController.hide() }
    }

    // ---- panel ------------------------------------------------------------------
    Item {
        id: panel
        width: Math.min(win.width - s(48), s(900))
        height: Math.min(win.height - s(64), s(620))
        anchors.centerIn: parent
        opacity: Math.min(1, reveal.value * 1.4)
        scale: 0.92 + 0.08 * reveal.value
        transform: Translate { y: (1 - reveal.value) * s(24) }
        focus: true

        // Keys pressed in the search field bubble up here when it ignores them.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (win.confirmTarget) win.confirmTarget = null;
                else if (searchInput.text !== "") searchInput.text = "";
                else ProcessExplorerController.hide();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                let r = win.rows;
                if (r.length === 0) return;
                let i = r.findIndex(p => p.pid === win.selectedPid);
                i = event.key === Qt.Key_Down ? Math.min(r.length - 1, i + 1) : Math.max(0, i - 1);
                win.selectPid(r[i].pid);
                list.positionViewAtIndex(i, ListView.Contain);
                event.accepted = true;
            } else if (event.key === Qt.Key_Delete && win.canEnd(win.selected) && !searchInput.hasFocus) {
                win.confirmTarget = { pid: win.selected.pid, name: win.selected.name };
                event.accepted = true;
            } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
                win.send("refresh");
                event.accepted = true;
            } else if (!searchInput.hasFocus && event.text && event.text.length === 1 && event.text > " "
                       && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                // typing anywhere starts a search
                searchInput.text = searchInput.text + event.text;
                searchInput.forceInputFocus();
                event.accepted = true;
            }
        }

        MouseArea { anchors.fill: parent; onClicked: panel.forceActiveFocus() }   // never reaches the backdrop

        Rectangle {
            id: bg
            anchors.fill: parent
            radius: win.neon ? s(8) : ThemeBackend.clampedBorderRadius + s(4)
            clip: true
            color: win.material === "neon" ? Qt.rgba(0.02, 0.03, 0.06, 0.92)
                : win.material === "mica" ? Qt.alpha(ThemeBackend.base, 0.95)
                : win.material === "liquid" ? Qt.alpha(ThemeBackend.surface0, 0.16)
                : Qt.alpha(ThemeBackend.base, Math.max(0.75, ThemeBackend.elementOpacity))
            border.width: 1
            border.color: win.neon ? Qt.alpha(win.neonA, 0.7)
                : win.material === "liquid" ? Qt.rgba(1, 1, 1, 0.28)
                : Qt.alpha(ThemeBackend.text, 0.08)

            WallpaperBlur {
                z: -1
                anchors.fill: parent
                radius: parent.radius
                visible: win.material === "standard" || win.material === "liquid"
            }

            // Mica: an opaque base with a soft accent wash
            Rectangle {
                anchors.fill: parent
                visible: win.material === "mica"
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.alpha(ThemeBackend.mauve, 0.08) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            // Liquid: a light rim along the top edge
            Rectangle {
                visible: win.material === "liquid"
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: 1
                height: s(40)
                radius: parent.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.12) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }

        // Neon outer glow
        Rectangle {
            visible: win.neon
            anchors.fill: parent
            anchors.margins: -s(3)
            radius: bg.radius + s(3)
            color: "transparent"
            border.width: s(2)
            border.color: Qt.alpha(win.neonB, 0.35)
            z: -1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: s(18)
            spacing: s(12)

            // title
            RowLayout {
                Layout.fillWidth: true
                spacing: s(10)
                Text {
                    text: "󰍛"
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: s(22)
                    color: win.accent
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("processexplorer.title", "Process Explorer")
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: s(17)
                    font.bold: true
                    color: ThemeBackend.text
                }
                Text {
                    text: ProcessExplorerController.hotkey.replace(/ /g, "") + "  ·  Esc"
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: s(10)
                    color: ThemeBackend.subtext0
                }
                IconButton {
                    size: s(30)
                    buttonIcon: "󰅖"
                    iconFontSize: s(15)
                    cornerRadius: ThemeBackend.borderRadius
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: ProcessExplorerController.hide()
                }
            }

            // totals
            RowLayout {
                Layout.fillWidth: true
                spacing: s(10)

                Repeater {
                    model: {
                        let sn = win.snapshot;
                        return [
                            { icon: "󰍛", label: "CPU", value: sn ? sn.cpu.toFixed(0) + "%" : "…", frac: sn ? sn.cpu / 100 : 0,
                              sub: sn ? sn.cores + " " + I18n.t("processexplorer.cores", "cores") : "", color: ThemeBackend.mauve },
                            { icon: "󰘚", label: "RAM", value: sn ? sn.ram.percent.toFixed(0) + "%" : "…", frac: sn ? sn.ram.percent / 100 : 0,
                              sub: sn ? win.formatBytes(sn.ram.used) + " / " + win.formatBytes(sn.ram.total) : "", color: ThemeBackend.blue },
                            { icon: "󰢮", label: "GPU", value: sn && sn.gpu ? sn.gpu.percent + "%" : "—", frac: sn && sn.gpu ? sn.gpu.percent / 100 : 0,
                              sub: sn && sn.gpu ? sn.gpu.name : I18n.t("processexplorer.gpuUnavailable", "not reported by the driver"), color: ThemeBackend.green },
                            { icon: "󰐱", label: I18n.t("processexplorer.processes", "Processes"), value: sn ? String(sn.count) : "…", frac: -1,
                              sub: win.heaviest ? I18n.t("processexplorer.top", "busiest") + ": " + win.heaviest.name : "", color: ThemeBackend.peach }
                        ];
                    }

                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: s(70)
                        radius: ThemeBackend.borderRadius
                        color: win.neon ? Qt.rgba(1, 1, 1, 0.03) : Qt.alpha(ThemeBackend.surface0, 0.55)
                        border.width: win.neon ? 1 : 0
                        border.color: Qt.alpha(win.neonA, 0.35)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: s(10)
                            spacing: s(2)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: s(6)
                                Text { text: modelData.icon; font.family: ThemeBackend.iconFont; font.pixelSize: s(14); color: win.neon ? win.neonA : modelData.color }
                                Text { text: modelData.label; font.family: ThemeBackend.fontFamily; font.pixelSize: s(10); color: ThemeBackend.subtext0 }
                                Item { Layout.fillWidth: true }
                                Text { text: modelData.value; font.family: ThemeBackend.fontFamily; font.pixelSize: s(16); font.bold: true; color: ThemeBackend.text }
                            }
                            Rectangle {
                                visible: modelData.frac >= 0
                                Layout.fillWidth: true
                                Layout.preferredHeight: s(5)
                                radius: height / 2
                                color: Qt.alpha(ThemeBackend.text, 0.08)
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, modelData.frac))
                                    height: parent.height
                                    radius: parent.radius
                                    color: win.neon ? win.neonA : modelData.color
                                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.sub
                                elide: Text.ElideRight
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: s(9)
                                color: ThemeBackend.subtext0
                            }
                        }
                    }
                }
            }

            // search + sorting
            RowLayout {
                Layout.fillWidth: true
                spacing: s(8)

                Input {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: s(34)
                    placeholderText: I18n.t("processexplorer.search", "Search by name, command or PID")
                    leadingIcon: "󰍉"
                    fontPixelSize: s(12)
                    baseColor: ThemeBackend.surface0
                    accentColor: win.accent
                    cornerRadius: ThemeBackend.borderRadius
                    horizontalPadding: s(10)
                }

                Repeater {
                    model: [
                        { key: "cpu", label: "CPU" },
                        { key: "mem", label: I18n.t("processexplorer.memory", "Memory") },
                        { key: "name", label: I18n.t("processexplorer.name", "Name") },
                        { key: "pid", label: "PID" }
                    ]
                    ClickButton {
                        required property var modelData
                        Layout.preferredHeight: s(34)
                        height: s(34)
                        horizontalPadding: s(10)
                        cornerRadius: ThemeBackend.borderRadius
                        buttonText: modelData.label + (win.sortKey === modelData.key ? (win.sortDesc ? " ↓" : " ↑") : "")
                        textFontSize: s(11)
                        accentColor: win.sortKey === modelData.key ? win.accent : ThemeBackend.surface0
                        textColor: win.sortKey === modelData.key ? ThemeBackend.crust : ThemeBackend.text
                        onClicked: {
                            if (win.sortKey === modelData.key) win.sortDesc = !win.sortDesc;
                            else { win.sortKey = modelData.key; win.sortDesc = modelData.key === "cpu" || modelData.key === "mem"; }
                        }
                    }
                }

                IconButton {
                    size: s(34)
                    buttonIcon: "󰑐"
                    iconFontSize: s(15)
                    cornerRadius: ThemeBackend.borderRadius
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text
                    onClicked: win.send("refresh")
                }
            }

            // list + details
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: s(12)

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: ThemeBackend.borderRadius
                    color: Qt.alpha(ThemeBackend.crust, win.neon ? 0.35 : 0.18)
                    clip: true

                    RowLayout {
                        id: header
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.leftMargin: s(40); anchors.rightMargin: s(16)
                        height: s(28)
                        spacing: s(8)
                        Text { Layout.fillWidth: true; text: I18n.t("processexplorer.name", "Name"); font.pixelSize: s(10); font.bold: true; color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily }
                        Text { Layout.preferredWidth: s(64); text: "PID"; horizontalAlignment: Text.AlignRight; font.pixelSize: s(10); font.bold: true; color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily }
                        Text { Layout.preferredWidth: s(64); text: "CPU"; horizontalAlignment: Text.AlignRight; font.pixelSize: s(10); font.bold: true; color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily }
                        Text { Layout.preferredWidth: s(84); text: "RAM"; horizontalAlignment: Text.AlignRight; font.pixelSize: s(10); font.bold: true; color: ThemeBackend.subtext0; font.family: ThemeBackend.fontFamily }
                    }

                    ListView {
                        id: list
                        anchors.fill: parent
                        anchors.topMargin: header.height
                        clip: true
                        model: win.rows
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: rowItem
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: s(34)
                            readonly property bool isSel: modelData.pid === win.selectedPid
                            readonly property bool hot: modelData.cpu >= 20
                            color: isSel ? Qt.alpha(win.accent, 0.22)
                                : (rowArea.containsMouse ? Qt.alpha(ThemeBackend.text, 0.05) : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: s(10)
                                anchors.rightMargin: s(16)
                                spacing: s(8)

                                Item {
                                    Layout.preferredWidth: s(20)
                                    Layout.preferredHeight: s(20)
                                    Image {
                                        id: appIcon
                                        anchors.fill: parent
                                        source: win.iconFor(rowItem.modelData.name)
                                        sourceSize.width: s(40)
                                        sourceSize.height: s(40)
                                        visible: status === Image.Ready
                                        asynchronous: true
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !appIcon.visible
                                        text: rowItem.modelData.own ? "󰆍" : "󰒓"
                                        font.family: ThemeBackend.iconFont
                                        font.pixelSize: s(14)
                                        color: ThemeBackend.subtext0
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: rowItem.modelData.name + (rowItem.modelData.own ? "" : "  · " + rowItem.modelData.user)
                                    elide: Text.ElideRight
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: s(12)
                                    font.bold: rowItem.hot
                                    color: rowItem.modelData.own ? ThemeBackend.text : ThemeBackend.subtext1
                                }
                                Text { Layout.preferredWidth: s(64); horizontalAlignment: Text.AlignRight; text: rowItem.modelData.pid; font.family: ThemeBackend.fontFamily; font.pixelSize: s(11); color: ThemeBackend.subtext0 }
                                Text {
                                    Layout.preferredWidth: s(64)
                                    horizontalAlignment: Text.AlignRight
                                    text: rowItem.modelData.cpu.toFixed(1) + "%"
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: s(11)
                                    font.bold: rowItem.hot
                                    color: rowItem.modelData.cpu >= 50 ? ThemeBackend.red : (rowItem.hot ? ThemeBackend.peach : ThemeBackend.text)
                                }
                                Text { Layout.preferredWidth: s(84); horizontalAlignment: Text.AlignRight; text: win.formatBytes(rowItem.modelData.mem); font.family: ThemeBackend.fontFamily; font.pixelSize: s(11); color: ThemeBackend.text }
                            }

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { win.selectPid(rowItem.modelData.pid); panel.forceActiveFocus(); }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - s(40)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            visible: win.rows.length === 0
                            text: win.backendError !== "" ? win.backendError
                                : (win.snapshot ? I18n.t("processexplorer.nothing", "Nothing matches") : I18n.t("processexplorer.loading", "Reading processes…"))
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: s(12)
                            color: win.backendError !== "" ? ThemeBackend.red : ThemeBackend.subtext0
                        }
                    }
                }

                // details
                Rectangle {
                    Layout.preferredWidth: win.selected ? s(260) : 0
                    Layout.fillHeight: true
                    visible: Layout.preferredWidth > 1
                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    radius: ThemeBackend.borderRadius
                    color: Qt.alpha(ThemeBackend.surface0, 0.5)
                    clip: true

                    ColumnLayout {
                        width: s(236)
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.margins: s(12)
                        spacing: s(6)
                        visible: !!win.selected

                        Text {
                            Layout.fillWidth: true
                            text: win.selected ? win.selected.name : ""
                            elide: Text.ElideRight
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: s(14)
                            font.bold: true
                            color: ThemeBackend.text
                        }

                        Repeater {
                            model: {
                                let p = win.selected, d = win.detail;
                                if (!p) return [];
                                let r = [
                                    ["PID", p.pid + "  (" + I18n.t("processexplorer.parent", "parent") + " " + p.ppid + ")"],
                                    [I18n.t("processexplorer.user", "User"), p.user],
                                    ["CPU / RAM", p.cpu.toFixed(1) + "%  ·  " + win.formatBytes(p.mem)],
                                    [I18n.t("processexplorer.threads", "Threads") + " / " + I18n.t("processexplorer.state", "State"), p.threads + "  ·  " + p.state]
                                ];
                                if (d && !d.gone) {
                                    if (d.started) r.push([I18n.t("processexplorer.started", "Started"), new Date(d.started * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat)]);
                                    r.push([I18n.t("processexplorer.exe", "Executable"), d.exe || I18n.t("processexplorer.noAccess", "not readable (another user)")]);
                                }
                                return r;
                            }
                            ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: modelData[0]; font.family: ThemeBackend.fontFamily; font.pixelSize: s(9); color: ThemeBackend.subtext0 }
                                Text { Layout.fillWidth: true; text: modelData[1]; elide: Text.ElideMiddle; font.family: ThemeBackend.fontFamily; font.pixelSize: s(11); color: ThemeBackend.text }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: win.detail && win.detail.cmdline ? win.detail.cmdline : (win.selected ? win.selected.cmd : "")
                            wrapMode: Text.WrapAnywhere
                            elide: Text.ElideRight
                            font.family: "monospace"
                            font.pixelSize: s(9)
                            color: ThemeBackend.subtext1
                        }

                        ClickButton {
                            Layout.fillWidth: true
                            height: s(32)
                            visible: !!(win.detail && win.detail.exe)
                            buttonIcon: "󰉋"
                            buttonText: I18n.t("processexplorer.openLocation", "Open file location")
                            textFontSize: s(11)
                            cornerRadius: ThemeBackend.borderRadius
                            accentColor: ThemeBackend.surface1
                            textColor: ThemeBackend.text
                            onClicked: win.openLocation()
                        }

                        ClickButton {
                            Layout.fillWidth: true
                            height: s(32)
                            enabled: win.canEnd(win.selected)
                            opacity: enabled ? 1 : 0.45
                            buttonIcon: "󰅙"
                            buttonText: win.canEnd(win.selected) ? I18n.t("processexplorer.end", "End process…")
                                : (win.selected && win.snapshot && win.selected.pid === win.snapshot.self ? I18n.t("processexplorer.isShell", "This is the shell")
                                : I18n.t("processexplorer.notOwn", "Owned by another user"))
                            textFontSize: s(11)
                            cornerRadius: ThemeBackend.borderRadius
                            accentColor: ThemeBackend.red
                            textColor: ThemeBackend.crust
                            onClicked: if (win.selected) win.confirmTarget = { pid: win.selected.pid, name: win.selected.name }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: win.actionMessage !== ""
                text: win.actionMessage
                elide: Text.ElideRight
                font.family: ThemeBackend.fontFamily
                font.pixelSize: s(11)
                color: ThemeBackend.subtext1
            }
        }

        // confirmation before ending a process
        Rectangle {
            anchors.fill: parent
            radius: bg.radius
            color: Qt.rgba(0, 0, 0, 0.45)
            visible: opacity > 0.01
            opacity: win.confirmTarget ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            MouseArea { anchors.fill: parent; onClicked: win.confirmTarget = null }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - s(40), s(400))
                height: confirmCol.implicitHeight + s(32)
                radius: ThemeBackend.borderRadius
                color: ThemeBackend.base
                border.width: 1
                border.color: ThemeBackend.red
                scale: win.confirmTarget ? 1 : 0.9
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: confirmCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: s(16)
                    spacing: s(12)
                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("processexplorer.confirmTitle", "End") + " " + (win.confirmTarget ? win.confirmTarget.name + " (PID " + win.confirmTarget.pid + ")" : "") + "?"
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: s(14)
                        font.bold: true
                        color: ThemeBackend.text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("processexplorer.confirmBody", "Unsaved work in this program may be lost. \"End\" asks it to quit (SIGTERM); \"Force\" stops it at once (SIGKILL).")
                        wrapMode: Text.Wrap
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: s(11)
                        color: ThemeBackend.subtext0
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: s(8)
                        Item { Layout.fillWidth: true }
                        ClickButton { height: s(32); horizontalPadding: s(14); buttonText: I18n.t("processexplorer.cancel", "Cancel"); textFontSize: s(11); cornerRadius: ThemeBackend.borderRadius; accentColor: ThemeBackend.surface1; textColor: ThemeBackend.text; onClicked: win.confirmTarget = null }
                        ClickButton { height: s(32); horizontalPadding: s(14); buttonText: I18n.t("processexplorer.force", "Force"); textFontSize: s(11); cornerRadius: ThemeBackend.borderRadius; accentColor: ThemeBackend.surface1; textColor: ThemeBackend.red; onClicked: if (win.confirmTarget) win.endProcess(win.confirmTarget.pid, "KILL") }
                        ClickButton { height: s(32); horizontalPadding: s(14); buttonText: I18n.t("processexplorer.endShort", "End"); textFontSize: s(11); cornerRadius: ThemeBackend.borderRadius; accentColor: ThemeBackend.red; textColor: ThemeBackend.crust; onClicked: if (win.confirmTarget) win.endProcess(win.confirmTarget.pid, "TERM") }
                    }
                }
            }
        }
    }
}
