import QtQuick
import "../../"
import "CanvasMath.js" as CM

// Small map of one monitor's canvas: every widget, the home screen and the part
// of the world the monitor shows right now. Press or drag to move the camera.
Item {
    id: map

    // Widget records (wX, wY, wWidth, wHeight, wRotation, wId).
    property var widgets: []
    property real camX: 0
    property real camY: 0
    property real camZoom: 1
    property real screenW: 1920
    property real screenH: 1080
    property var selectedIds: []
    property bool interactive: true

    property color widgetColor: Qt.alpha(ThemeBackend.text, 0.55)
    property color selectedColor: ThemeBackend.mauve
    property color viewColor: ThemeBackend.mauve
    property color homeColor: Qt.alpha(ThemeBackend.subtext0, 0.6)

    // World point the user asked for; the owner centres the camera on it.
    signal navigate(real worldX, real worldY)
    signal released()

    readonly property var cam: ({ x: map.camX, y: map.camY, zoom: map.camZoom > 0 ? map.camZoom : 1 })
    readonly property var liveTransform: CM.minimapTransform(CM.minimapArea(map.widgets, map.cam, map.screenW, map.screenH), map.width, map.height, 4)
    // While the pointer is down the map must not rescale under it.
    property var frozenTransform: null
    readonly property var t: map.frozenTransform ? map.frozenTransform : map.liveTransform

    function mx(worldX) { return (worldX - map.t.originX) * map.t.scale + map.t.offsetX; }
    function my(worldY) { return (worldY - map.t.originY) * map.t.scale + map.t.offsetY; }

    clip: true

    Rectangle {
        x: map.mx(0)
        y: map.my(0)
        width: Math.max(2, map.screenW * map.t.scale)
        height: Math.max(2, map.screenH * map.t.scale)
        color: "transparent"
        border.width: 1
        border.color: map.homeColor
        radius: 2
    }

    Repeater {
        model: map.widgets
        delegate: Rectangle {
            required property var modelData
            readonly property var box: CM.widgetBox(modelData)
            readonly property bool selected: map.selectedIds.indexOf(String(modelData.wId)) >= 0
            x: map.mx(box.x)
            y: map.my(box.y)
            width: Math.max(2, box.w * map.t.scale)
            height: Math.max(2, box.h * map.t.scale)
            radius: Math.min(2, width / 2, height / 2)
            color: selected ? map.selectedColor : map.widgetColor
        }
    }

    Rectangle {
        x: map.mx(map.camX)
        y: map.my(map.camY)
        width: Math.max(4, map.screenW / map.cam.zoom * map.t.scale)
        height: Math.max(4, map.screenH / map.cam.zoom * map.t.scale)
        color: Qt.alpha(map.viewColor, 0.14)
        border.width: 1
        border.color: map.viewColor
        radius: 2
    }

    MouseArea {
        anchors.fill: parent
        enabled: map.interactive
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        function go(mouse) {
            let w = CM.miniToWorld(map.t, mouse.x, mouse.y);
            map.navigate(w.x, w.y);
        }

        onPressed: mouse => {
            map.frozenTransform = map.liveTransform;
            go(mouse);
        }
        onPositionChanged: mouse => {
            if (pressed) go(mouse);
        }
        onReleased: {
            map.frozenTransform = null;
            map.released();
        }
        onCanceled: {
            map.frozenTransform = null;
            map.released();
        }
    }
}
