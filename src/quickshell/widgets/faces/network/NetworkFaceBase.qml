import QtQuick
import Quickshell
import Quickshell.Networking
import "../../../"

// Shared logic of the Network Monitor Pro faces. All faces read the one
// NetStats sampler (real /proc/net/dev counters); none starts a process of
// its own. Settings are plain properties, saved per widget by the editor.
Item {
    id: root
    anchors.fill: parent

    property bool previewMode: false

    property real minWidth: 90
    property real minHeight: 34
    property real maxWidth: 900
    property real maxHeight: 600
    property real minAspect: 0
    property real maxAspect: 9999
    property bool isRound: false

    // ---- settings (wProps) ----
    property string interfaceName: "auto"   // "auto" or an interface such as wlp2s0
    property int updateInterval: 1000       // ms
    property bool showLatency: false        // runs `ping` every 5 s while on
    property string pingHost: "1.1.1.1"
    property bool showTotals: true

    // ---- where the face lives (see Widget.qml) ----
    readonly property bool isLive: !!(parent && parent.liveDesktopWidget === true)

    function persist(prop, val) {
        if (!root.isLive || !parent.widgetId) return;
        WidgetSync.setProperty(parent.widgetMonitor, parent.widgetId, prop, val);
    }

    function cycleInterface() {
        let next = NetStats.nextInterface(root.interfaceName);
        root.interfaceName = next;
        root.persist("interfaceName", next);
    }

    // ---- data ----
    readonly property var stats: NetStats.stats(root.interfaceName)
    readonly property var hist: NetStats.historyFor(root.interfaceName)
    readonly property string ifaceName: stats.name || "—"
    readonly property string ifaceType: stats.type || "other"
    readonly property bool hasInterface: stats.name !== ""

    property real rxSpeed: stats.rx || 0
    property real txSpeed: stats.tx || 0
    Behavior on rxSpeed { enabled: root.visible; NumberAnimation { duration: Math.min(900, root.updateInterval * 0.9); easing.type: Easing.OutCubic } }
    Behavior on txSpeed { enabled: root.visible; NumberAnimation { duration: Math.min(900, root.updateInterval * 0.9); easing.type: Easing.OutCubic } }

    readonly property string rxText: NetStats.formatSpeed(root.rxSpeed)
    readonly property string txText: NetStats.formatSpeed(root.txSpeed)
    readonly property string rxShort: NetStats.formatShortSpeed(root.rxSpeed)
    readonly property string txShort: NetStats.formatShortSpeed(root.txSpeed)
    readonly property string rxTotalText: NetStats.formatBytes(stats.rxTotal)
    readonly property string txTotalText: NetStats.formatBytes(stats.txTotal)
    readonly property string latencyText: !root.showLatency ? ""
        : (NetStats.latencyMs >= 0 ? Math.round(NetStats.latencyMs) + " ms" : (NetStats.latencyFailed ? I18n.t("widgets.network.noReply", "no reply") : "…"))
    readonly property string typeIcon: root.ifaceType === "wifi" ? root.wifiIcon : NetStats.typeIcon(root.ifaceType)
    readonly property string typeLabel: NetStats.typeLabel(root.ifaceType)

    // ---- Wi-Fi name and signal, the same source the bar indicator uses ----
    property string wifiSsid: ""
    property string wifiIcon: "󰤨"

    function refreshWifi() {
        let ssid = "";
        let icon = "󰤨";
        try {
            let devs = Networking.devices ? (Networking.devices.values || Networking.devices) : [];
            for (let i = 0; i < devs.length; i++) {
                let d = devs[i];
                if (!d || d.type !== DeviceType.Wifi || !d.networks) continue;
                let nets = d.networks.values || d.networks;
                for (let j = 0; j < nets.length; j++) {
                    let n = nets[j];
                    if (n && n.connected) {
                        ssid = n.name || n.ssid || "";
                        let s = n.signalStrength !== undefined ? Math.round(n.signalStrength * (n.signalStrength <= 1 ? 100 : 1)) : 100;
                        icon = s >= 80 ? "󰤨" : s >= 60 ? "󰤥" : s >= 40 ? "󰤢" : s >= 20 ? "󰤟" : "󰤯";
                    }
                }
            }
        } catch (e) {}
        root.wifiSsid = ssid;
        root.wifiIcon = icon;
    }

    readonly property string connectionName: root.ifaceType === "wifi" && root.wifiSsid !== "" ? root.wifiSsid : root.typeLabel

    Timer {
        interval: 5000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.refreshWifi()
    }

    // ---- subscription to the shared sampler ----
    readonly property string token: "netface-" + Math.random().toString(36).slice(2)

    function updateSubscription() {
        if (root.visible) NetStats.register(root.token, root.updateInterval, root.showLatency, root.pingHost);
        else NetStats.unregister(root.token);
    }

    onVisibleChanged: updateSubscription()
    onUpdateIntervalChanged: updateSubscription()
    onShowLatencyChanged: updateSubscription()
    onPingHostChanged: updateSubscription()
    Component.onCompleted: updateSubscription()
    Component.onDestruction: NetStats.unregister(root.token)

    function openNetworkPanel() {
        if (!root.isLive) return;
        Quickshell.execDetached(["bash", Caching.serpantinumDir + "/scripts/qs_manager.sh", "toggle", "network", root.ifaceType === "ethernet" ? "" : "wifi"]);
    }
}
