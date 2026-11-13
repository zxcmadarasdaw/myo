pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Network Monitor Pro data source.
//
// One shared sampler for every network card, the bar's speed variant and any
// other consumer. It reads the kernel counters directly:
//   /proc/net/dev       bytes received / sent per interface
//   /proc/net/route     the interface that carries the default route
//   /proc/net/wireless  which interfaces are Wi-Fi
// so it starts no process at all. Sampling runs only while at least one
// consumer is registered, at the shortest interval any of them asked for.
// Latency is measured with `ping` only while a consumer explicitly enables it.
Item {
    id: root

    // ---- consumers -------------------------------------------------------
    property var _clients: ({})
    property int _clientRev: 0

    // token: any unique string; intervalMs: wanted refresh; wantPing: latency probe
    function register(token, intervalMs, wantPing, pingHost) {
        if (!token) return;
        let c = Object.assign({}, _clients);
        c[token] = {
            interval: Math.max(250, Math.min(10000, Number(intervalMs) || 1000)),
            ping: !!wantPing,
            host: root.validHost(pingHost) ? String(pingHost).trim() : ""
        };
        _clients = c;
        _clientRev++;
    }

    // Host names / IPv4 / IPv6 only; nothing that ping could read as an option.
    function validHost(h) {
        let s = (h === undefined || h === null) ? "" : String(h).trim();
        return s.length > 0 && s.length <= 253 && /^[A-Za-z0-9][A-Za-z0-9.:\-]*$/.test(s);
    }

    function unregister(token) {
        if (!token || !_clients[token]) return;
        let c = Object.assign({}, _clients);
        delete c[token];
        _clients = c;
        _clientRev++;
    }

    readonly property int clientCount: { let r = _clientRev; return Object.keys(_clients).length; }
    readonly property bool active: clientCount > 0

    readonly property int interval: {
        let r = _clientRev;
        let best = 0;
        for (let k in _clients) {
            let v = _clients[k].interval;
            if (best === 0 || v < best) best = v;
        }
        return best > 0 ? best : 1000;
    }

    readonly property bool pingWanted: {
        let r = _clientRev;
        for (let k in _clients) if (_clients[k].ping) return true;
        return false;
    }

    readonly property string pingTarget: {
        let r = _clientRev;
        for (let k in _clients) if (_clients[k].ping && _clients[k].host) return _clients[k].host;
        return "1.1.1.1";
    }

    // ---- data ----------------------------------------------------------------
    // [{ name, type: "wifi"|"ethernet"|"other", rx, tx, rxTotal, txTotal }]
    property var interfaces: []
    property string defaultInterface: ""
    property var history: ({})          // name -> { rx: [...], tx: [...] } bytes/s
    readonly property int historyLength: 60
    property real latencyMs: -1         // -1: unknown / not measured
    property bool latencyFailed: false
    property bool ready: false

    property var _prev: ({})            // name -> { rx, tx, t }
    property var _wireless: ({})
    property string _routeIface: ""

    function _text(view) {
        try {
            return typeof view.text === "function" ? view.text() : (view.text || "");
        } catch (e) {
            return "";
        }
    }

    function _classify(name) {
        if (root._wireless[name]) return "wifi";
        if (/^(wl|wlan|ath|ra)/.test(name)) return "wifi";
        if (/^(en|eth|em|eno|ens|enp|usb)/.test(name)) return "ethernet";
        return "other";
    }

    function _parseWireless(text) {
        let w = {};
        let lines = String(text || "").split("\n");
        for (let i = 2; i < lines.length; i++) {
            let m = lines[i].match(/^\s*([^:\s]+):/);
            if (m) w[m[1]] = true;
        }
        root._wireless = w;
    }

    function _parseRoute(text) {
        let lines = String(text || "").split("\n");
        let best = "";
        let bestMetric = Infinity;
        for (let i = 1; i < lines.length; i++) {
            let f = lines[i].trim().split(/\s+/);
            if (f.length < 8) continue;
            // Destination 00000000 and the RTF_UP flag
            if (f[1] === "00000000" && (parseInt(f[3], 16) & 1)) {
                let metric = parseInt(f[6], 10) || 0;
                if (metric < bestMetric) {
                    bestMetric = metric;
                    best = f[0];
                }
            }
        }
        root._routeIface = best;
    }

    // Time of the last /proc/net/dev sample. A second read within 100 ms (the
    // initial FileView load right before the timer's first tick) would divide
    // by almost zero and show a huge spike, so it is ignored.
    property real _lastSample: 0

    function _parseDev(text) {
        let now = Date.now();
        if (root._lastSample > 0 && now - root._lastSample < 100) return;
        root._lastSample = now;
        let lines = String(text || "").split("\n");
        let list = [];
        let prev = root._prev;
        let next = {};
        let hist = Object.assign({}, root.history);
        for (let i = 2; i < lines.length; i++) {
            let line = lines[i];
            let colon = line.indexOf(":");
            if (colon < 0) continue;
            let name = line.substring(0, colon).trim();
            if (name === "" || name === "lo") continue;
            let f = line.substring(colon + 1).trim().split(/\s+/);
            if (f.length < 9) continue;
            let rxTotal = Number(f[0]) || 0;
            let txTotal = Number(f[8]) || 0;
            let rx = 0, tx = 0;
            let p = prev[name];
            if (p && now > p.t) {
                let dt = (now - p.t) / 1000;
                // counters can reset (interface re-created): never report negatives
                rx = rxTotal >= p.rx ? (rxTotal - p.rx) / dt : 0;
                tx = txTotal >= p.tx ? (txTotal - p.tx) / dt : 0;
            }
            next[name] = { rx: rxTotal, tx: txTotal, t: now };
            if (p) {
                let h = hist[name] ? { rx: hist[name].rx.slice(), tx: hist[name].tx.slice() } : { rx: [], tx: [] };
                h.rx.push(rx);
                h.tx.push(tx);
                while (h.rx.length > root.historyLength) h.rx.shift();
                while (h.tx.length > root.historyLength) h.tx.shift();
                hist[name] = h;
            }
            list.push({ name: name, type: root._classify(name), rx: rx, tx: tx, rxTotal: rxTotal, txTotal: txTotal });
        }
        root._prev = next;
        root.history = hist;
        root.interfaces = list;

        let def = root._routeIface;
        if (def === "" || !next[def]) {
            // no default route: the busiest wired/wireless interface
            let best = null;
            for (let it of list) {
                if (it.type === "other") continue;
                if (!best || it.rxTotal + it.txTotal > best.rxTotal + best.txTotal) best = it;
            }
            def = best ? best.name : (list.length > 0 ? list[0].name : "");
        }
        root.defaultInterface = def;
        root.ready = Object.keys(prev).length > 0;
    }

    // Resolve "auto" / "" / a name to the interface record (or a zero record).
    function stats(name) {
        let target = (!name || name === "auto") ? root.defaultInterface : name;
        for (let it of root.interfaces) {
            if (it.name === target) return it;
        }
        return { name: target || "", type: target ? root._classify(target) : "other", rx: 0, tx: 0, rxTotal: 0, txTotal: 0 };
    }

    function historyFor(name) {
        let target = (!name || name === "auto") ? root.defaultInterface : name;
        return root.history[target] || { rx: [], tx: [] };
    }

    function interfaceNames() {
        return root.interfaces.map(it => it.name);
    }

    // Next interface after `current` ("auto" is part of the cycle).
    function nextInterface(current) {
        let names = ["auto"].concat(interfaceNames());
        let i = names.indexOf(current || "auto");
        return names[(i + 1) % names.length];
    }

    function formatSpeed(bytesPerSec) {
        let v = Number(bytesPerSec) || 0;
        if (v < 1024) return Math.round(v) + " B/s";
        if (v < 1024 * 1024) return (v / 1024).toFixed(v < 10240 ? 1 : 0) + " KB/s";
        if (v < 1024 * 1024 * 1024) return (v / 1048576).toFixed(1) + " MB/s";
        return (v / 1073741824).toFixed(2) + " GB/s";
    }

    function formatShortSpeed(bytesPerSec) {
        let v = Number(bytesPerSec) || 0;
        if (v < 1024) return Math.round(v) + "B";
        if (v < 1024 * 1024) return (v / 1024).toFixed(v < 10240 ? 1 : 0) + "K";
        if (v < 1024 * 1024 * 1024) return (v / 1048576).toFixed(1) + "M";
        return (v / 1073741824).toFixed(1) + "G";
    }

    function formatBytes(bytes) {
        let v = Number(bytes) || 0;
        if (v < 1024) return Math.round(v) + " B";
        if (v < 1048576) return (v / 1024).toFixed(1) + " KB";
        if (v < 1073741824) return (v / 1048576).toFixed(1) + " MB";
        if (v < 1099511627776) return (v / 1073741824).toFixed(2) + " GB";
        return (v / 1099511627776).toFixed(2) + " TB";
    }

    function typeIcon(type) {
        if (type === "wifi") return "󰤨";
        if (type === "ethernet") return "󰈀";
        return "󰛳";
    }

    function typeLabel(type) {
        if (type === "wifi") return "Wi-Fi";
        if (type === "ethernet") return "Ethernet";
        return "Network";
    }

    // ---- sampling ---------------------------------------------------------------
    FileView { id: devFile; path: "/proc/net/dev"; printErrors: false; onLoaded: root._parseDev(root._text(devFile)) }
    FileView { id: routeFile; path: "/proc/net/route"; printErrors: false; onLoaded: root._parseRoute(root._text(routeFile)) }
    FileView { id: wirelessFile; path: "/proc/net/wireless"; printErrors: false; onLoaded: root._parseWireless(root._text(wirelessFile)) }

    property int _tick: 0

    Timer {
        id: sampler
        interval: root.interval
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            // route and Wi-Fi membership change rarely: every 5th sample
            if (root._tick % 5 === 0) {
                wirelessFile.reload();
                routeFile.reload();
            }
            root._tick++;
            devFile.reload();
        }
    }

    onActiveChanged: {
        if (!active) {
            root._lastSample = 0;
            root._prev = {};
            root.history = {};
            root.ready = false;
            root.latencyMs = -1;
        }
    }

    // ---- latency (opt-in) ---------------------------------------------------------
    Timer {
        interval: 5000
        repeat: true
        running: root.active && root.pingWanted
        triggeredOnStart: true
        onTriggered: if (!pingProc.running) pingProc.running = true
    }

    onPingWantedChanged: if (!pingWanted) { root.latencyMs = -1; root.latencyFailed = false; }

    Process {
        id: pingProc
        running: false
        // host comes from the user's own widget settings; passed as an argv
        // element, never through a shell
        command: ["ping", "-n", "-c", "1", "-W", "2", root.pingTarget]
        stdout: StdioCollector {
            onStreamFinished: {
                let m = String(this.text || "").match(/time[=<]([\d.]+)\s*ms/);
                if (m) {
                    root.latencyMs = parseFloat(m[1]);
                    root.latencyFailed = false;
                } else {
                    root.latencyMs = -1;
                    root.latencyFailed = true;
                }
            }
        }
    }
}
