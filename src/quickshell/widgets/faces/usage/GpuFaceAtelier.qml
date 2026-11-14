import QtQuick
import "../../../"

// GPU, Atelier: busy percent, VRAM and temperature from GpuStats (sysfs or nvidia-smi).
// Holds a GpuStats subscription only while visible. Without a source it says so.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property bool previewMode: false
    property string faceStyle: "technical"
    property real minWidth: 110
    property real minHeight: 44
    property real maxWidth: 900
    property real maxHeight: 600
    property real minAspect: 0.6
    property real maxAspect: 9.0
    property bool isRound: false

    property bool isSubscribed: false
    function updateSubscription() {
        if (root.visible && !root.isSubscribed) { GpuStats.subscribe(); root.isSubscribed = true; }
        else if (!root.visible && root.isSubscribed) { GpuStats.unsubscribe(); root.isSubscribed = false; }
    }
    onVisibleChanged: updateSubscription()
    Component.onCompleted: updateSubscription()
    Component.onDestruction: if (root.isSubscribed) { GpuStats.unsubscribe(); root.isSubscribed = false; }

    readonly property bool known: GpuStats.available && GpuStats.percent >= 0
    readonly property string detail: {
        let parts = [];
        if (GpuStats.vramTotalMb > 0)
            parts.push((GpuStats.vramUsedMb / 1024).toFixed(1) + " / " + (GpuStats.vramTotalMb / 1024).toFixed(0) + "G");
        if (GpuStats.temp > 0) parts.push(GpuStats.temp + "°");
        return parts.join("  ·  ");
    }

    AtelierUsageBody {
        faceStyle: root.faceStyle
        title: "GPU"
        valueText: root.known ? GpuStats.percent + "%" : "—"
        detailText: root.detail
        value: root.known ? GpuStats.percent / 100 : -1
        note: root.known ? "" : !GpuStats.received ? I18n.t("widgets.atelier.waiting", "Waiting for data")
              : I18n.t("widgets.atelier.gpuUnavailable", "The GPU driver reports no load")
        sampleInterval: GpuStats.interval * 1000
    }
}
