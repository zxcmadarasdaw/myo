pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

// Search Wallpapers (Settings -> Search Wallpapers): state and backend runner.
//
// Lives in a singleton because guide tabs are unloaded the moment you switch
// away: the query, the loaded results and a running download survive a tab
// switch or closing the settings window. All network, file and media work runs
// in scripts/wallpaper/wallhub.py (one process per job, never in the UI
// thread). Applying goes through Wallpaper.setWallpaper(), so GIF/video
// playback, transitions, scaling, wallpaper audio, per-monitor wallpapers and
// persistence stay in the existing WallpaperEngine.
Item {
    id: root

    function tr(en, ru) { return I18n.currentLang === "ru" ? ru : en; }

    readonly property string script: Caching.serpantinumDir + "/scripts/wallpaper/wallhub.py"
    readonly property string wallpaperDir: Config.getSetting("wallpaperDir", "") || Config.getSetting("wallpaper_dir", "") || Quickshell.env("WALLPAPER_DIR") || (Quickshell.env("HOME") + "/Pictures/Wallpapers")
    // Kept as "Wallpaper Hub" so files downloaded before the redesign stay in the library.
    readonly property string downloadDir: wallpaperDir + "/Wallpaper Hub"
    readonly property string editedDir: downloadDir + "/Edited"

    // ------------------------------------------------------------------ preferences
    readonly property var sourceNames: ["brave", "sepia", "wallhaven", "commons", "openverse", "pexels", "pixabay", "giphy", "steam", "local", "links"]
    readonly property var resOptions: ["auto", "any", "1080p", "1440p", "4k", "8k"]
    readonly property var sortOptions: ["relevance", "resolution", "newest", "popular"]
    readonly property var defaults: ({
        minRes: "auto", sort: "relevance", translate: true, safe: true, remember: true, gallery: false,
        maxDownloadMb: 400, minBitrateMbps: 0, hideUpscales: false, knownOnly: false, includeUnknown: true, sourceMode: "all",
        sources: { brave: true, sepia: true, wallhaven: true, commons: true, openverse: true, pexels: true, pixabay: true,
                   giphy: true, steam: true, local: true, links: false }
    })
    property var prefs: loadPrefs()

    function loadPrefs() {
        // Settings of the old Wallpaper Hub page are taken over once.
        let saved = Config.getSetting("wallpaperSearch", null) || Config.getSetting("wallpaperHub", {}) || {};
        let p = Object.assign({}, defaults, saved);
        p.sources = Object.assign({}, defaults.sources, saved.sources || {});
        if (resOptions.indexOf(p.minRes) < 0) p.minRes = "auto";
        if (sortOptions.indexOf(p.sort) < 0) p.sort = "relevance";
        if (p.sourceMode !== "all" && (!sourceNames.includes(p.sourceMode) || p.sources[p.sourceMode] === false)) p.sourceMode = "all";
        return p;
    }
    function setPref(key, value) {
        let p = JSON.parse(JSON.stringify(prefs));
        p[key] = value;
        prefs = p;
        Config.setSetting("wallpaperSearch", p);
    }
    function setSourceEnabled(name, on) {
        let src = Object.assign({}, prefs.sources);
        src[name] = on;
        setPref("sources", src);
        if (!on && prefs.sourceMode === name) setPref("sourceMode", "all");
        refresh();
    }
    function enabledSources() {
        return sourceNames.filter(k => prefs.sources[k] !== false && (prefs.sourceMode === "all" ? k !== "giphy" : prefs.sourceMode === k)).join(",");
    }
    Connections {
        target: Config
        function onSettingsLoaded() { root.prefs = root.loadPrefs(); }
    }

    // "Auto" picks the class of the largest connected monitor (physical pixels).
    readonly property string autoRes: {
        let big = 0, small = 0;
        for (let sc of Quickshell.screens) {
            let dpr = sc.devicePixelRatio || 1;
            let w = Math.round(sc.width * dpr), h = Math.round(sc.height * dpr);
            if (Math.max(w, h) * Math.min(w, h) > big * small) { big = Math.max(w, h); small = Math.min(w, h); }
        }
        if (big >= 7680 && small >= 4320) return "8k";
        if (big >= 3840 && small >= 2160) return "4k";
        if (big >= 2560 && small >= 1440) return "1440p";
        return "1080p";
    }
    readonly property string effectiveMinRes: prefs.minRes === "auto" ? autoRes : prefs.minRes

    // ------------------------------------------------------------------ search session
    property string query: ""
    property string kind: "all"              // all | image | animated | video
    property int page: 1
    property bool searching: false
    property bool hasMore: false
    property string translated: ""
    property string translateError: ""
    property string lastError: ""
    property var plan: []                    // per-source plan from the backend (skips with reasons)
    property var statusBySource: ({})        // source -> last status
    property var byId: ({})                  // result id -> result (filled before rows are added)
    property var segments: []                // one per loaded page: { page, batches: [{ source, ids }] }
    property var searchProc: null
    property var sourcePages: ({})
    property int searchSerial: 0
    property alias results: resultsModel     // rows: { rid }
    ListModel { id: resultsModel }

    property bool offline: false
    property bool onlineKnown: false
    property string offlineDetail: ""
    property var keys: ({})
    property var caps: ({})
    property var customSources: ({ folders: [], urls: [] })
    property var sourceChecks: ({})
    readonly property bool checkingSource: checkProc.running
    readonly property bool editingSources: customProc.running
    readonly property string resolvingPeer: peerProc.running ? peerProc.resultId : ""
    property var peerMedia: ({})
    property var nextPeer: null
    property bool ffmpegOk: true
    property var history: []

    property var library: []
    property var downloaded: ({})            // result id -> local path
    property var downloadDenied: ({})
    property var favorites: ({})
    readonly property bool favoriteBusy: favoriteProc.running
    property var preparedAnimations: ({})
    property var probed: ({})                // result id or path -> measured media info
    property var qualityById: ({})           // result id or path -> quality report
    property string monitor: "all"
    property string pendingEdit: ""           // a path to open in Wallpaper Studio once the tab is visible

    property string toast: ""
    function notify(msg) { toast = msg; toastTimer.restart(); }
    Timer { id: toastTimer; interval: 6000; onTriggered: root.toast = "" }

    function search(text) {
        let q = (text || "").trim();
        if (q === "") return;
        query = q;
        page = 1;
        resetResults();
        runSearch();
        if (prefs.remember) history = [q].concat(history.filter(x => x.toLowerCase() !== q.toLowerCase())).slice(0, 25);
    }
    // Filters changed: run the same query again from page 1.
    function refresh() {
        if (query === "") return;
        page = 1;
        resetResults();
        runSearch();
    }
    function loadMore() {
        if (searching || !hasMore || query === "") return;
        page += 1;
        runSearch();
    }
    function setKind(k) {
        if (kind === k) return;
        kind = k;
        refresh();
    }
    function setFilter(key, value) {
        if (prefs[key] === value) return;
        setPref(key, value);
        refresh();
    }
    function searchWithoutTranslation() {
        setPref("translate", false);
        refresh();
    }
    function resetResults() {
        cancelSearch();
        resultsModel.clear();
        byId = {};
        downloadDenied = {};
        peerMedia = {};
        nextPeer = null;
        segments = [];
        statusBySource = {};
        sourcePages = {};
        plan = [];
        translated = "";
        translateError = "";
        lastError = "";
        hasMore = false;
    }
    function cancelSearch() {
        searchTimeout.stop();
        if (searchProc) {
            let p = searchProc;
            searchProc = null;
            p.running = false;
            Qt.callLater(() => p.destroy());
        }
        searching = false;
    }
    function runSearch() {
        cancelSearch();
        let cmd = ["python3", script, "search", "--query", query, "--page", String(page), "--kind", kind,
                   "--min", effectiveMinRes, "--sort", prefs.sourceMode === "giphy" ? "relevance" : prefs.sort,
                   "--translate", prefs.translate ? "auto" : "off",
                   "--sources", enabledSources()];
        for (const dir of [downloadDir, wallpaperDir]) cmd.push("--dir", dir);
        if (!prefs.safe) cmd.push("--unsafe");
        if (prefs.includeUnknown) cmd.push("--include-unknown");
        if (page > 1) cmd.push("--source-pages", JSON.stringify(sourcePages));
        if (prefs.remember && page === 1) cmd.push("--remember");
        segments = segments.concat([{ page: page, batches: [] }]);
        searching = true;
        lastError = "";
        searchSerial++;
        let p = searchComp.createObject(root, { command: cmd, serial: searchSerial });
        searchProc = p;
        p.running = true;
        searchTimeout.restart();
    }
    Timer {
        id: searchTimeout
        interval: 120000
        onTriggered: {
            root.cancelSearch();
            root.hasMore = Object.keys(root.sourcePages).length > 0;
            root.lastError = root.tr("The search timed out.", "Истекло время ожидания поиска.");
        }
    }

    Component {
        id: searchComp
        Process {
            id: sp
            property int serial: 0
            property bool finished: false
            stdout: SplitParser { onRead: (line) => root.onSearchLine(sp, line) }
            onExited: (code) => root.onSearchExit(sp, code)
        }
    }

    function onSearchLine(p, line) {
        if (p !== searchProc) return;            // a cancelled search: ignore what it still prints
        let d = null;
        try { d = JSON.parse(line); } catch (e) { return; }
        if (d.event === "start") {
            translated = d.translated || "";
            translateError = d.translateError || "";
            if (d.page === 1) {
                plan = d.sources || [];
                let st = {};
                for (let s of plan) if (s.skipped) st[s.source] = { source: s.source, skipped: s.skipped, skipCode: s.skipCode, count: 0 };
                statusBySource = st;
            }
        } else if (d.event === "source") {
            let st = Object.assign({}, statusBySource);
            st[d.source] = d.status;
            statusBySource = st;
            let cursors = Object.assign({}, sourcePages);
            if (d.status.hasMore) cursors[d.source] = d.status.page + 1;
            else if (!d.status.error) delete cursors[d.source];
            sourcePages = cursors;
            let ids = [], thumbs = [];
            for (let r of d.results || []) {
                if (byId[r.id]) continue;            // the same file on two pages
                byId[r.id] = r;
                ids.push(r.id);
                if (r.source !== "giphy" && r.thumb && !r.thumbCached) thumbs.push(r.thumb);
            }
            let seg = segments[segments.length - 1];
            seg.batches.push({ source: d.source, ids: ids, error: d.status.error || "" });
            layoutLastSegment();
            if (thumbs.length) queueThumbs(thumbs);
        } else if (d.event === "done") {
            p.finished = true;
            searchTimeout.stop();
            searching = false;
            if (!d.ok) {
                if (!retryPageLater(d.error || "")) lastError = d.error || tr("search failed", "поиск не удался");
                return;
            }
            onlineKnown = true;
            offline = !!d.offline;
            if (offline) refreshLibrary();
            if (retryPageLater("")) return;
            hasMore = Object.keys(sourcePages).length > 0;
        }
    }
    // A further page that brought nothing because its sources failed (rate limit,
    // network) is not skipped: the page number goes back so the next scroll asks again.
    function retryPageLater(error) {
        let seg = segments[segments.length - 1];
        if (page <= 1 || !seg || seg.page !== page) return false;
        let got = 0;
        for (let b of seg.batches) got += b.ids.length;
        let errs = seg.batches.map(b => b.error).filter(Boolean);
        if (got > 0 || (error === "" && errs.length === 0)) return false;
        segments = segments.slice(0, -1);
        page -= 1;
        hasMore = true;
        notify(tr("Could not load more results: ", "Не удалось загрузить ещё: ") + (error || errs[0]) + tr(". Scroll again to retry.", ". Прокрутите ещё раз, чтобы повторить."));
        return true;
    }
    function onSearchExit(p, code) {
        if (p !== searchProc) return;
        searchTimeout.stop();
        searching = false;
        if (!p.finished) {
            lastError = tr("The search helper stopped unexpectedly (exit code ", "Поисковый процесс неожиданно завершился (код ") + code + ").";
        }
        searchProc = null;
        Qt.callLater(() => p.destroy());
    }

    // Each page keeps its own rows; only the page that is still loading is re-laid
    // out, so rows the user already scrolled past never move.
    function orderSegment(seg) {
        let ids = [];
        if (prefs.sort === "resolution" && prefs.sourceMode !== "giphy") {
            for (let b of seg.batches) ids = ids.concat(b.ids);
            ids.sort((a, b) => area(byId[b]) - area(byId[a]));
        } else {
            // Interleave sources so one provider does not bury the others.
            let i = 0, more = true;
            while (more) {
                more = false;
                for (let b of seg.batches) {
                    if (i < b.ids.length) { ids.push(b.ids[i]); more = true; }
                }
                i++;
            }
        }
        return ids.filter(id => passes(byId[id]));
    }
    function area(r) { return r && r.width && r.height ? r.width * r.height : 0; }
    function layoutLastSegment() {
        let start = 0;
        for (let i = 0; i < segments.length - 1; i++) start += orderSegment(segments[i]).length;
        let ids = orderSegment(segments[segments.length - 1]);
        if (resultsModel.count > start) resultsModel.remove(start, resultsModel.count - start);
        for (let id of ids) resultsModel.append({ rid: id });
    }
    function rebuild() {
        resultsModel.clear();
        for (let seg of segments) for (let id of orderSegment(seg)) resultsModel.append({ rid: id });
    }
    // Local filters of the Original Quality Checker (all off by default).
    function passes(r) {
        if (r && r.source === "giphy") return true;
        if (!r) return false;
        let q = qualityById[r.id] || r.quality;
        if (prefs.hideUpscales && q && q.verdict === "upscale") return false;
        if (prefs.knownOnly && !r.qualityKnown) return false;
        let minBps = (prefs.minBitrateMbps || 0) * 1000000;
        if (minBps > 0 && r.kind === "video") {
            if (r.bitrate > 0 && r.bitrate < minBps) return false;
            if (!r.bitrate && prefs.knownOnly) return false;
        }
        return true;
    }
    function setLocalFilter(key, value) {
        setPref(key, value);
        rebuild();
    }

    // ------------------------------------------------------------------ thumbnails
    property var thumbQueue: []
    function queueThumbs(urls) {
        thumbQueue = thumbQueue.concat(urls);
        pumpThumbs();
    }
    function pumpThumbs() {
        if (thumbProc.running || thumbQueue.length === 0) return;
        thumbProc.pending = JSON.stringify(thumbQueue.slice(0, 120));
        thumbQueue = thumbQueue.slice(120);
        thumbProc.running = true;
    }
    Process {
        id: thumbProc
        property string pending: ""
        stdinEnabled: true
        command: ["python3", root.script, "cache-thumbs"]
        onStarted: write(pending + "\n")
        onExited: { thumbCommit.restart(); Qt.callLater(root.pumpThumbs); }
        stdout: SplitParser {
            onRead: (line) => {
                let d = null;
                try { d = JSON.parse(line); } catch (e) { return; }
                if (d.event !== "thumb") return;
                root.thumbPendingFiles[d.url] = d.failed ? "" : d.path;
                if (!thumbCommit.running) thumbCommit.start();
            }
        }
    }
    // url -> cached file ("" = the source did not deliver it). Cards read this, so
    // updates are collected and published a few times a second, not once per file.
    property var thumbFiles: ({})
    property var thumbPendingFiles: ({})
    function thumbFor(r) {
        if (!r || !r.thumb) return "";
        if (r.thumbCached) return r.thumbCache;
        return thumbFiles[r.thumb] || "";
    }
    function thumbFailed(r) { return !!(r && r.thumb && thumbFiles[r.thumb] === ""); }
    Timer {
        id: thumbCommit
        interval: 200
        onTriggered: {
            root.thumbFiles = Object.assign({}, root.thumbFiles, root.thumbPendingFiles);
            root.thumbPendingFiles = ({});
        }
    }

    // ------------------------------------------------------------------ status / keys / history / library
    function refreshStatus() {
        statusProc.running = false;
        statusProc.running = true;
    }
    Process {
        id: statusProc
        command: ["python3", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                root.onlineKnown = true;
                root.offline = !d.online;
                root.offlineDetail = d.detail || "";
                root.keys = d.keys || {};
                root.caps = d.caps || {};
                root.ffmpegOk = !!(d.ffmpeg && d.ffprobe);
                if (root.offline) root.refreshLibrary();
            }
        }
    }

    function loadHistory() { runHistory([]); }
    function clearHistory() { history = []; runHistory(["--clear"]); }
    function forgetQuery(q) { history = history.filter(x => x !== q); runHistory(["--remove", q]); }
    function runHistory(extra) {
        historyProc.running = false;
        historyProc.command = ["python3", script, "history"].concat(extra);
        historyProc.running = true;
    }
    Process {
        id: historyProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                if (d.ok) root.history = d.items || [];
            }
        }
    }

    function refreshLibrary() {
        localProc.running = false;
        localProc.command = ["python3", script, "local", "--dir", downloadDir, "--dir", wallpaperDir];
        localProc.running = true;
    }
    function editCustomSources(action, field, value) {
        if (customProc.running) return;
        customProc.command = ["python3", script, "custom-sources"].concat(action ? [action, field] : []);
        customProc.pending = value || "";
        customProc.changed = !!action;
        customProc.enableLinks = action === "add" && field === "urls";
        customProc.running = true;
    }
    Process {
        id: customProc
        property string pending: ""
        property bool changed: false
        property bool enableLinks: false
        stdinEnabled: true
        onStarted: if (pending !== "") { write(pending + "\n"); pending = ""; }
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                if (d.ok) {
                    root.customSources = d.sources;
                    if (customProc.changed) {
                        root.refreshLibrary();
                        if (customProc.enableLinks && !root.prefs.sources.links) root.setSourceEnabled("links", true);
                        else root.refresh();
                    }
                } else root.notify(d.error || root.tr("Could not save the source", "Не удалось сохранить источник"));
            }
        }
    }
    function checkSource(name) {
        if (checkProc.running) return;
        checkProc.source = name;
        checkProc.command = ["python3", script, "check-source", name];
        checkProc.running = true;
    }
    Process {
        id: checkProc
        property string source: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                const checks = Object.assign({}, root.sourceChecks);
                checks[checkProc.source] = d.ok ? root.tr("Connection OK", "Подключение работает") : (d.error || root.tr("Connection check failed", "Проверка подключения не удалась"));
                root.sourceChecks = checks;
            }
        }
    }
    Process {
        id: localProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                root.library = d.items || [];
                let map = Object.assign({}, root.downloaded);
                for (let it of root.library) if (it.id && it.hub && !it.edited) map[it.id] = it.path;
                root.downloaded = map;
            }
        }
    }

    function saveKey(name, value) {
        keyProc.running = false;
        keyProc.command = ["python3", script, "set-key", name];
        keyProc.pending = value;
        keyProc.running = true;
    }

    function readFavorites() {
        if (favoriteProc.running) return;
        favoriteProc.command = ["python3", script, "favorites"];
        favoriteProc.running = true;
    }
    function saveFavorite(r, collection, remove) {
        if (!r || favoriteProc.running) return;
        favoriteProc.command = ["python3", script, "favorites", "--update"];
        favoriteProc.pending = JSON.stringify({id: r.id, title: r.title, sourceName: r.sourceName, kind: r.kind,
            format: r.format, path: r.local ? r.path : "", pageUrl: r.pageUrl, collection: collection, remove: remove});
        favoriteProc.running = true;
    }
    Process {
        id: favoriteProc
        property string pending: ""
        stdinEnabled: true
        onStarted: if (pending !== "") { write(pending + "\n"); pending = ""; }
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                if (d.ok) root.favorites = d.items || {};
                else root.notify(d.error || root.tr("Could not update favorites", "Не удалось обновить избранное"));
            }
        }
    }
    Process {
        id: keyProc
        property string pending: ""
        stdinEnabled: true
        onStarted: { write(pending + "\n"); pending = ""; }
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                if (!d.ok) { root.notify(d.error); return; }
                let k = Object.assign({}, root.keys); k[d.source] = d.set; root.keys = k;
                const checks = Object.assign({}, root.sourceChecks);
                delete checks[d.source];
                root.sourceChecks = checks;
                root.notify(d.set ? root.tr("API key saved (private file, not in settings or Themess). Search again to use it.",
                                            "Ключ сохранён (личный файл, не в настройках и не в Themess). Повторите поиск.")
                                  : root.tr("API key removed.", "Ключ удалён."));
            }
        }
    }

    // ------------------------------------------------------------------ download / apply / quality
    property var dlItem: null
    property real dlDone: 0
    property real dlTotal: 0
    property string dlAfter: ""               // "", "apply", "edit", "quality", "preview-animation"
    property string dlMonitor: "all"
    readonly property bool downloading: dlItem !== null
    readonly property bool importing: importProc.running
    readonly property bool preparing: prepareProc.running

    function canFetch(r) {
        return !!(r && r.url && !r.external && !downloadDenied[r.id]);
    }
    function resolvedResult(r) {
        return r && peerMedia[r.id] ? Object.assign({}, r, peerMedia[r.id]) : r;
    }
    function resolvePeer(r) {
        if (!r || r.source !== "sepia" || !r.peerId || peerMedia[r.id] || r.id === resolvingPeer) return;
        nextPeer = r;
        startPeer();
    }
    function startPeer() {
        if (!nextPeer || peerProc.running) return;
        const r = nextPeer;
        nextPeer = null;
        peerProc.resultId = r.id;
        peerProc.safe = prefs.safe;
        peerProc.command = ["python3", script, "resolve-peertube", "--page-url", r.pageUrl, "--uuid", r.peerId]
            .concat(prefs.safe ? [] : ["--unsafe"]);
        peerProc.running = true;
    }
    Process {
        id: peerProc
        property string resultId: ""
        property bool safe: true
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                if (!root.byId[peerProc.resultId] || peerProc.safe !== root.prefs.safe) return;
                const media = Object.assign({}, root.peerMedia);
                media[peerProc.resultId] = d.ok ? d.media : {notes: [d.error || root.tr("Could not check the video", "Не удалось проверить видео")]};
                root.peerMedia = media;
            }
        }
        onExited: Qt.callLater(root.startPeer)
    }

    function metaFor(r) {
        return JSON.stringify({ source: r.source, sourceName: r.sourceName, pageUrl: r.pageUrl, author: r.author,
                                license: r.license, provenance: r.provenance, provenanceReason: r.provenanceReason });
    }
    // after: "" (save only), "apply", "edit", "quality"
    function download(r, after) {
        if (!r) return;
        if (r.local && r.path) { finishAfter(r, r.path, after, monitor, probed[r.path] || null); return; }
        if (downloaded[r.id]) { finishAfter(r, downloaded[r.id], after, monitor, probed[r.id] || null); return; }
        if (!canFetch(r)) return;
        if (dlItem) { notify(tr("Another download is running; cancel it first.", "Уже идёт загрузка; сначала отмените её.")); return; }
        if (!r.originalAvailable)
            notify(tr("Only a reduced copy is available from this source.", "У этого источника доступна только уменьшенная копия."));
        dlItem = r;
        dlAfter = after || "";
        dlMonitor = monitor;
        dlDone = 0;
        dlTotal = r.size || 0;
        dlProc.command = ["python3", script, "download", "--url", r.url, "--id", r.id, "--title", r.title || r.id,
                          "--dest", downloadDir, "--max-mb", String(prefs.maxDownloadMb || 400), "--meta", metaFor(r), "--kind", r.kind || ""];
        dlProc.running = true;
    }
    function cancelDownload() {
        if (dlProc.running) dlProc.signal(15);
    }
    function finishAfter(r, path, after, mon, info) {
        if (after === "apply") applyPath(path, mon, info);
        else if (after === "edit") pendingEdit = path;
        else if (after === "quality") checkQuality(path, r);
        else if (after === "preview-animation") prepareAnimation(path, "");
    }
    function applyPath(path, mon, info) {
        if (!path) return;
        let target = mon || monitor;
        if (!info || info.format === "apng" || (info.format === "webp" && info.kind === "animated" && !path.toLowerCase().endsWith(".animated.webp"))) {
            prepareAnimation(path, target);
            return;
        }
        installWallpaper(path, target);
    }
    function installWallpaper(path, target) {
        Wallpaper.setWallpaper(target, path, "");
        let where = target === "all" ? tr("all monitors", "все мониторы") : target;
        notify(tr("Wallpaper applied to ", "Обои применены: ") + where);
    }
    Process {
        id: dlProc
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("P ")) {
                    let p = line.split(" ");
                    root.dlDone = Number(p[1]) || 0;
                    if (Number(p[2]) > 0) root.dlTotal = Number(p[2]);
                    return;
                }
                let d = null;
                try { d = JSON.parse(line); } catch (e) { return; }
                let r = root.dlItem;
                if (d.ok && r) {
                    let map = Object.assign({}, root.downloaded); map[r.id] = d.path; root.downloaded = map;
                    let pm = Object.assign({}, root.probed); pm[r.id] = d.info; pm[d.path] = d.info; root.probed = pm;
                    if (root.dlAfter !== "apply") root.notify(root.tr("Saved to ", "Сохранено: ") + d.path);
                    root.finishAfter(r, d.path, root.dlAfter, root.dlMonitor, d.info);
                    root.refreshLibrary();
                } else if (d.cancelled) {
                    root.notify(root.tr("Download cancelled.", "Загрузка отменена."));
                } else {
                    if (r && d.unavailable) {
                        const denied = Object.assign({}, root.downloadDenied);
                        denied[r.id] = true;
                        root.downloadDenied = denied;
                    }
                    root.notify(d.error || root.tr("download failed", "загрузка не удалась"));
                    if (d.offline) root.offline = true;
                }
            }
        }
        onExited: (code) => { root.dlItem = null; root.dlAfter = ""; }
    }

    function importFiles(urls) {
        if (!urls || !urls.length || importing) return;
        importProc.command = ["python3", script, "import", "--dest", downloadDir, "--max-mb", String(prefs.maxDownloadMb || 400)]
            .concat(Array.from(urls, url => String(url)));
        importProc.running = true;
    }
    Process {
        id: importProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                if (d.ok) root.refreshLibrary();
                root.notify((d.errors?.length ? d.errors[0] : d.error) || (root.tr("Imported files: ", "Импортировано файлов: ") + (d.items?.length || 0)));
            }
        }
    }

    function prepareAnimation(path, target) {
        if (!path || prepareProc.running) return;
        prepareProc.original = path;
        prepareProc.monitor = target;
        prepareProc.command = ["python3", script, "prepare-animation", path];
        prepareProc.running = true;
        notify(tr("Preparing animation…", "Подготовка анимации…"));
    }
    Process {
        id: prepareProc
        property string original: ""
        property string monitor: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                if (!d.ok || !d.path) { root.notify(d.error || root.tr("Animation could not be prepared", "Не удалось подготовить анимацию")); return; }
                if (d.info.format === "apng" && d.path !== prepareProc.original) {
                    const ready = Object.assign({}, root.preparedAnimations);
                    ready[prepareProc.original] = d.path;
                    root.preparedAnimations = ready;
                }
                if (prepareProc.monitor !== "") root.installWallpaper(d.path, prepareProc.monitor);
            }
        }
    }

    property var qualityTarget: null
    readonly property bool qualityBusy: qualityProc.running
    function checkQuality(path, r) {
        if (qualityProc.running) { notify(tr("A quality check is already running.", "Проверка качества уже идёт.")); return; }
        qualityTarget = r || null;
        let cmd = ["python3", script, "quality", path];
        if (r) cmd = cmd.concat(["--id", r.id || "", "--provenance", r.provenance || "", "--provenance-reason", r.provenanceReason || ""]);
        qualityProc.command = cmd;
        qualityProc.running = true;
    }
    Process {
        id: qualityProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                if (!d.ok) { root.notify(d.error || "quality check failed"); return; }
                let r = root.qualityTarget;
                let key = r ? r.id : d.info.path;
                let qm = Object.assign({}, root.qualityById); qm[key] = d.quality; qm[d.info.path] = d.quality; root.qualityById = qm;
                let pm = Object.assign({}, root.probed); pm[key] = d.info; pm[d.info.path] = d.info; root.probed = pm;
                if (root.prefs.hideUpscales) root.rebuild();
            }
        }
    }

    // ------------------------------------------------------------------ formatting
    function fmtSize(b) {
        if (!b || b <= 0) return tr("size unknown", "размер неизвестен");
        if (b >= 1073741824) return (b / 1073741824).toFixed(2) + " GB";
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB";
        return Math.max(1, Math.round(b / 1024)) + " KB";
    }
    function fmtDur(sec) {
        if (!sec || sec <= 0) return "";
        let m = Math.floor(sec / 60), s2 = Math.round(sec % 60);
        return m + ":" + String(s2).padStart(2, "0");
    }
    function fmtRate(bps, estimated) {
        if (!bps) return "";
        return (estimated ? "≈" : "") + (bps >= 1000000 ? (bps / 1000000).toFixed(1) + " Mbit/s" : Math.round(bps / 1000) + " kbit/s");
    }
    function resClass(w, h) {
        let big = Math.max(w, h), small = Math.min(w, h);
        if (big >= 7680 && small >= 4320) return "8K";
        if (big >= 3840 && small >= 2160) return "4K";
        if (big >= 2560 && small >= 1440) return "1440p";
        if (big >= 1920 && small >= 1080) return "1080p";
        return "";
    }
    function resLabel(w, h) {
        if (!w || !h) return tr("resolution unknown", "разрешение неизвестно");
        let c = resClass(w, h);
        return w + "×" + h + (c ? " · " + c : "");
    }
    function kindLabel(k) {
        return k === "video" ? tr("Video", "Видео") : k === "animated" ? tr("Animated", "Анимация") : tr("Image", "Изображение");
    }
    function sourceLabel(name) {
        if (name === "local") return tr("My Wallpapers", "Мои обои");
        if (name === "links") return tr("Custom URLs / Feeds", "Ссылки и ленты");
        return caps[name]?.name || ({ brave: "Brave Search", sepia: "Sepia Search / PeerTube", wallhaven: "Wallhaven", commons: "Wikimedia Commons", openverse: "Openverse", pexels: "Pexels", pixabay: "Pixabay", giphy: "GIPHY", steam: "Steam Workshop" })[name] || name;
    }
    function resOptionLabel(v) {
        return v === "auto" ? tr("Auto", "Авто") + " · " + autoRes.toUpperCase().replace("P", "p")
             : v === "any" ? tr("Any", "Любое") : v === "4k" ? "4K" : v === "8k" ? "8K" : v;
    }
    function sortLabel(v) {
        return ({ relevance: tr("Relevance", "По релевантности"), resolution: tr("Highest resolution", "Наибольшее разрешение"),
                  newest: tr("Newest", "Новые"), popular: tr("Most popular", "Популярные") })[v] || v;
    }
    // Human text for why a source sat this search out.
    function skipText(st) {
        switch (st.skipCode) {
        case "separate": return tr("choose GIPHY by itself", "выберите GIPHY отдельно");
        case "key": return tr("needs your API key", "нужен ваш API-ключ");
        case "safe": return tr("no safe-search filter at the source — used only with Safe Search off", "у источника нет безопасного фильтра — используется только при выключенном Safe Search");
        case "sort-newest": return tr("provides no upload dates", "не сообщает даты загрузки");
        case "sort-popular": return tr("provides no reliable popularity", "не даёт достоверной популярности");
        case "kind": return kind === "video" ? tr("has no videos", "нет видео") : kind === "animated" ? tr("has no animations", "нет анимаций") : tr("has no still images", "нет статичных изображений");
        }
        return st.skipped || "";
    }
    function hiddenText(h) {
        if (!h) return "";
        let parts = [];
        if (h.lowres) parts.push(h.lowres + tr(" below the minimum resolution", " ниже мин. разрешения"));
        if (h.unknownRes) parts.push(h.unknownRes + tr(" without known resolution", " без известного разрешения"));
        if (h.reducedCopy) parts.push(h.reducedCopy + tr(" only as a reduced copy", " только уменьшенная копия"));
        if (h.kind) parts.push(h.kind + tr(" of another type", " другого типа"));
        if (h.animation) parts.push(h.animation + tr(" unconfirmed animations", " с неподтверждённой анимацией"));
        return parts.length ? tr("hidden: ", "скрыто: ") + parts.join(", ") : "";
    }
}
