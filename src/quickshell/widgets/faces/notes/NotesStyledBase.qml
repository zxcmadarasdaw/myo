import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../../../"
import "../../../quickactions/actions/NotesFormat.js" as NotesFormat

// Shared data of the Restrained and Lush notes faces: the quick actions notes
// (read-only here), pinned notes first. Clicking opens the notes panel.
Item {
    id: base
    anchors.fill: parent

    property bool previewMode: false
    property real minWidth: 200
    property real minHeight: 140
    property real maxWidth: 700
    property real maxHeight: 800
    property real minAspect: 0.4
    property real maxAspect: 3.0
    property bool isRound: false

    property var notesList: []
    property bool fileLoaded: false

    readonly property var generalSettings: Config.getSetting("general", {})
    readonly property bool quickactionsAvailable: generalSettings.quickactions !== false && !generalSettings.performance

    readonly property var sortedNotes: {
        let raw = base.notesList || [];
        let pinned = raw.filter(n => n.pinned);
        let rest = raw.filter(n => !n.pinned);
        return pinned.concat(rest);
    }

    // re-evaluated every 30 s so "5 min ago" stays true
    property real now: Date.now()
    Timer { interval: 30000; running: base.visible; repeat: true; onTriggered: base.now = Date.now() }

    function relativeTime(ts) {
        let dummy = base.now;
        let fmt = (Config.rawSettings && Config.rawSettings.bar && Config.rawSettings.bar.time && Config.rawSettings.bar.time.format !== undefined)
            ? Config.rawSettings.bar.time.format : "HH:mm";
        return NotesFormat.formatRelativeTime(ts, I18n, fmt);
    }

    function snippet(note) {
        let s = String(note && note.content ? note.content : "").replace(/\s+/g, " ").trim();
        return s.length > 140 ? s.slice(0, 140) + "…" : s;
    }

    function parseNotes(rawText) {
        let txt = (rawText || "").trim();
        if (txt === "") { base.notesList = []; return; }
        try {
            let data = JSON.parse(txt);
            if (Array.isArray(data)) base.notesList = data.filter(n => n && n.id !== undefined);
        } catch (e) {}
    }

    function openNotes() {
        if (base.previewMode || !base.quickactionsAvailable) return;
        FloatingController.showNotes(base.Window.window ? base.Window.window.screen : null);
    }

    FileView {
        path: Caching.stateDir + "/quickactions/notes.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            base.fileLoaded = true;
            base.parseNotes(typeof text === "function" ? text() : text);
        }
        onLoadFailed: base.fileLoaded = false
    }
}
