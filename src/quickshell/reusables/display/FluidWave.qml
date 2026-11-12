import QtQuick
import "../../"

ShaderEffect {
    id: root

    property real radius: 0.0
    property real fillLevel: 0.0
    property real waveAmp: 0.0
    property vector2d itemSize: Qt.vector2d(width, height)
    property real phase: 0.0
    property real vertical: 1.0
    property color color1: ThemeBackend.primary
    property color color2: color1
    property vector4d params: Qt.vector4d(1.0, 0.0, 0.0, 0.0)

    onStatusChanged: { if (String(fragmentShader) !== "") GpuCompatibility.observeShader(String(fragmentShader), status, log); }
    fragmentShader: GpuCompatibility.shadersAllowed ? ("file://" + Caching.serpantinumDir + "/assets/shaders/fluid/fluid_wave.frag.qsb") : ""
    Rectangle {
        visible: !GpuCompatibility.shadersAllowed
        anchors.bottom: parent.bottom
        width: root.vertical > 0.5 ? parent.width : parent.width * Math.max(0, Math.min(1, root.fillLevel))
        height: root.vertical > 0.5 ? parent.height * Math.max(0, Math.min(1, root.fillLevel)) : parent.height
        radius: Math.min(root.radius, width / 2, height / 2)
        color: root.color1
    }
}
