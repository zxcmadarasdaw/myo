import QtQuick

// Small rotating dot; the animation runs only while visible and running.
Item {
    id: sp
    property real size: 16
    property color color: "#7fd4ff"
    property bool running: false
    property real angle: 0
    width: size
    height: size
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: Math.max(2, sp.size * 0.14)
        border.color: Qt.alpha(sp.color, 0.25)
    }
    Rectangle {
        width: Math.max(3, sp.size * 0.22)
        height: width
        radius: width / 2
        color: sp.color
        x: sp.size / 2 - width / 2 + Math.sin(sp.angle * Math.PI / 180) * (sp.size / 2 - width / 2)
        y: sp.size / 2 - height / 2 - Math.cos(sp.angle * Math.PI / 180) * (sp.size / 2 - height / 2)
    }
    NumberAnimation on angle {
        from: 0; to: 360; duration: 900
        loops: Animation.Infinite
        running: sp.running && sp.visible
    }
}
