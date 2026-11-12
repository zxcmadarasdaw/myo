import QtQuick
import "../../"

ShaderEffect {
    id: root

    property real radius: 0.0
    property real fillLevel: 0.0
    property real waveAmp: 0.0
    property vector2d itemSize: Qt.vector2d(width, height)
    property real phase: 0.0
    property real bodyAlpha: 0.5
    property color color1: ThemeBackend.primary
    property color color2: color1

    onStatusChanged: { if (String(fragmentShader) !== "") GpuCompatibility.observeShader(String(fragmentShader), status, log); }
    fragmentShader: GpuCompatibility.shadersAllowed ? ("file://" + Caching.serpantinumDir + "/assets/shaders/fluid/liquid_fill.frag.qsb") : ""
    Rectangle {
        visible: !GpuCompatibility.shadersAllowed
        anchors.bottom: parent.bottom
        width: parent.width
        height: parent.height * Math.max(0, Math.min(1, root.fillLevel))
        radius: Math.min(root.radius, width / 2, height / 2)
        color: Qt.alpha(root.color1, root.bodyAlpha)
    }
}
