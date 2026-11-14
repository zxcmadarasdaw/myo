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
    // Disconnect works otherwise; the VPN tab also shows it while a disconnect hangs)
    readonly property bool canForceOff: tunState === "failed" || tunState === "deactivating" || tunState === "activating"
    property bool forcing: false

    // ---- connection phase (VPN Control Studio) ---------------------------------------------
    // "connected" only after the backend confirmed it (sing-box answers on its control port);
    // between an action and the next status the phase stays "connecting"/"disconnecting".
    property string awaiting: ""              // "on" | "off": action done, status not read yet
    property string errorAction: ""           // action whose failure produced `error`
    readonly property string phase: {
        if (forcing) return "disconnecting";
        if (busy && (busyAction === "connect" || busyAction === "select" || busyAction === "mode")) return "connecting";
        if (busy && busyAction === "disconnect") return "disconnecting";
        if (awaiting === "on") return "connecting";
        if (awaiting === "off") return "disconnecting";
        if (vpnState === "connected") return "connected";
        if (vpnState === "error") return "error";
        if (error !== "" && ["connect", "select", "disconnect", "mode"].indexOf(errorAction) >= 0) return "error";
        return "disconnected";
    }
    readonly property bool canConnect: !busy && !forcing && hasSource && vpnState !== "missing" && servers.length > 0
    readonly property string subscriptionName: status.subscription || ""
    readonly property var lastUpdate: status.lastUpdate || ({})

    // ---- exit IP: checked through the VPN after it connects, only while the panel is open --
    property var exitIp: null                 // { ip, country, countryName, flag, time, server }
    property string ipState: ""               // "" | "checking" | "ok" | "failed"
    property string ipError: ""

    // ---- subscriptions -------------------------------------------------------------------
    property var subs: []                     // [{ id, name, kind, host|count, active, lastUpdate }]
    property string activeSub: ""

    // ---- sing-box --------------------------------------------------------------------------
    property var sbInfo: ({})                 // singbox-info: path, source, version, works, candidates
    property bool sbInstalling: false
    property bool sbCancelled: false
    property string sbStage: ""               // release | download | verify | extract | test | done
    property real sbDone: 0
    property real sbTotal: 0
    property real sbSpeed: 0
    property int sbAttempt: 0
    property string sbVersion: ""
    property bool sbChecksum: false
    property string sbError: ""
    property var sbResult: null               // last successful install

    function start() {
        if (started) return;
        started = true;
        refresh();
        loadSubs();
        run("update", ["--auto"], "");
    }

    // A status that was already running when an action finished describes the time before
    // it: it is followed by a fresh one, and only a fresh one may end the "awaiting" phase.
    property int actionSeq: 0
    property bool refreshQueued: false
    function refresh() {
        if (!started) return;
        if (statusProc.running) {
            refreshQueued = true;
            return;
        }
        statusProc.seq = actionSeq;
        statusProc.running = true;
    }

    // ---- actions (one at a time) --------------------------------------------------------

    function run(action, args, input) {
        if (actionProc.running) return false;
        error = "";
        errorAction = "";
        awaiting = "";
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
        ipState = "";                  // first: bindings see "ok" only together with an exitIp
        exitIp = null;                 // the old address no longer applies
        run("select", [tag], "");
    }

    function checkIp() {
        if (!connected || !panelOpen || ipProc.running) return;
        ipState = "checking";
        ipError = "";
        ipProc.running = true;
    }

    // ---- subscriptions (the link goes on stdin, never into argv) ----------------------------
    function loadSubs() {
        if (started && !subsProc.running) subsProc.running = true;
    }
    function addSub(link, name) {
        let t = (link || "").trim();
        if (t === "") {
            error = I18n.t("vpn.errors.empty_link", "Paste a subscription link first.");
            return false;
        }
        let n = (name || "").trim();
        return run("sub-add", n !== "" ? ["--name=" + n] : [], t);
    }
    function useSub(id) { if (id && id !== activeSub) run("sub-use", [id], ""); }
    function renameSub(id, name) { if (id && (name || "").trim() !== "") run("sub-rename", [id, name.trim()], ""); }
    function removeSub(id) { if (id) run("sub-remove", [id], ""); }

    // ---- sing-box ------------------------------------------------------------------------
    function singboxInfo() {
        if (!sbInfoProc.running) sbInfoProc.running = true;
    }
    function installSingbox() {
        if (sbProc.running) return;
        sbCancelled = false;
        sbError = "";
        sbResult = null;
        sbStage = "release";
        sbDone = 0; sbTotal = 0; sbSpeed = 0; sbAttempt = 1;
        sbInstalling = true;
        sbProc.running = true;
    }
    function cancelInstall() {
        if (!sbProc.running) return;
        sbCancelled = true;
        sbProc.running = false;        // SIGTERM: the script removes its partial download
    }
    function useSingbox(path) { run("singbox-use", [path || ""], ""); }

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
                map[key] = { code: key, name: s.countryName || key || I18n.t("vpn.unknown_country", "Unknown"),
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
                    root.errorAction = actionProc.action;
                    root.pendingConnect = false;
                } else if (d.restartError) {
                    root.error = d.restartError;
                    root.errorAction = actionProc.action;
                } else if (d.updateError) {
                    root.error = d.updateError;
                    root.errorAction = actionProc.action;
                }
                if (d.items !== undefined && Array.isArray(d.items)) {
                    root.subs = d.items;
                    root.activeSub = d.active || "";
                }
            }
        }
        onExited: (code) => {
            let action = actionProc.action;
            root.actionSeq++;
            root.busy = false;
            root.busyAction = "";
            if (code > 2 && root.error === "" && !root.forcing) {    // killed by forceOff(): not an error
                root.error = I18n.t("vpn.errors.backend", "The VPN helper failed (is python3 installed?).");
                root.errorAction = action;
            }
            let again = action === "select" && root.pendingConnect && root.error === "";
            root.pendingConnect = false;
            if (again) {
                root.connect();
                return;
            }
            if (root.error === "") {
                if (action === "connect" || action === "select" || (action === "mode" && root.connected)) root.awaiting = "on";
                else if (action === "disconnect") root.awaiting = "off";
                if (awaitTimeout.running || root.awaiting !== "") awaitTimeout.restart();
                if (action === "select" && root.connected) ipDelay.restart();
            }
            root.refresh();
            if (action !== "select" && action !== "connect" && action !== "disconnect")
                listProc.running = true;
            if (action.indexOf("sub-") === 0 || action === "update" || action === "set-source") root.loadSubs();
            if (action === "singbox-use") root.singboxInfo();
        }
    }

    // A status that never arrives must not leave the button spinning.
    Timer {
        id: awaitTimeout
        interval: 8000
        onTriggered: root.awaiting = ""
    }

    Timer {
        id: ipDelay
        interval: 700
        onTriggered: root.checkIp()
    }

    Process {
        id: ipProc
        command: ["python3", root.script, "ipcheck", "--json"]
        environment: root.procEnv
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.parseLast(this.text);
                if (d && d.ok !== false && d.ip) {
                    root.exitIp = d;
                    root.ipState = "ok";
                } else {
                    root.exitIp = null;
                    root.ipState = root.connected ? "failed" : "";
                    root.ipError = d && d.error ? (d.error.message || "") : "";
                }
            }
        }
        onExited: if (root.ipState === "checking") root.ipState = root.connected ? "failed" : ""
    }

    Process {
        id: subsProc
        command: ["python3", root.script, "subs", "--json"]
        environment: root.procEnv
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.parseLast(this.text);
                if (d && Array.isArray(d.items)) {
                    root.subs = d.items;
                    root.activeSub = d.active || "";
                }
            }
        }
    }

    Process {
        id: sbInfoProc
        command: ["python3", root.script, "singbox-info", "--json"]
        environment: root.procEnv
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.parseLast(this.text);
                if (d && d.ok !== false) root.sbInfo = d;
            }
        }
    }

    // Live progress: one JSON object per line (stage / progress / retry), the result last.
    Process {
        id: sbProc
        command: ["python3", root.script, "singbox-install", "--json"]
        environment: root.procEnv
        stdout: SplitParser {
            onRead: (line) => {
                let e;
                try { e = JSON.parse(line); } catch (err) { return; }
                if (e.event === "stage") {
                    root.sbStage = e.stage || "";
                    if (e.version) root.sbVersion = e.version;
                    if (e.total) root.sbTotal = e.total;
                    if (e.checksum !== undefined) root.sbChecksum = e.checksum === true;
                } else if (e.event === "progress") {
                    root.sbDone = e.done || 0;
                    if (e.total) root.sbTotal = e.total;
                    root.sbSpeed = e.speed || 0;
                    root.sbAttempt = e.attempt || root.sbAttempt;
                } else if (e.event === "retry") {
                    root.sbAttempt = e.attempt || root.sbAttempt;
                    root.sbSpeed = 0;
                } else if (e.ok === true && e.path) {
                    root.sbResult = e;
                    root.sbStage = "done";
                } else if (e.ok === false && e.error) {
                    root.sbError = e.error.message || e.error.code || "";
                }
            }
        }
        onExited: (code) => {
            root.sbInstalling = false;
            if (root.sbCancelled) {
                root.sbError = I18n.t("vpn.singbox.cancelled", "Download cancelled. Nothing was installed.");
                root.sbStage = "";
            } else if (!root.sbResult && root.sbError === "") {
                root.sbError = I18n.t("vpn.errors.backend", "The VPN helper failed (is python3 installed?).");
            }
            root.refresh();
            root.singboxInfo();
        }
    }

    Process {
        id: statusProc
        property int seq: 0
        command: ["python3", root.script, "status", "--json"]
        environment: root.procEnv
        onExited: {
            if (root.refreshQueued) {
                root.refreshQueued = false;
                Qt.callLater(root.refresh);
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let d = root.parseLast(this.text);
                if (!d || d.ok === false) return;
                root.status = d;
                root.vpnState = d.state || "";
                if (!root.busy && statusProc.seq === root.actionSeq) {
                    root.awaiting = "";
                    awaitTimeout.stop();
                }
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
            if (connected && exitIp === null) ipDelay.restart();
        } else {
            stopPing();
        }
    }
    onConnectedChanged: {
        if (connected) {
            ipDelay.restart();
        } else {
            ipDelay.stop();
            if (ipProc.running) ipProc.running = false;
            ipState = "";
            exitIp = null;
            ipError = "";
        }
    }
    onServersChanged: if (panelOpen && servers.length > 0 && Object.keys(delays).length === 0) ping()
}
