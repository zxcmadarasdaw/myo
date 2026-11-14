import QtQuick
import Quickshell
import Quickshell.Io
import "../../../reusables"
import "../../../"
import "../common"
import "FileDockIcons.js" as Icons

// File Dock for the Restrained and Lush looks (FileDockRestrained.qml,
// FileDockLush.qml). Same contract as FileDockFace: only shortcuts live here.
// Removing an item removes the shortcut; nothing on disk is ever deleted,
// moved or renamed. Drops are accepted as a *link*; opening goes through
// xdg-open with the path as one argument, never through a shell.
// FileDockFace itself is left as it is (its animations overshoot); this file
// repeats its shortcut logic so the new looks can animate with OutCubic/OutQuint.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 90
    property real minHeight: 70
    property real maxWidth: 2400
    property real maxHeight: 1600
    property real minAspect: 0
    property real maxAspect: 9999
    property bool isRound: false

    // ---- look (set by the variant files) ----
    property string look: "restrained"    // restrained | lush | atelier
    readonly property bool lush: look === "lush"
    property string faceStyle: "matte"     // Atelier look only (AtelierStyles.js)

    // ---- settings (wProps), same names as FileDockFace ----
    property string itemsJson: ""
    property real iconSize: 44
    property bool showLabels: true
    property real backgroundOpacity: -1      // -1: follow the theme
    property bool startExpanded: false       // accepted for compatibility; these looks are never collapsed

    readonly property bool isLive: !!(parent && parent.liveDesktopWidget === true)
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property FaceTone tone: FaceTone {}

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
    Component.onCompleted: load()

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
    readonly property real iconPx: Scaler.s(Math.max(20, Math.min(128, root.iconSize)))
    readonly property bool labelsShown: root.showLabels
    readonly property real tileW: root.iconPx + Scaler.s(root.labelsShown ? 30 : 14)
    readonly property real tileH: root.iconPx + Scaler.s(root.labelsShown ? 32 : 14)
    readonly property real pad: Scaler.s(root.lush ? 14 : 10)
    property int hoverIndex: -1

    function toneColor(t) {
        if (!root.lush) return root.tone.quietAccent;
        let c = ThemeBackend[t];
        return c !== undefined ? c : ThemeBackend.text;
    }

    // the appear animation lives in the variant files (FileDockRestrained/FileDockLush)

    Loader {
        anchors.fill: parent
        z: -1
        sourceComponent: root.look === "atelier" ? atelierBg : root.lush ? lushBg : minimalBg
    }
    Component {
        id: atelierBg
        AtelierCard {
            kit: AtelierKit { style: root.faceStyle }
            showHeader: false
            emphasised: root.hoverIndex >= 0
        }
    }
    Component {
        id: minimalBg
        MinimalCard { fillOpacity: root.backgroundOpacity >= 0 ? root.backgroundOpacity : Math.max(0.42, Math.min(0.78, ThemeBackend.elementOpacity * 0.75)) }
    }
    Component {
        id: lushBg
        LushCard {
            bodyOpacity: root.backgroundOpacity >= 0 ? root.backgroundOpacity : Math.max(0.55, Math.min(0.86, ThemeBackend.elementOpacity * 0.85))
            intensity: root.hoverIndex >= 0 ? 0.8 : 0.55
            ornate: Math.min(root.width, root.height) >= Scaler.s(120)
        }
    }

    // ---- items ----------------------------------------------------------------------
    Item {
        id: gridHost
        anchors.fill: parent
        anchors.margins: root.pad
        clip: true
        readonly property int columns: Math.max(1, Math.floor((width + grid.spacing) / (root.tileW + grid.spacing)))

        Grid {
            id: grid
            anchors.centerIn: parent
            columns: Math.min(gridHost.columns, Math.max(1, dockModel.count))
            spacing: Scaler.s(root.lush ? 10 : 6)

            move: Transition { NumberAnimation { properties: "x,y"; duration: 280; easing.type: Easing.OutCubic } }
            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: 360; easing.type: Easing.OutQuint }
                }
            }

            Repeater {
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

                    readonly property bool hovered: root.hoverIndex === index
                    readonly property color tint: root.toneColor(Icons.tone(path, dir))

                    Item {
                        id: iconBox
                        width: root.iconPx
                        height: root.iconPx
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Scaler.s(7)
                        scale: tileArea.dragging ? 1.08 : (root.lush && tile.hovered ? 1.06 : 1)
                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }

                        // restrained: hairline square; lush: gradient glass tile
                        Rectangle {
                            anchors.fill: parent
                            visible: !thumb.visible
                            radius: root.lush ? width * 0.28 : Math.min(Scaler.s(3), ThemeBackend.clampedBorderRadius)
                            antialiasing: true
                            color: root.lush ? "transparent" : (tile.hovered ? Qt.alpha(ThemeBackend.text, 0.06) : "transparent")
                            gradient: root.lush ? lushTileGradient : null
                            border.width: 1
                            border.color: root.lush ? Qt.alpha(tile.tint, tile.hovered ? 0.8 : 0.45)
                                                    : (tile.hovered ? root.tone.hairlineStrong : root.tone.hairline)
                            Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Gradient {
                                id: lushTileGradient
                                GradientStop { position: 0.0; color: Qt.alpha(tile.tint, tile.hovered ? 0.38 : 0.26) }
                                GradientStop { position: 1.0; color: Qt.alpha(tile.tint, 0.08) }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !thumb.visible
                            text: Icons.icon(tile.path, tile.dir, root.home)
                            font.family: ThemeBackend.iconFont
                            font.pixelSize: root.iconPx * (root.lush ? 0.56 : 0.5)
                            color: root.lush ? tile.tint : (tile.hovered ? root.tone.ink : root.tone.muted)
                        }

                        Image {
                            id: thumb
                            anchors.fill: parent
                            anchors.margins: root.lush ? 0 : 1
                            visible: status === Image.Ready
                            source: !tile.dir && Icons.isImage(tile.path) ? Caching.fileUrl(tile.path) : ""
                            sourceSize.width: Math.round(root.iconPx * 2)
                            sourceSize.height: Math.round(root.iconPx * 2)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }

                        // opening feedback: a ring that fades out (no movement)
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -Scaler.s(2)
                            radius: root.lush ? width * 0.3 : Scaler.s(2)
                            color: "transparent"
                            border.width: 1
                            border.color: root.lush ? tile.tint : root.tone.ink
                            opacity: openPulse.pulseIndex === tile.index ? openPulse.value : 0
                        }
                    }

                    Text {
                        visible: root.labelsShown
                        anchors.top: iconBox.bottom
                        anchors.topMargin: Scaler.s(5)
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: tile.name
                        elide: Text.ElideMiddle
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: Scaler.s(10)
                        font.italic: root.lush
                        color: tile.hovered ? root.tone.ink : root.tone.muted
                    }

                    // tooltip when labels are off
                    Rectangle {
                        visible: !root.labelsShown && tile.hovered && !tileArea.dragging
                        anchors.bottom: iconBox.top
                        anchors.bottomMargin: Scaler.s(6)
                        anchors.horizontalCenter: iconBox.horizontalCenter
                        width: tipText.implicitWidth + Scaler.s(14)
                        height: tipText.implicitHeight + Scaler.s(8)
                        radius: root.lush ? height / 2 : Scaler.s(2)
                        color: ThemeBackend.base
                        border.width: 1
                        border.color: root.tone.hairline
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
                text: String.fromCodePoint(0xF0257)
                font.family: ThemeBackend.iconFont
                font.pixelSize: Scaler.s(24)
                color: root.tone.faint
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.t("widgets.filedock.empty", "Drop files or folders here")
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(11)
                color: root.tone.muted
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
        radius: root.lush ? Scaler.s(16) : Scaler.s(2)
        color: Qt.alpha(ThemeBackend.mauve, root.lush ? 0.12 : 0.06)
        border.width: 1
        border.color: root.lush ? ThemeBackend.mauve : root.tone.hairlineStrong
        opacity: dropArea.containsDrag ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
}
