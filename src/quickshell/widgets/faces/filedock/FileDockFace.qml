import QtQuick
import Quickshell
import Quickshell.Io
import "../../../reusables"
import "../../../"
import "FileDockIcons.js" as Icons

// File Dock: shortcuts to files and folders on the desktop.
//
// Only shortcuts live here. Removing an item removes the shortcut; nothing
// on disk is ever deleted, moved or renamed. Files dropped from a file
// manager are accepted as a *link* action, so the file manager never treats
// the drop as a move. Opening goes through xdg-open (the default app / file
// manager) with the path as a plain argument, never through a shell.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 70
    property real minHeight: 56
    property real maxWidth: 2400
    property real maxHeight: 1600
    property real minAspect: 0
    property real maxAspect: 9999
    property bool isRound: false

    // ---- variant (set by the variant files) ----
    property string dockStyle: "floating"   // floating | minimal | stack | expandable | grid | cyber

    // ---- settings (wProps) ----
    // [{ "path": "/home/u/Documents", "name": "Documents", "dir": true }]
    // "" means "never edited": the XDG folders are shown until the first change.
    property string itemsJson: ""
    property real iconSize: 44
    property bool showLabels: true
    property real backgroundOpacity: -1      // -1: follow the theme
    property bool startExpanded: false

    readonly property bool isLive: !!(parent && parent.liveDesktopWidget === true)
    readonly property string home: Quickshell.env("HOME") || ""

    function persist(prop, val) {
        if (!root.isLive || !parent.widgetId) return;
        WidgetSync.setProperty(parent.widgetMonitor, parent.widgetId, prop, val);
    }

    // ---- model -------------------------------------------------------------
    ListModel { id: dockModel }
    property alias model: dockModel
    readonly property int count: dockModel.count
    property bool _writing: false

    function defaultItems() {
        if (root.home === "") return [];
        return [
            { path: root.home, name: I18n.t("widgets.filedock.home", "Home"), dir: true },
            { path: root.home + "/Downloads", name: "Downloads", dir: true },
            { path: root.home + "/Documents", name: "Documents", dir: true },
            { path: root.home + "/Pictures", name: "Pictures", dir: true }
        ];
    }

    function load() {
        let list = root.itemsJson === "" ? defaultItems() : Icons.parse(root.itemsJson);
        dockModel.clear();
        for (let it of list) dockModel.append({ path: it.path, name: it.name, dir: !!it.dir });
    }

    function serialize() {
        let out = [];
        for (let i = 0; i < dockModel.count; i++) {
            let it = dockModel.get(i);
            out.push({ path: it.path, name: it.name, dir: !!it.dir });
        }
        return out;
    }

    function commit() {
        root._writing = true;
        root.itemsJson = JSON.stringify(serialize());
        root._writing = false;
        root.persist("itemsJson", root.itemsJson);
    }

    function indexOfPath(path) {
        for (let i = 0; i < dockModel.count; i++) if (dockModel.get(i).path === path) return i;
        return -1;
    }

    function addPath(path, isDir) {
        let p = String(path || "").trim();
        if (p.indexOf("file://") === 0) p = Icons.urlToPath(p);
        if (p.length > 1) p = p.replace(/\/+$/, "");
        if (p === "" || p[0] !== "/" || indexOfPath(p) !== -1) return false;
        dockModel.append({ path: p, name: Icons.baseName(p), dir: !!isDir });
        commit();
        return true;
    }

    // Removes the shortcut only.
    function removeAt(i) {
        if (i < 0 || i >= dockModel.count) return;
        dockModel.remove(i, 1);
        commit();
    }

    function moveItem(from, to) {
        if (from === to || from < 0 || to < 0 || from >= dockModel.count || to >= dockModel.count) return;
        dockModel.move(from, to, 1);
        commit();
    }

    function openItem(i) {
        if (!root.isLive || i < 0 || i >= dockModel.count) return;
        let p = dockModel.get(i).path;
        if (!p || p[0] !== "/") return;
        Quickshell.execDetached(["xdg-open", p]);
        openPulse.pulseIndex = i;
        openPulse.restart();
    }

    onItemsJsonChanged: if (!root._writing) load()
    Component.onCompleted: {
        load();
        root.expanded = root.startExpanded;
        appear.start();
    }

    // Dropped paths: ask the file system whether each is a folder.
    property var _probeQueue: []
    function probeAndAdd(paths) {
        root._probeQueue = root._probeQueue.concat(paths);
        if (!dirProbe.running) nextProbe();
    }
    function nextProbe() {
        if (root._probeQueue.length === 0) return;
        let q = root._probeQueue.slice();
        dirProbe.pending = q.shift();
        root._probeQueue = q;
        dirProbe.command = ["test", "-d", dirProbe.pending];
        dirProbe.running = true;
    }
    Process {
        id: dirProbe
        property string pending: ""
        running: false
        onExited: (exitCode, exitStatus) => {
            root.addPath(dirProbe.pending, exitCode === 0);
            Qt.callLater(root.nextProbe);
        }
    }

    // ---- look ----------------------------------------------------------------
    readonly property bool cyber: dockStyle === "cyber"
    readonly property bool hasCard: dockStyle !== "minimal"
    readonly property bool magnify: dockStyle === "floating" || dockStyle === "minimal"
    readonly property bool labelsShown: root.showLabels && (dockStyle === "grid" || dockStyle === "cyber" || dockStyle === "stack" || (dockStyle === "expandable" && root.expanded))
    readonly property bool collapsible: dockStyle === "stack" || dockStyle === "expandable"
    property bool expanded: false
    readonly property bool showGrid: !root.collapsible || root.expanded

    readonly property color neonA: "#00f0ff"
    readonly property color neonB: "#ff2bd6"
    readonly property real s1: Scaler.s(1)
    readonly property real iconPx: Scaler.s(Math.max(20, Math.min(128, root.iconSize)))
    readonly property real tileW: root.iconPx + Scaler.s(root.labelsShown ? 28 : 12)
    readonly property real tileH: root.iconPx + Scaler.s(root.labelsShown ? 30 : 12)
    readonly property real pad: Scaler.s(root.hasCard ? 12 : 4)
    readonly property real stripH: root.iconPx * 0.7 + Scaler.s(20)

    function toneColor(t) {
        if (root.cyber) return t === "blue" ? root.neonA : root.neonB;
        let c = ThemeBackend[t];
        return c !== undefined ? c : ThemeBackend.text;
    }

    property int hoverIndex: -1

    opacity: 0
    scale: 0.94
    ParallelAnimation {
        id: appear
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "scale"; to: 1; duration: 420; easing.type: Easing.OutBack }
    }

    // ---- background --------------------------------------------------------------
    Rectangle {
        id: card
        visible: root.hasCard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.dockStyle === "expandable" && !root.expanded ? Math.min(parent.height, root.stripH) : parent.height
        Behavior on height { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
        radius: root.cyber ? Scaler.s(6) : ThemeBackend.clampedBorderRadius
        color: root.cyber
            ? Qt.rgba(0.02, 0.03, 0.06, root.backgroundOpacity >= 0 ? root.backgroundOpacity : Math.max(0.55, ThemeBackend.elementOpacity))
            : Qt.alpha(ThemeBackend.surface0, root.backgroundOpacity >= 0 ? root.backgroundOpacity : ThemeBackend.elementOpacity)
        border.width: 1
        border.color: root.cyber ? Qt.alpha(root.neonA, 0.6) : Qt.alpha(ThemeBackend.text, 0.07)
        clip: true

        WallpaperBlur {
            z: -1
            anchors.fill: parent
            radius: parent.radius
            visible: !root.cyber && root.backgroundOpacity !== 0
        }
    }

    // ---- collapsed representations -------------------------------------------------
    // Folder Stack: fanned cards with a counter.
    Item {
        id: stackView
        visible: opacity > 0.01
        opacity: root.dockStyle === "stack" && !root.expanded ? 1 : 0
        scale: root.dockStyle === "stack" && !root.expanded ? 1 : 0.85
        Behavior on opacity { NumberAnimation { duration: 260 } }
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        anchors.centerIn: parent
        width: root.iconPx * 1.8
        height: root.iconPx * 1.6

        Repeater {
            model: Math.min(3, dockModel.count)
            Rectangle {
                readonly property var it: dockModel.get(index)
                width: root.iconPx * 1.2
                height: root.iconPx
                anchors.centerIn: parent
                radius: Scaler.s(8)
                rotation: (index - 1) * (stackHover.containsMouse ? 14 : 8)
                Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                x: (index - 1) * (stackHover.containsMouse ? Scaler.s(14) : Scaler.s(6))
                color: Qt.alpha(root.toneColor(Icons.tone(it ? it.path : "", it ? it.dir : true)), 0.22 + index * 0.1)
                border.width: 1
                border.color: Qt.alpha(ThemeBackend.text, 0.12)
                Text {
                    anchors.centerIn: parent
                    text: it ? Icons.icon(it.path, it.dir, root.home) : ""
                    font.family: ThemeBackend.iconFont
                    font.pixelSize: root.iconPx * 0.55
                    color: root.toneColor(Icons.tone(it ? it.path : "", it ? it.dir : true))
                }
            }
        }

        Rectangle {
            visible: dockModel.count > 0
            anchors.right: parent.right
            anchors.top: parent.top
            width: Scaler.s(22); height: width; radius: width / 2
            color: ThemeBackend.mauve
            Text { anchors.centerIn: parent; text: dockModel.count; font.pixelSize: Scaler.s(11); font.bold: true; color: ThemeBackend.crust }
        }

        MouseArea {
            id: stackHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = true
        }
    }

    // Expandable Dock: a strip with the first icons and a chevron.
    Row {
        id: stripView
        visible: opacity > 0.01
        opacity: root.dockStyle === "expandable" && !root.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 220 } }
        anchors.left: parent.left
        anchors.leftMargin: Scaler.s(12)
        y: (Math.min(root.height, root.stripH) - height) / 2
        spacing: Scaler.s(8)

        Repeater {
            model: Math.max(0, Math.min(dockModel.count, Math.floor((root.width - Scaler.s(60)) / (root.iconPx * 0.7 + Scaler.s(8)))))
            Text {
                readonly property var it: dockModel.get(index)
                text: it ? Icons.icon(it.path, it.dir, root.home) : ""
                font.family: ThemeBackend.iconFont
                font.pixelSize: root.iconPx * 0.55
                color: root.toneColor(Icons.tone(it ? it.path : "", it ? it.dir : true))
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // Collapse / expand control for the two collapsible styles.
    Text {
        visible: root.collapsible && (root.dockStyle === "expandable" || root.expanded)
        z: 5
        anchors.right: parent.right
        anchors.rightMargin: Scaler.s(10)
        y: root.dockStyle === "expandable" ? (Math.min(root.height, root.stripH) - height) / 2 : Scaler.s(8)
        text: root.expanded ? "󰅃" : "󰅀"
        font.family: ThemeBackend.iconFont
        font.pixelSize: Scaler.s(18)
        color: chevronArea.containsMouse ? ThemeBackend.mauve : ThemeBackend.subtext0
        Behavior on color { ColorAnimation { duration: 150 } }
        MouseArea {
            id: chevronArea
            anchors.fill: parent
            anchors.margins: -Scaler.s(6)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    MouseArea {
        // the whole strip toggles too
        visible: root.dockStyle === "expandable" && !root.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.min(root.height, root.stripH)
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = true
    }

    // ---- items --------------------------------------------------------------------
    Item {
        id: gridHost
        anchors.fill: parent
        anchors.margins: root.pad
        anchors.topMargin: root.pad + (root.collapsible ? Scaler.s(18) : 0)
        visible: opacity > 0.01
        opacity: root.showGrid ? 1 : 0
        scale: root.showGrid ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
        clip: !root.magnify

        readonly property int columns: Math.max(1, Math.floor((width + grid.spacing) / (root.tileW + grid.spacing)))

        Grid {
            id: grid
            anchors.centerIn: parent
            columns: Math.min(gridHost.columns, Math.max(1, dockModel.count))
            spacing: Scaler.s(root.magnify ? 4 : 8)

            move: Transition { NumberAnimation { properties: "x,y"; duration: 260; easing.type: Easing.OutCubic } }
            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "scale"; from: 0.4; to: 1; duration: 300; easing.type: Easing.OutBack }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                }
            }

            Repeater {
                id: tiles
                model: dockModel

                Item {
                    id: tile
                    required property int index
                    required property string path
                    required property string name
                    required property bool dir

                    width: root.tileW
                    height: root.tileH
                    z: tileArea.containsMouse || tileArea.dragging ? 10 : 1

                    readonly property int row: Math.floor(index / grid.columns)
                    readonly property bool hovered: root.hoverIndex === index
                    readonly property bool neighbour: root.hoverIndex >= 0 && Math.abs(root.hoverIndex - index) === 1
                        && Math.floor(root.hoverIndex / grid.columns) === row
                    readonly property color tone: root.toneColor(Icons.tone(path, dir))

                    Item {
                        id: iconBox
                        width: root.iconPx
                        height: root.iconPx
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Scaler.s(6)
                        transformOrigin: root.magnify ? Item.Bottom : Item.Center
                        scale: tileArea.dragging ? 1.12
                            : (root.magnify ? (tile.hovered ? 1.32 : (tile.neighbour ? 1.12 : 1)) : (tile.hovered ? 1.08 : 1))
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

                        Rectangle {
                            anchors.fill: parent
                            radius: root.cyber ? Scaler.s(4) : Scaler.s(10)
                            color: Qt.alpha(tile.tone, root.cyber ? 0.08 : 0.16)
                            border.width: root.cyber ? 1 : 0
                            border.color: tile.tone
                            visible: !thumb.visible
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !thumb.visible
                            text: Icons.icon(tile.path, tile.dir, root.home)
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: root.iconPx * 0.58
                            color: tile.tone
                            style: root.dockStyle === "minimal" ? Text.Raised : Text.Normal
                            styleColor: Qt.alpha(ThemeBackend.crust, 0.5)
                        }

                        Image {
                            id: thumb
                            anchors.fill: parent
                            visible: status === Image.Ready
                            source: !tile.dir && Icons.isImage(tile.path) ? Caching.fileUrl(tile.path) : ""
                            sourceSize.width: Math.round(root.iconPx * 2)
                            sourceSize.height: Math.round(root.iconPx * 2)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }

                        // opening feedback
                        Rectangle {
                            anchors.fill: parent
                            radius: Scaler.s(10)
                            color: "transparent"
                            border.width: 2
                            border.color: tile.tone
                            opacity: openPulse.pulseIndex === tile.index ? openPulse.value : 0
                            scale: 1 + (1 - opacity) * 0.3
                        }
                    }

                    Text {
                        visible: root.labelsShown
                        anchors.top: iconBox.bottom
                        anchors.topMargin: Scaler.s(4)
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.name
                        elide: Text.ElideMiddle
                        font.family: root.cyber ? "JetBrains Mono" : ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        color: root.cyber ? root.neonA : ThemeBackend.text
                    }

                    // tooltip for the label-less styles
                    Rectangle {
                        visible: !root.labelsShown && tile.hovered && !tileArea.dragging
                        anchors.bottom: iconBox.top
                        anchors.bottomMargin: Scaler.s(14)
                        anchors.horizontalCenter: iconBox.horizontalCenter
                        width: tipText.implicitWidth + Scaler.s(14)
                        height: tipText.implicitHeight + Scaler.s(8)
                        radius: Scaler.s(6)
                        color: ThemeBackend.crust
                        Text {
                            id: tipText
                            anchors.centerIn: parent
                            text: tile.name
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: Scaler.s(11)
                            color: ThemeBackend.text
                        }
                    }

                    MouseArea {
                        id: tileArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        pressAndHoldInterval: 350
                        property bool dragging: false

                        onEntered: root.hoverIndex = tile.index
                        onExited: if (root.hoverIndex === tile.index) root.hoverIndex = -1
                        onDoubleClicked: root.openItem(tile.index)
                        onPressAndHold: if (root.isLive && dockModel.count > 1) dragging = true
                        onPositionChanged: mouse => {
                            if (!dragging) return;
                            let p = tileArea.mapToItem(grid, mouse.x, mouse.y);
                            let col = Math.max(0, Math.min(grid.columns - 1, Math.floor(p.x / (root.tileW + grid.spacing))));
                            let row = Math.max(0, Math.floor(p.y / (root.tileH + grid.spacing)));
                            let target = Math.max(0, Math.min(dockModel.count - 1, row * grid.columns + col));
                            if (target !== tile.index) dockModel.move(tile.index, target, 1);
                        }
                        onReleased: if (dragging) { dragging = false; root.commit(); }
                        onCanceled: if (dragging) { dragging = false; root.commit(); }
                    }
                }
            }
        }

        // empty state
        Column {
            anchors.centerIn: parent
            visible: dockModel.count === 0
            spacing: Scaler.s(4)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰉗"
                font.family: ThemeBackend.iconFont
                font.pixelSize: Scaler.s(26)
                color: ThemeBackend.subtext0
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.t("widgets.filedock.empty", "Drop files or folders here")
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(11)
                color: ThemeBackend.subtext0
            }
        }
    }

    // shared "opened" pulse
    NumberAnimation {
        id: openPulse
        property int pulseIndex: -1
        property real value: 0
        target: openPulse
        property: "value"
        from: 1
        to: 0
        duration: 600
        easing.type: Easing.OutCubic
    }

    // ---- drag and drop from file managers -----------------------------------------
    DropArea {
        id: dropArea
        anchors.fill: parent
        enabled: root.isLive
        keys: ["text/uri-list"]
        onEntered: drag => {
            // Link, never move: the file manager must not delete the source.
            drag.accepted = drag.hasUrls;
            if (drag.hasUrls) drag.action = (drag.supportedActions & Qt.LinkAction) ? Qt.LinkAction : Qt.CopyAction;
        }
        onDropped: drop => {
            if (!drop.hasUrls) return;
            let paths = [];
            for (let u of drop.urls) {
                let s = String(u);
                if (s.indexOf("file://") === 0) paths.push(Icons.urlToPath(s));
            }
            drop.dropAction = (drop.supportedActions & Qt.LinkAction) ? Qt.LinkAction : Qt.CopyAction;
            drop.accept();
            if (paths.length > 0) root.probeAndAdd(paths);
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: Qt.alpha(ThemeBackend.mauve, 0.12)
        border.width: 2
        border.color: ThemeBackend.mauve
        opacity: dropArea.containsDrag ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
}
