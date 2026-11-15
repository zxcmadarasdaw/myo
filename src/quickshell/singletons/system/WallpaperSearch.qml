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
    readonly property var sourceNames: ["wallhaven", "commons", "openverse", "pexels", "pixabay", "giphy"]
    readonly property var resOptions: ["auto", "any", "1080p", "1440p", "4k", "8k"]
    readonly property var sortOptions: ["relevance", "resolution", "newest", "popular"]
    readonly property var defaults: ({
        minRes: "auto", sort: "relevance", translate: true, safe: true, remember: true,
        maxDownloadMb: 400, minBitrateMbps: 0, hideUpscales: false, knownOnly: false,
        sources: { wallhaven: true, commons: true, openverse: true, pexels: true, pixabay: true, giphy: true }
    })
    property var prefs: loadPrefs()

    function loadPrefs() {
        // Settings of the old Wallpaper Hub page are taken over once.
        let saved = Config.getSetting("wallpaperSearch", null) || Config.getSetting("wallpaperHub", {}) || {};
        let p = Object.assign({}, defaults, saved);
        p.sources = Object.assign({}, defaults.sources, saved.sources || {});
        if (resOptions.indexOf(p.minRes) < 0) p.minRes = "auto";
        if (sortOptions.indexOf(p.sort) < 0) p.sort = "relevance";
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
    }
    function enabledSources() {
        return sourceNames.filter(k => prefs.sources[k] !== false).join(",");
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
    property int searchSerial: 0
    property alias results: resultsModel     // rows: { rid }
    ListModel { id: resultsModel }

    property bool offline: false
    property bool onlineKnown: false
    property string offlineDetail: ""
    property var keys: ({})
    property var caps: ({})
    property bool ffmpegOk: true
    property var history: []

    property var library: []
    property var downloaded: ({})            // result id -> local path
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
        segments = [];
        statusBySource = {};
        plan = [];
        translated = "";
        translateError = "";
        lastError = "";
        hasMore = false;
    }
    function cancelSearch() {
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
                   "--min", effectiveMinRes, "--sort", prefs.sort, "--translate", prefs.translate ? "auto" : "off",
                   "--sources", enabledSources()];
        if (!prefs.safe) cmd.push("--unsafe");
        if (prefs.remember && page === 1) cmd.push("--remember");
        segments = segments.concat([{ page: page, batches: [] }]);
        searching = true;
        lastError = "";
        searchSerial++;
        let p = searchComp.createObject(root, { command: cmd, serial: searchSerial });
        searchProc = p;
        p.running = true;
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
            let ids = [], thumbs = [];
            for (let r of d.results || []) {
                if (byId[r.id]) continue;            // the same file on two pages
                byId[r.id] = r;
                ids.push(r.id);
                if (r.thumb && !r.thumbCached) thumbs.push(r.thumb);
            }
            let seg = segments[segments.length - 1];
            seg.batches.push({ source: d.source, ids: ids });
            layoutLastSegment();
            if (thumbs.length) queueThumbs(thumbs);
        } else if (d.event === "done") {
            p.finished = true;
            searching = false;
            if (!d.ok) {
                if (!retryPageLater(d.error || "")) lastError = d.error || tr("search failed", "поиск не удался");
                return;
            }
            onlineKnown = true;
            offline = !!d.offline;
            if (offline) refreshLibrary();
            if (retryPageLater("")) return;
            hasMore = !!d.hasMore;
        }
    }
    // A further page that brought nothing because its sources failed (rate limit,
    // network) is not skipped: the page number goes back so the next scroll asks again.
    function retryPageLater(error) {
        let seg = segments[segments.length - 1];
        if (page <= 1 || !seg || seg.page !== page) return false;
        let got = 0;
        for (let b of seg.batches) got += b.ids.length;
        let errs = Object.values(statusBySource).filter(s => s && (s.error || s.offline)).map(s => s.error || "offline");
        if (got > 0 || (error === "" && errs.length === 0)) return false;
        segments = segments.slice(0, -1);
        page -= 1;
        hasMore = true;
        notify(tr("Could not load more results: ", "Не удалось загрузить ещё: ") + (error || errs[0]) + tr(". Scroll again to retry.", ". Прокрутите ещё раз, чтобы повторить."));
        return true;
    }
    function onSearchExit(p, code) {
        if (p === searchProc) {
            searching = false;
            if (!p.finished) {
                lastError = tr("The search helper stopped unexpectedly (exit code ", "Поисковый процесс неожиданно завершился (код ") + code + ").";
            }
            searchProc = null;
        }
        Qt.callLater(() => p.destroy());
    }

    // Each page keeps its own rows; only the page that is still loading is re-laid
    // out, so rows the user already scrolled past never move.
    function orderSegment(seg) {
        let ids = [];
        if (prefs.sort === "resolution") {
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
        localProc.command = ["python3", script, "local", "--dirs", downloadDir + "|" + editedDir + "|" + wallpaperDir];
        localProc.running = true;
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
    property string dlAfter: ""               // "", "apply", "edit", "quality"
    property string dlMonitor: "all"
    readonly property bool downloading: dlItem !== null

    function metaFor(r) {
        return JSON.stringify({ source: r.source, sourceName: r.sourceName, pageUrl: r.pageUrl, author: r.author,
                                license: r.license, provenance: r.provenance, provenanceReason: r.provenanceReason });
    }
    // after: "" (save only), "apply", "edit", "quality"
    function download(r, after) {
        if (!r || !r.url) return;
        if (downloaded[r.id]) { finishAfter(r, downloaded[r.id], after, monitor, probed[r.id] || null); return; }
        if (dlItem) { notify(tr("Another download is running; cancel it first.", "Уже идёт загрузка; сначала отмените её.")); return; }
        if (!r.originalAvailable)
            notify(tr("Only a reduced copy is available from this source.", "У этого источника доступна только уменьшенная копия."));
        dlItem = r;
        dlAfter = after || "";
        dlMonitor = monitor;
        dlDone = 0;
        dlTotal = r.size || 0;
        dlProc.command = ["python3", script, "download", "--url", r.url, "--id", r.id, "--title", r.title || r.id,
                          "--dest", downloadDir, "--max-mb", String(prefs.maxDownloadMb || 400), "--meta", metaFor(r)];
        dlProc.running = true;
    }
    function cancelDownload() {
        if (dlProc.running) dlProc.signal(15);
    }
    function finishAfter(r, path, after, mon, info) {
        if (after === "apply") applyPath(path, mon, info);
        else if (after === "edit") pendingEdit = path;
        else if (after === "quality") checkQuality(path, r);
    }
    function applyPath(path, mon, info) {
        if (!path) return;
        let target = mon || monitor;
        Wallpaper.setWallpaper(target, path, "");
        let where = target === "all" ? tr("all monitors", "все мониторы") : target;
        if (info && info.kind === "animated" && info.format === "webp")
            notify(tr("Applied to ", "Применено: ") + where + tr(". Note: the Wallpaper Engine shows animated WebP as a still picture.", ". Учтите: Wallpaper Engine показывает анимированный WebP как статичную картинку."));
        else
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
                    root.notify(d.error || root.tr("download failed", "загрузка не удалась"));
                    if (d.offline) root.offline = true;
                }
            }
        }
        onExited: (code) => { root.dlItem = null; root.dlAfter = ""; }
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
        return ({ wallhaven: "Wallhaven", commons: "Wikimedia Commons", openverse: "Openverse", pexels: "Pexels", pixabay: "Pixabay", giphy: "Giphy" })[name] || name;
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
        case "key": return tr("needs your free API key", "нужен ваш бесплатный API-ключ");
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
        return parts.length ? tr("hidden: ", "скрыто: ") + parts.join(", ") : "";
    }
}
