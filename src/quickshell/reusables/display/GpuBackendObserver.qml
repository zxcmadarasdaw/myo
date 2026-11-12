import QtQuick
import "../../"

// Attach to an actual visible shell window, not a windowless singleton.
Item {
    id: observer
    property string observerKey: "renderer-" + Math.random().toString(36).slice(2)
    readonly property int graphicsApi: GraphicsInfo.api
    function publish() {
        let name = "Unknown";
        if (graphicsApi === GraphicsInfo.Software) name = "Software";
        else if (graphicsApi === GraphicsInfo.Null) name = "Null";
        else if (graphicsApi === GraphicsInfo.OpenGL) name = "OpenGL";
        else if (graphicsApi === GraphicsInfo.Vulkan) name = "Vulkan";
        else if (graphicsApi === GraphicsInfo.Direct3D11) name = "Direct3D11";
        else if (graphicsApi === GraphicsInfo.Metal) name = "Metal";
        GpuCompatibility.observeBackend(observerKey, name);
    }
    onGraphicsApiChanged: publish()
    Component.onCompleted: publish()
    Component.onDestruction: GpuCompatibility.forgetBackend(observerKey)
}
