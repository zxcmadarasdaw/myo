pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// VPN subscription client: stage 1 local proxy through sing-box (no root),
// stage 2 TUN mode through the serpantinum-vpn system service.
// All work is done by scripts/system/serp_vpn.py. The subscription link is
// handed to it on stdin only: never in a command line and never logged here.
Item {
    id: root
    visible: false

    readonly property string script: Caching.serpantinumDir + "/scripts/system/serp_vpn.py"
    readonly property var procEnv: ({ "SERP_VPN_LANG": I18n.currentLang })
    property bool started: false

    // "" (unknown yet) | "none" | "disconnected" | "connected" | "error" | "missing"
    property string vpnState: ""
    property var status: ({})
    property var servers: []
    property var delays: ({})
    property string current: ""
    property string error: ""          // user-facing text of the last failed action
    property bool busy: false
    property string busyAction: ""
    property bool pinging: false
    property bool panelOpen: false     // set by the network panel: pings run only while it is open
    property bool pendingConnect: false

    readonly property bool connected: vpnState === "connected"
    readonly property bool hasSource: status.hasSource === true
    readonly property var currentServer: status.currentServer || null
    readonly property string proxy: status.proxy || "127.0.0.1:2080"
    readonly property string installHint: status.installHint || "sudo dnf install sing-box"
    readonly property int currentDelay: (current !== "" && delays[current] !== undefined) ? delays[current] : -1
    readonly property string warning: status.warning || ""
    readonly property var countries: groupCountries(servers, delays)

    // Stage 2: TUN mode through the serpantinum-vpn system service (root helper via pkexec,
    // allowed by the installer's polkit rule; nothing here uses sudo).
    readonly property string mode: status.mode || "proxy"            // "proxy" | "tun"
    readonly property bool tunInstalled: status.tunInstalled === true
    readonly property string tunState: status.tunState || ""
    readonly property var checks: status.checks || []
    readonly property bool hasConflict: checks.some(c => c.level === "warn")
    // the emergency off is offered when the service is stuck or failed (a normal
    // Disconnect works otherwise; VpnBlock also shows it while a disconnect hangs)
    readonly property bool canForceOff: tunState === "failed" || tunState === "deactivating" || tunState === "activating"
    property bool forcing: false

    function start() {
        if (started) return;
        started = true;
        refresh();
        run("update", ["--auto"], "");
    }

    function refresh() {
        if (!started || statusProc.running) return;
        statusProc.running = true;
    }

    // ---- actions (one at a time) --------------------------------------------------------

    function run(action, args, input) {
        if (actionProc.running) return false;
        error = "";
        busy = true;
        busyAction = action;
        actionProc.action = action;
        actionProc.input = input || "";
        actionProc.command = ["python3", script, action].concat(args || []).concat(["--json"]);
        actionProc.stdinEnabled = true;
        actionProc.running = true;
        return true;
    }

    function setSource(text) {
        let t = (text || "").trim();
        if (t === "") {
            error = I18n.t("vpn.errors.empty_link", "Paste a subscription link first.");
            return;
        }
        run("set-source", [], t);
    }

    function update() { run("update", [], ""); }
    function connect() { run("connect", [], ""); }
    function disconnect() { run("disconnect", [], ""); }
    function toggle() { connected ? disconnect() : connect(); }
    function forget() { run("clear", [], ""); }
    function setMode(m) {
        if (m === mode || busy) return;
        run("mode", [m], "");
    }

    // Emergency off: works even while another action hangs (it is stopped first).
    function forceOff() {
        if (forceProc.running) return;
        if (actionProc.running) actionProc.running = false;
        stopPing();
        error = "";
        forcing = true;
        forceProc.running = true;
    }

    // Choosing a server switches the connection; when disconnected it also connects.
    function select(tag) {
        if (!tag || busy) return;
        current = tag;                 // immediate feedback; status confirms
        pendingConnect = !connected;
        run("select", [tag], "");
    }

    function ping() {
        if (pingProc.running || !panelOpen || servers.length === 0) return;
        if (vpnState === "missing" || vpnState === "none") return;
        pinging = true;
        pingProc.running = true;
    }

    function stopPing() {
        if (pingProc.running) pingProc.running = false;   // SIGTERM: the script stops its probe
        pinging = false;
    }

    function copyText(text) {
        if (text) Quickshell.execDetached(["wl-copy", "--", text]);
    }

    function groupCountries(list, d) {
        let map = {};
        let order = [];
        for (let i = 0; i < list.length; i++) {
            let s = list[i];
            let key = s.country || "";
            if (!map[key]) {
                map[key] = { code: key, name: s.countryName || key || I18n.t("vpn.other_country", "Other"),
                             flag: s.flag || "", servers: [], best: -1 };
                order.push(key);
            }
            map[key].servers.push(s);
            let v = d[s.tag];
            if (v > 0 && (map[key].best < 0 || v < map[key].best)) map[key].best = v;
        }
        order.sort((a, b) => {
            if (a === "") return 1;
            if (b === "") return -1;
            return map[a].name.localeCompare(map[b].name);
        });
        return order.map(k => map[k]);
    }

    function parseLast(text) {
        let lines = (text || "").trim().split("\n");
        try { return JSON.parse(lines[lines.length - 1]); } catch (e) { return null; }
    }

    // ---- processes ---------------------------------------------------------------------

    Process {
        id: actionProc
        property string action: ""
        property string input: ""
        environment: root.procEnv
        onStarted: {
            if (actionProc.input !== "") actionProc.write(actionProc.input + "\n");
            actionProc.input = "";
            actionProc.stdinEnabled = false;          // EOF for the script
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.parseLast(this.text);
                if (!d) return;
                if (d.ok === false && d.error) {
                    root.error = d.error.message || d.error.code || "";
                    root.pendingConnect = false;
                } else if (d.restartError) {
                    root.error = d.restartError;
                }
            }
        }
        onExited: (code) => {
            root.busy = false;
            root.busyAction = "";
            if (code > 2 && root.error === "" && !root.forcing)     // killed by forceOff(): not an error
                root.error = I18n.t("vpn.errors.backend", "The VPN helper failed (is python3 installed?).");
            let again = actionProc.action === "select" && root.pendingConnect && root.error === "";
            root.pendingConnect = false;
            if (again) {
                root.connect();
                return;
            }
            root.refresh();
            if (actionProc.action !== "select" && actionProc.action !== "connect" && actionProc.action !== "disconnect")
                listProc.running = true;
        }
    }

    Process {
        id: statusProc
        command: ["python3", root.script, "status", "--json"]
        environment: root.procEnv
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.parseLast(this.text);
                if (!d || d.ok === false) return;
                root.status = d;
                root.vpnState = d.state || "";
                if (d.current && !root.busy) root.current = d.current;
                if (d.delays && Object.keys(d.delays).length > 0 && !root.pinging) root.delays = d.delays;
                if (d.count !== root.servers.length && !listProc.running) listProc.running = true;
            }
        }
    }

    Process {
        id: forceProc
        command: ["python3", root.script, "force-off", "--json"]
        environment: root.procEnv
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.parseLast(this.text);
                if (d && d.error) root.error = (typeof d.error === "string") ? d.error : (d.error.message || "");
            }
        }
        onExited: {
            root.forcing = false;
            root.busy = false;
            root.busyAction = "";
            root.refresh();
        }
    }

    Process {
        id: listProc
        command: ["python3", root.script, "list", "--json"]
        environment: root.procEnv
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.parseLast(this.text);
                if (d && d.servers) root.servers = d.servers;
            }
        }
    }

    Process {
        id: pingProc
        command: ["python3", root.script, "ping", "--json"]
        environment: root.procEnv
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.parseLast(this.text);
                if (d && d.delays) root.delays = d.delays;
                else if (d && d.ok === false && d.error && root.panelOpen) root.error = d.error.message || "";
            }
        }
        onExited: root.pinging = false
    }

    // ---- timers ------------------------------------------------------------------------

    // Checked every 30 minutes; the script updates only when the configured interval
    // (default 12 h) has passed, and keeps the old config when an update fails.
    Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: root.started
        onTriggered: root.run("update", ["--auto"], "")
    }

    // Only while the panel is open: status every 4 s, ping every 60 s.
    Timer {
        interval: 4000
        repeat: true
        running: root.started && root.panelOpen
        onTriggered: root.refresh()
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.started && root.panelOpen
        triggeredOnStart: true
        onTriggered: root.ping()
    }

    onPanelOpenChanged: {
        if (panelOpen) {
            refresh();
            if (servers.length === 0 && started) listProc.running = true;
        } else {
            stopPing();
        }
    }
    onServersChanged: if (panelOpen && servers.length > 0 && Object.keys(delays).length === 0) ping()
}
