pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// GPU load shared by every GPU widget: one serp_gpu.py process while at least one
// widget is subscribed, none otherwise. `available` stays false (and `percent` -1)
// when the driver reports no load, so nothing invents a reading.
Item {
    id: root

    property bool available: false
    property string reason: ""
    property string name: ""
    property string source: ""
    property int percent: -1
    property int temp: -1
    property int vramUsedMb: -1
    property int vramTotalMb: -1
    property bool received: false

    property int subscribers: 0
    property int interval: SysData.onBattery ? 4 : 2

    function subscribe() {
        subscribers++;
        if (subscribers === 1) proc.running = true;
    }
    function unsubscribe() {
        subscribers = Math.max(0, subscribers - 1);
        if (subscribers === 0) proc.running = false;
    }

    function apply(line) {
        let u;
        try { u = JSON.parse(String(line || "").trim()); } catch (e) { return; }
        if (!u || typeof u !== "object") return;
        root.received = true;
        root.available = u.available === true;
        root.reason = u.reason || "";
        root.name = u.name || "";
        root.source = u.source || "";
        root.percent = root.available && typeof u.percent === "number" ? u.percent : -1;
        root.temp = typeof u.temp === "number" ? u.temp : -1;
        root.vramUsedMb = typeof u.vramUsedMb === "number" ? u.vramUsedMb : -1;
        root.vramTotalMb = typeof u.vramTotalMb === "number" ? u.vramTotalMb : -1;
    }

    Process {
        id: proc
        running: false
        command: ["python3", Caching.serpantinumDir + "/scripts/system/serp_gpu.py", "--interval", String(root.interval)]
        stdout: SplitParser { onRead: data => root.apply(data) }
        onExited: (code, status) => {
            if (code !== 0 && !root.received) {
                root.available = false;
                root.reason = "python3";
            }
        }
    }
}
