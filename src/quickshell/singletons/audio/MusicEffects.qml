pragma Singleton
import QtQuick
import Quickshell.Io
import "../../"

Item {
    id: root
    visible: false
    property var eqState: ({ b1:0, b2:0, b3:0, b4:0, b5:0, b6:0, b7:0, b8:0, b9:0, b10:0,
        preset:"Flat", pending:false, balance:0, mono:false, swap:false, dyneq:false, dynamics:"off", effects:true })
    property var presets: []
    property bool available: false
    property string error: "Проверка аудиодвижка…"
    property string notice: ""
    property int consumers: 0
    property var queue: []
    property var current: []
    signal applied(string command)
    readonly property bool busy: worker.running || queue.length > 0
    function register() { consumers++; refresh(); }
    function unregister() { consumers = Math.max(0, consumers - 1); }
    function refresh() {
        if (!busy) { queue = [["status"]]; pump.start(); }
    }
    function command(args) {
        if (!available && args[0] !== "save_preset") return;
        args = args.map(String);
        let pending = queue.slice();
        // Coalesce a dragged control, while preserving order between different controls.
        let last = pending.length ? pending[pending.length - 1] : null;
        if (last && args[0].startsWith("set_") && last[0] === args[0]
            && (args[0] !== "set_band" && args[0] !== "set_tone" || last[1] === args[1])) pending.pop();
        pending.push(args);
        queue = pending;
        notice = "";
        pump.restart();
    }
    function finish(code, text, stderr) {
        watchdog.stop();

        try {
            let response = JSON.parse(text);
            root.available = response.available === true;
            root.error = response.error || "";
            if (response.ok && code === 0) {
                if (response.state) root.eqState = response.state;
                if (response.presets) root.presets = response.presets;
                if (root.current[0] === "save_preset") root.notice = "Пресет сохранён";
                root.applied(root.current[0]);
            } else { root.queue = []; }
        } catch (e) {
            root.available = false;
            root.error = "Не удалось запустить аудиокомпонент. Нужны python3 и serpantinum-audio. " + stderr.slice(0,180);
            root.queue = [];
        }
        if (root.queue.length) pump.restart();
    }
    Timer {
        id: watchdog
        interval: 8000
        onTriggered: {
            root.available = false;
            root.error = "Аудиокомпонент не ответил. Проверьте python3, serpantinum-audio и PipeWire.";
            root.queue = [];
            worker.running = false;
        }
    }
    Timer {
        id: pump
        interval: 40
        onTriggered: {
            if (worker.running || !root.queue.length) return;
            let pending = root.queue.slice();
            root.current = pending.shift();
            root.queue = pending;
            worker.command = ["python3", Caching.qsDir + "/media/equalizer.py"].concat(root.current);
            watchdog.restart();
            worker.running = true;
        }
    }
    Timer { interval: 4000; running: root.consumers > 0; repeat: true; onTriggered: root.refresh() }
    Process {
        id: worker
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: errors }
        onExited: (code) => Qt.callLater(() => root.finish(code, output.text, errors.text))
    }
}
