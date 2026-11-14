import QtQuick
import "../../../"
import "UsageReadings.js" as UsageReadings

// CPU / RAM / temperature / disk, Atelier. The readings are the same SysData values
// (and the same UsageReadings formatting) as every other usage face; the subscription
// lives in UsageFaceBase. `kind` is set by the per-type files.
UsageFaceBase {
    id: root
    clip: true
    minWidth: 110
    minHeight: 44
    maxWidth: 900
    maxHeight: 600
    minAspect: 0.6
    maxAspect: 9.0

    property string kind: "cpu"
    property string faceStyle: "matte"

    readonly property var reading: UsageReadings.read(root.kind, SysData.cpu, SysData.ramPercent, SysData.ramGb,
                                                      SysData.temp, SysData.diskPercent, SysData.diskGb, SysData.diskTotalGb)
    // Temperature 0 means the sensor gave nothing; show that rather than "0°".
    readonly property bool measured: root.kind !== "temp" || SysData.temp > 0

    AtelierUsageBody {
        faceStyle: root.faceStyle
        title: I18n.t(root.reading.titleKey, root.reading.title)
        valueText: root.measured ? root.reading.text : "—"
        detailText: root.reading.detail
        value: root.measured ? root.reading.value : -1
        note: root.measured ? "" : I18n.t("widgets.atelier.noSensor", "No sensor reading")
        sampleInterval: SysData.streamInterval * 1000
    }
}
