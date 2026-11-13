import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C
import Quickshell
import Quickshell.Io
import "../../"
import "../../../"

// Wallpaper Hub: real internet wallpaper search (Settings -> Theme -> Wallpaper Hub).
// All network, file and media work runs in scripts/wallpaper/wallhub.py; this
// file only shows results. The preview and Wallpaper Studio panels are loaded
// by URL so a missing QtMultimedia or a broken panel cannot take the settings
// window (or the shell) down with it. Applying uses the existing
// Wallpaper.setWallpaper() path, so GIF/video playback, transitions,
// per-monitor wallpapers and persistence stay in WallpaperEngine.
GuideTab {
    id: hub
    subTabIndex: 2

    function tr(en, ru) { return I18n.currentLang === "ru" ? ru : en; }
    function s(v) { return rootObj.s(v); }

    readonly property string script: Caching.serpantinumDir + "/scripts/wallpaper/wallhub.py"
    readonly property string wallpaperDir: Config.getSetting("wallpaperDir", "") || Config.getSetting("wallpaper_dir", "") || Quickshell.env("WALLPAPER_DIR") || (Quickshell.env("HOME") + "/Pictures/Wallpapers")
    readonly property string hubDir: wallpaperDir + "/Wallpaper Hub"
    readonly property string editedDir: hubDir + "/Edited"

    // ---------------------------------------------------------------- settings
    readonly property var defaults: ({
        minRes: "any", translate: true, safe: true, maxDownloadMb: 400, minBitrateMbps: 0,
        preferVerified: false, hideUpscales: false, knownOnly: false,
        sources: { wallhaven: true, commons: true, openverse: true, pexels: true, pixabay: true, giphy: true }
    })
    property var prefs: loadPrefs()
    function loadPrefs() {
        let p = Object.assign({}, defaults, Config.getSetting("wallpaperHub", {}) || {});
        p.sources = Object.assign({}, defaults.sources, p.sources || {});
        return p;
    }
    function setPref(key, value) {
        let p = JSON.parse(JSON.stringify(prefs));
        p[key] = value;
        prefs = p;
        Config.setSetting("wallpaperHub", p);
    }
    function setSourceEnabled(name, on) {
        let src = Object.assign({}, prefs.sources);
        src[name] = on;
        setPref("sources", src);
    }
    Connections {
        target: Config
        function onSettingsLoaded() { hub.prefs = hub.loadPrefs(); }
    }

    // ---------------------------------------------------------------- state
    property string query: ""
    property string kind: "all"             // all | image | animated | video
    property int page: 1
    property bool searching: false
    property bool hasMore: false
    property var results: []
    property var sourceStatus: []
    property string translated: ""
    property string translateError: ""
    property string lastError: ""
    property bool offline: false
    property bool onlineKnown: false
    property string offlineDetail: ""
    property bool showLibrary: false
    property bool showSettings: false
    property var library: []
    property var downloaded: ({})          // result id -> local path
    property var probed: ({})              // result id -> media info after download
    property var qualityById: ({})         // result id (or local path) -> quality report
    property var keys: ({})
    property bool ffmpegOk: true
    property string toast: ""
    property string monitor: "all"

    // one transfer at a time, cancellable
    property var dlItem: null
    property real dlDone: 0
    property real dlTotal: 0
    property string dlAfter: ""             // "", "apply", "edit", "quality"

    property var previewEntry: null
    property string studioPath: ""

    readonly property var visibleResults: {
        let out = results.slice();
        let minBps = (prefs.minBitrateMbps || 0) * 1000000;
        out = out.filter(r => {
            let q = qualityById[r.id] || r.quality;
            if (prefs.hideUpscales && q && q.verdict === "upscale") return false;
            if (prefs.knownOnly && !r.qualityKnown) return false;
            if (minBps > 0 && r.kind === "video") {
                if (r.bitrate > 0 && r.bitrate < minBps) return false;
                if (!r.bitrate && prefs.knownOnly) return false;
            }
            return true;
        });
        if (prefs.preferVerified)
            out.sort((a, b) => (a.provenance === "verified" ? 0 : 1) - (b.provenance === "verified" ? 0 : 1));
        return out;
    }

    function notify(msg) { toast = msg; toastTimer.restart(); }
    Timer { id: toastTimer; interval: 5000; onTriggered: hub.toast = "" }

    // ---------------------------------------------------------------- formatting
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
    function resLabel(w, h) {
        if (!w || !h) return tr("resolution unknown", "разрешение неизвестно");
        let big = Math.max(w, h), small = Math.min(w, h), tag = "";
        if (big >= 7680 && small >= 4320) tag = " · 8K";
        else if (big >= 3840 && small >= 2160) tag = " · 4K";
        else if (big >= 2560 && small >= 1440) tag = " · 1440p";
        else if (big >= 1920 && small >= 1080) tag = " · 1080p";
        return w + "×" + h + tag;
    }
    function kindLabel(k) {
        return k === "video" ? tr("Video", "Видео") : k === "animated" ? tr("Animated", "Анимация") : tr("Image", "Изображение");
    }
    function sourceLabel(name) {
        return ({ wallhaven: "Wallhaven", commons: "Wikimedia Commons", openverse: "Openverse", pexels: "Pexels", pixabay: "Pixabay", giphy: "Giphy" })[name] || name;
    }
    function qualityColor(v) {
        return v === "upscale" ? ThemeBackend.red : v === "lowdetail" ? ThemeBackend.peach : v === "ok" ? ThemeBackend.green : ThemeBackend.overlay1;
    }

    // ---------------------------------------------------------------- backend calls
    function enabledSources() {
        return Object.keys(prefs.sources).filter(k => prefs.sources[k]).join(",");
    }

    function startSearch() {
        let q = searchField.text.trim();
        if (q === "") return;
        query = q;
        page = 1;
        results = [];
        sourceStatus = [];
        translated = "";
        translateError = "";
        lastError = "";
        showLibrary = false;
        runSearch();
    }
    function loadMore() {
        if (searching || !hasMore || query === "" || showLibrary) return;
        page += 1;
        runSearch();
    }
    function runSearch() {
        searchProc.running = false;
        let cmd = ["python3", script, "search", "--query", query, "--page", String(page), "--kind", kind,
                   "--min", prefs.minRes || "any", "--translate", prefs.translate ? "auto" : "off",
                   "--sources", enabledSources()];
        if (!prefs.safe) cmd.push("--unsafe");
        searchProc.expect = query + "|" + page + "|" + kind;
        searchProc.command = cmd;
        searching = true;
        searchProc.running = true;
    }
    function resetSearch() {
        if (query === "" || showLibrary) return;
        page = 1;
        results = [];
        runSearch();
    }
    function setKind(k) {
        if (kind === k) return;
        kind = k;
        resetSearch();
    }

    function refreshStatus() {
        statusProc.running = false;
        statusProc.running = true;
    }
    function refreshLibrary() {
        localProc.command = ["python3", script, "local", "--dirs", hubDir + "|" + editedDir + "|" + wallpaperDir];
        localProc.running = false;
        localProc.running = true;
    }

    function metaFor(r) {
        return JSON.stringify({ source: r.source, sourceName: r.sourceName, pageUrl: r.pageUrl, author: r.author,
                                license: r.license, provenance: r.provenance, provenanceReason: r.provenanceReason });
    }
    // after: "" (just download), "apply", "edit", "quality"
    function download(r, after) {
        if (!r || !r.url) return;
        if (downloaded[r.id]) { finishAfter(r, downloaded[r.id], after); return; }
        if (dlItem) { notify(tr("Another download is running; cancel it first.", "Уже идёт загрузка; сначала отмените её.")); return; }
        if (!r.originalAvailable)
            notify(tr("Only a reduced copy is available from this source.", "У этого источника доступна только уменьшенная копия."));
        dlItem = r;
        dlAfter = after || "";
        dlDone = 0;
        dlTotal = r.size || 0;
        dlProc.command = ["python3", script, "download", "--url", r.url, "--id", r.id, "--title", r.title || r.id,
                          "--dest", hubDir, "--max-mb", String(prefs.maxDownloadMb || 400), "--meta", metaFor(r)];
        dlProc.running = true;
    }
    function cancelDownload() {
        if (dlProc.running) dlProc.signal(15);
    }
    function finishAfter(r, path, after) {
        if (after === "apply") applyPath(path);
        else if (after === "edit") studioPath = path;
        else if (after === "quality") checkQuality(path, r);
    }
    function applyPath(path) {
        if (!path) return;
        Wallpaper.setWallpaper(monitor, path, "");
        notify(tr("Wallpaper applied to ", "Обои применены: ") + (monitor === "all" ? tr("all monitors", "все мониторы") : monitor));
    }
    property var qualityTarget: null
    function checkQuality(path, r) {
        if (qualityProc.running) { notify(tr("A quality check is already running.", "Проверка качества уже идёт.")); return; }
        qualityTarget = r || null;
        let cmd = ["python3", script, "quality", path];
        if (r) cmd = cmd.concat(["--id", r.id || "", "--provenance", r.provenance || "", "--provenance-reason", r.provenanceReason || ""]);
        qualityProc.command = cmd;
        qualityProc.running = true;
    }
    readonly property bool qualityBusy: qualityProc.running
    function saveKey(name, value) {
        keyProc.command = ["python3", script, "set-key", name];
        keyProc.pending = value;
        keyProc.running = true;
    }

    Process {
        id: searchProc
        property string expect: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                let d = null;
                try { d = JSON.parse(lines[lines.length - 1]); } catch (e) { d = null; }
                if (!d) return;
                if (d.ok && (d.query + "|" + d.page + "|" + d.kind) !== searchProc.expect) return;
                hub.searching = false;
                if (!d.ok) { hub.lastError = d.error || "search failed"; return; }
                hub.offline = d.offline;
                hub.onlineKnown = true;
                hub.translated = d.translated || "";
                hub.translateError = d.translateError || "";
                hub.sourceStatus = d.sources || [];
                hub.hasMore = d.hasMore;
                let seen = {};
                for (let r of hub.results) seen[r.id] = true;
                hub.results = hub.results.concat((d.results || []).filter(r => !seen[r.id]));
                if (d.offline) { hub.showLibrary = true; hub.refreshLibrary(); }
                let thumbs = (d.results || []).filter(r => r.thumb && !r.thumbCached).map(r => r.thumb);
                if (thumbs.length > 0 && !thumbProc.running) {
                    thumbProc.pending = JSON.stringify(thumbs);
                    thumbProc.running = true;
                }
            }
        }
        onExited: (code) => { if (code !== 0) hub.searching = false; }
    }

    Process {
        id: thumbProc
        property string pending: ""
        stdinEnabled: true
        command: ["python3", hub.script, "cache-thumbs"]
        onStarted: { write(pending + "\n"); }
    }

    Process {
        id: statusProc
        command: ["python3", hub.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                hub.onlineKnown = true;
                hub.offline = !d.online;
                hub.offlineDetail = d.detail || "";
                hub.keys = d.keys || {};
                hub.ffmpegOk = d.ffmpeg && d.ffprobe;
                if (hub.offline) { hub.showLibrary = true; hub.refreshLibrary(); }
            }
        }
    }

    Process {
        id: localProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                hub.library = d.items || [];
                let map = Object.assign({}, hub.downloaded);
                for (let it of hub.library) if (it.id && it.hub && !it.edited) map[it.id] = it.path;
                hub.downloaded = map;
            }
        }
    }

    Process {
        id: dlProc
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("P ")) {
                    let p = line.split(" ");
                    hub.dlDone = Number(p[1]) || 0;
                    if (Number(p[2]) > 0) hub.dlTotal = Number(p[2]);
                    return;
                }
                let d = null;
                try { d = JSON.parse(line); } catch (e) { return; }
                let r = hub.dlItem;
                if (d.ok && r) {
                    let map = Object.assign({}, hub.downloaded); map[r.id] = d.path; hub.downloaded = map;
                    let pm = Object.assign({}, hub.probed); pm[r.id] = d.info; hub.probed = pm;
                    hub.notify(hub.tr("Saved to ", "Сохранено: ") + d.path);
                    hub.finishAfter(r, d.path, hub.dlAfter);
                } else if (d.cancelled) {
                    hub.notify(hub.tr("Download cancelled.", "Загрузка отменена."));
                } else {
                    hub.notify(d.error || "download failed");
                    if (d.offline) hub.offline = true;
                }
            }
        }
        onExited: (code) => { hub.dlItem = null; hub.dlAfter = ""; }
    }

    Process {
        id: qualityProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { return; }
                if (!d.ok) { hub.notify(d.error || "quality check failed"); return; }
                let r = hub.qualityTarget;
                let key = r ? r.id : d.info.path;
                let qm = Object.assign({}, hub.qualityById); qm[key] = d.quality; qm[d.info.path] = d.quality; hub.qualityById = qm;
                let pm = Object.assign({}, hub.probed); pm[key] = d.info; pm[d.info.path] = d.info; hub.probed = pm;
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
                if (!d.ok) { hub.notify(d.error); return; }
                let k = Object.assign({}, hub.keys); k[d.source] = d.set; hub.keys = k;
                hub.notify(d.set ? hub.tr("API key saved (private file, not in Themess).", "Ключ сохранён (личный файл, не в Themess).")
                                 : hub.tr("API key removed.", "Ключ удалён."));
            }
        }
    }

    onVisibleChanged: if (visible) activateTimer.restart()
    Component.onCompleted: if (visible) activateTimer.restart()
    Timer {
        id: activateTimer
        interval: 250
        onTriggered: { hub.refreshStatus(); hub.refreshLibrary(); }
    }

    // ---------------------------------------------------------------- small building blocks
    component Txt: Text {
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: hub.s(12)
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    component Btn: Rectangle {
        id: btn
        property string label: ""
        property string icon: ""
        property color accent: ThemeBackend.surface1
        property color fg: ThemeBackend.text
        property bool active: true
        signal clicked()
        implicitHeight: hub.s(30)
        implicitWidth: btnRow.implicitWidth + hub.s(20)
        radius: Math.min(height / 2, ThemeBackend.borderRadius)
        color: !active ? Qt.alpha(accent, 0.35) : (btnMa.pressed ? Qt.darker(accent, 1.15) : (btnMa.containsMouse ? Qt.lighter(accent, 1.12) : accent))
        opacity: active ? 1 : 0.55
        Behavior on color { ColorAnimation { duration: 90 } }
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: hub.s(6)
            Text { visible: btn.icon !== ""; text: btn.icon; font.family: ThemeBackend.iconFont; font.pixelSize: hub.s(14); color: btn.fg; anchors.verticalCenter: parent.verticalCenter }
            Text { visible: btn.label !== ""; text: btn.label; font.family: ThemeBackend.fontFamily; font.pixelSize: hub.s(12); font.weight: Font.Medium; color: btn.fg; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.active) btn.clicked()
        }
    }
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        signal clicked()
        implicitHeight: hub.s(30)
        implicitWidth: chipText.implicitWidth + hub.s(22)
        radius: height / 2
        color: on ? Qt.alpha(ThemeBackend.mauve, 0.22) : (chipMa.containsMouse ? Qt.alpha(ThemeBackend.text, 0.08) : Qt.alpha(ThemeBackend.surface0, 0.6))
        border.width: 1
        border.color: on ? ThemeBackend.mauve : Qt.alpha(ThemeBackend.surface2, 0.5)
        Text { id: chipText; anchors.centerIn: parent; text: chip.label; color: chip.on ? ThemeBackend.mauve : ThemeBackend.text; font.family: ThemeBackend.fontFamily; font.pixelSize: hub.s(12); font.weight: Font.Medium }
        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }
    component Badge: Rectangle {
        id: badge
        property string label: ""
        property color tint: ThemeBackend.overlay1
        implicitHeight: hub.s(18)
        implicitWidth: badgeText.implicitWidth + hub.s(10)
        radius: hub.s(5)
        color: Qt.alpha(tint, 0.22)
        border.width: 1
        border.color: Qt.alpha(tint, 0.6)
        Text { id: badgeText; anchors.centerIn: parent; text: badge.label; color: badge.tint; font.family: ThemeBackend.fontFamily; font.pixelSize: hub.s(10); font.bold: true }
    }
    component Check: C.CheckBox {
        font.family: ThemeBackend.fontFamily
        font.pixelSize: hub.s(12)
        palette.windowText: ThemeBackend.text
        palette.text: ThemeBackend.text
        palette.base: ThemeBackend.surface0
        palette.highlight: ThemeBackend.mauve
    }

    // ---------------------------------------------------------------- layout
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: hub.s(12)
        spacing: hub.s(8)

        // header
        RowLayout {
            Layout.fillWidth: true
            spacing: hub.s(8)
            Txt { text: "Wallpaper Hub"; font.pixelSize: hub.s(18); font.bold: true }
            Badge {
                visible: hub.onlineKnown
                label: hub.offline ? "OFFLINE" : "ONLINE"
                tint: hub.offline ? ThemeBackend.red : ThemeBackend.green
            }
            Item { Layout.fillWidth: true }
            Txt { text: hub.tr("Apply to", "Применить на"); color: ThemeBackend.subtext0 }
            C.ComboBox {
                id: monitorBox
                Layout.preferredWidth: hub.s(150)
                font.family: ThemeBackend.fontFamily
                model: [hub.tr("All monitors", "Все мониторы")].concat(Quickshell.screens.map(sc => sc.name))
                onActivated: (i) => { hub.monitor = i === 0 ? "all" : Quickshell.screens[i - 1].name; }
            }
            Btn {
                icon: "󰉋"
                label: hub.tr("Downloaded", "Скачанные")
                accent: hub.showLibrary ? Qt.alpha(ThemeBackend.mauve, 0.3) : ThemeBackend.surface1
                onClicked: { hub.showLibrary = !hub.showLibrary; if (hub.showLibrary) hub.refreshLibrary(); }
            }
            Btn {
                icon: "󰒓"
                accent: hub.showSettings ? Qt.alpha(ThemeBackend.mauve, 0.3) : ThemeBackend.surface1
                onClicked: hub.showSettings = !hub.showSettings
            }
        }

        // search row
        RowLayout {
            Layout.fillWidth: true
            spacing: hub.s(8)
            C.TextField {
                id: searchField
                Layout.fillWidth: true
                Layout.preferredHeight: hub.s(38)
                placeholderText: hub.tr("Search wallpapers on the internet, e.g. \"cyberpunk rainy city\" or \"аниме девушка в белом\"",
                                        "Поиск обоев в интернете, например «cyberpunk rainy city» или «аниме девушка в белом»")
                font.family: ThemeBackend.fontFamily
                font.pixelSize: hub.s(13)
                color: ThemeBackend.text
                placeholderTextColor: ThemeBackend.overlay1
                selectByMouse: true
                background: Rectangle {
                    radius: ThemeBackend.borderRadius
                    color: Qt.alpha(ThemeBackend.surface0, 0.7)
                    border.width: 1
                    border.color: searchField.activeFocus ? ThemeBackend.mauve : Qt.alpha(ThemeBackend.surface2, 0.5)
                }
                onAccepted: hub.startSearch()
                Keys.onEscapePressed: (event) => { text = ""; event.accepted = true; }
            }
            Btn {
                Layout.preferredHeight: hub.s(38)
                icon: hub.searching ? "󰔟" : "󰍉"
                label: hub.tr("Search", "Найти")
                accent: ThemeBackend.mauve
                fg: ThemeBackend.crust
                active: searchField.text.trim() !== ""
                onClicked: hub.startSearch()
            }
        }

        // tabs + resolution
        Flow {
            Layout.fillWidth: true
            spacing: hub.s(6)
            Repeater {
                model: [["all", "All", "Все"], ["image", "Images", "Изображения"], ["animated", "Animated", "Анимация"], ["video", "Videos", "Видео"]]
                delegate: Chip {
                    required property var modelData
                    label: hub.tr(modelData[1], modelData[2])
                    on: hub.kind === modelData[0]
                    onClicked: hub.setKind(modelData[0])
                }
            }
            Item { width: hub.s(16); height: 1 }
            Txt { height: hub.s(30); verticalAlignment: Text.AlignVCenter; text: hub.tr("Min. resolution", "Мин. разрешение"); color: ThemeBackend.subtext0 }
            Repeater {
                model: [["any", "Any", "Любое"], ["1080p", "1080p", "1080p"], ["1440p", "1440p", "1440p"], ["4k", "4K", "4K"], ["8k", "8K", "8K"]]
                delegate: Chip {
                    required property var modelData
                    label: hub.tr(modelData[1], modelData[2])
                    on: (hub.prefs.minRes || "any") === modelData[0]
                    onClicked: { hub.setPref("minRes", modelData[0]); hub.resetSearch(); }
                }
            }
        }

        // translation + per-source status
        Txt {
            Layout.fillWidth: true
            visible: hub.translated !== "" || hub.translateError !== ""
            wrapMode: Text.Wrap
            color: ThemeBackend.subtext1
            text: hub.translated !== ""
                ? hub.tr("Original query sent to Pexels/Pixabay; translated for the other sources: ", "Исходный запрос отправлен в Pexels/Pixabay; для остальных источников переведён: ") + "“" + hub.translated + "”" + hub.tr("  (can be turned off in ⚙)", "  (отключается в ⚙)")
                : hub.tr("Translation unavailable (", "Перевод недоступен (") + hub.translateError + hub.tr("); the original text was sent.", "); отправлен исходный текст.")
        }
        Flow {
            Layout.fillWidth: true
            spacing: hub.s(6)
            visible: hub.sourceStatus.length > 0 && !hub.showLibrary
            Repeater {
                model: hub.sourceStatus
                delegate: Badge {
                    required property var modelData
                    tint: modelData.error ? ThemeBackend.red : modelData.skipped ? ThemeBackend.overlay1 : modelData.count > 0 ? ThemeBackend.green : ThemeBackend.yellow
                    label: hub.sourceLabel(modelData.source) + ": " + (modelData.error ? modelData.error : modelData.skipped ? modelData.skipped : modelData.count > 0 ? modelData.count : (modelData.note || "0"))
                }
            }
        }
        Txt { visible: hub.lastError !== ""; color: ThemeBackend.red; text: hub.lastError; Layout.fillWidth: true; wrapMode: Text.Wrap }

        // settings panel
        Rectangle {
            Layout.fillWidth: true
            visible: hub.showSettings
            implicitHeight: settingsCol.implicitHeight + hub.s(20)
            radius: ThemeBackend.borderRadius
            color: Qt.alpha(ThemeBackend.surface0, 0.55)
            ColumnLayout {
                id: settingsCol
                anchors.fill: parent
                anchors.margins: hub.s(10)
                spacing: hub.s(6)
                Txt { text: hub.tr("Sources", "Источники"); font.bold: true }
                Flow {
                    Layout.fillWidth: true
                    spacing: hub.s(6)
                    Repeater {
                        model: ["wallhaven", "commons", "openverse", "pexels", "pixabay", "giphy"]
                        delegate: Chip {
                            required property string modelData
                            label: hub.sourceLabel(modelData) + ((modelData === "pexels" || modelData === "pixabay" || modelData === "giphy") ? (hub.keys[modelData] ? " 󰌆" : " · " + hub.tr("key needed", "нужен ключ")) : "")
                            on: !!hub.prefs.sources[modelData]
                            onClicked: hub.setSourceEnabled(modelData, !hub.prefs.sources[modelData])
                        }
                    }
                }
                Txt {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: ThemeBackend.subtext0
                    text: hub.tr("Pexels, Pixabay and Giphy require your own free API key (pexels.com/api, pixabay.com/api/docs, developers.giphy.com). Keys are stored in ~/.config/serpantinum/secrets (mode 600), never in settings.json or Themess exports. A Wallhaven key is optional.",
                                 "Pexels, Pixabay и Giphy требуют ваш бесплатный API-ключ (pexels.com/api, pixabay.com/api/docs, developers.giphy.com). Ключи хранятся в ~/.config/serpantinum/secrets (права 600), не в settings.json и не в экспорте Themess. Ключ Wallhaven необязателен.")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: hub.s(6)
                    C.ComboBox {
                        id: keySource
                        Layout.preferredWidth: hub.s(130)
                        model: ["pexels", "pixabay", "giphy", "wallhaven"]
                        font.family: ThemeBackend.fontFamily
                    }
                    C.TextField {
                        id: keyField
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        placeholderText: hub.keys[keySource.currentText] ? hub.tr("key saved — enter a new one to replace", "ключ сохранён — введите новый для замены") : hub.tr("paste API key", "вставьте API-ключ")
                        font.family: ThemeBackend.fontFamily
                        color: ThemeBackend.text
                    }
                    Btn { label: hub.tr("Save key", "Сохранить"); active: keyField.text.trim() !== ""; onClicked: { hub.saveKey(keySource.currentText, keyField.text.trim()); keyField.text = ""; } }
                    Btn { label: hub.tr("Remove", "Удалить"); active: !!hub.keys[keySource.currentText]; onClicked: hub.saveKey(keySource.currentText, "") }
                }
                Txt { text: hub.tr("Search", "Поиск"); font.bold: true; Layout.topMargin: hub.s(4) }
                Check { text: hub.tr("Translate Russian queries to English for sources that need it (original text is kept and shown)", "Переводить русские запросы на английский для источников, которым это нужно (исходный текст сохраняется и показывается)"); checked: hub.prefs.translate; onToggled: hub.setPref("translate", checked) }
                Check { text: hub.tr("Safe search (each source's own filter)", "Безопасный поиск (фильтр самого источника)"); checked: hub.prefs.safe; onToggled: hub.setPref("safe", checked) }
                Txt { text: hub.tr("Original Quality Checker filters (all off by default — nothing is hidden unless you enable it)", "Фильтры Original Quality Checker (по умолчанию выключены — ничего не скрывается без вашего разрешения)"); font.bold: true; Layout.topMargin: hub.s(4); Layout.fillWidth: true; wrapMode: Text.Wrap }
                Check { text: hub.tr("Prefer verified sources (show first)", "Предпочитать подтверждённые источники (показывать первыми)"); checked: hub.prefs.preferVerified; onToggled: hub.setPref("preferVerified", checked) }
                Check { text: hub.tr("Hide likely upscales (among files already checked)", "Скрывать вероятные апскейлы (среди уже проверенных файлов)"); checked: hub.prefs.hideUpscales; onToggled: hub.setPref("hideUpscales", checked) }
                Check { text: hub.tr("Only files with known quality parameters (resolution and size)", "Только файлы с известными параметрами качества (разрешение и размер)"); checked: hub.prefs.knownOnly; onToggled: hub.setPref("knownOnly", checked) }
                Flow {
                    Layout.fillWidth: true
                    spacing: hub.s(8)
                    Txt { height: hub.s(36); verticalAlignment: Text.AlignVCenter; text: hub.tr("Minimum video bitrate, Mbit/s (0 = off)", "Мин. битрейт видео, Мбит/с (0 = выкл.)") }
                    C.SpinBox { from: 0; to: 200; value: hub.prefs.minBitrateMbps || 0; editable: true; onValueModified: hub.setPref("minBitrateMbps", value) }
                    Txt { height: hub.s(36); verticalAlignment: Text.AlignVCenter; text: hub.tr("Download size limit, MB", "Лимит размера загрузки, МБ") }
                    C.SpinBox { from: 20; to: 4000; stepSize: 20; value: hub.prefs.maxDownloadMb || 400; editable: true; onValueModified: hub.setPref("maxDownloadMb", value) }
                }
                Txt {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: ThemeBackend.subtext0
                    text: hub.tr("Downloads go to ", "Файлы сохраняются в ") + hub.hubDir + hub.tr(", edited copies to ", ", отредактированные копии — в ") + hub.editedDir + hub.tr(". Files are checked by signature and decoded with ffprobe; nothing downloaded is ever executed.", ". Файлы проверяются по сигнатуре и декодируются ffprobe; скачанное никогда не запускается.")
                }
                Txt { visible: !hub.ffmpegOk; color: ThemeBackend.red; text: hub.tr("ffmpeg/ffprobe not found: download checks, quality analysis and Wallpaper Studio are unavailable.", "ffmpeg/ffprobe не найдены: проверка файлов, анализ качества и Wallpaper Studio недоступны."); Layout.fillWidth: true; wrapMode: Text.Wrap }
            }
        }

        // offline banner
        Rectangle {
            Layout.fillWidth: true
            visible: hub.offline
            implicitHeight: offTxt.implicitHeight + hub.s(16)
            radius: ThemeBackend.borderRadius
            color: Qt.alpha(ThemeBackend.red, 0.14)
            Txt {
                id: offTxt
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: hub.s(8)
                wrapMode: Text.Wrap
                text: hub.tr("Offline: no connection to the wallpaper sources", "Offline: нет подключения к источникам обоев") + (hub.offlineDetail ? " (" + hub.offlineDetail + ")" : "") + hub.tr(". Showing wallpapers you already have; your current wallpaper keeps working. Click to check again.", ". Показаны уже скачанные обои; текущие обои продолжают работать. Нажмите, чтобы проверить снова.")
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: hub.refreshStatus() }
        }

        // download progress
        Rectangle {
            Layout.fillWidth: true
            visible: hub.dlItem !== null
            implicitHeight: hub.s(40)
            radius: ThemeBackend.borderRadius
            color: Qt.alpha(ThemeBackend.surface0, 0.7)
            RowLayout {
                anchors.fill: parent
                anchors.margins: hub.s(8)
                spacing: hub.s(8)
                Txt { Layout.preferredWidth: hub.s(220); text: hub.tr("Downloading ", "Загрузка ") + (hub.dlItem ? hub.dlItem.title : "") }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: hub.s(6)
                    radius: height / 2
                    color: ThemeBackend.surface1
                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: ThemeBackend.mauve
                        width: hub.dlTotal > 0 ? parent.width * Math.min(1, hub.dlDone / hub.dlTotal) : parent.width * 0.15
                    }
                }
                Txt { text: hub.fmtSize(hub.dlDone) + (hub.dlTotal > 0 ? " / " + hub.fmtSize(hub.dlTotal) : "") }
                Btn { label: hub.tr("Cancel", "Отмена"); accent: Qt.alpha(ThemeBackend.red, 0.4); onClicked: hub.cancelDownload() }
            }
        }

        // results / library
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Txt {
                anchors.centerIn: parent
                width: parent.width * 0.8
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: ThemeBackend.subtext0
                visible: !hub.showLibrary && grid.count === 0
                text: hub.searching ? hub.tr("Searching…", "Поиск…")
                    : hub.query === "" ? hub.tr("Type any request in Russian or English and press Enter. Results come live from Wallhaven, Wikimedia Commons, Openverse and, with your keys, Pexels, Pixabay and Giphy.",
                                               "Введите любой запрос на русском или английском и нажмите Enter. Результаты приходят из Wallhaven, Wikimedia Commons, Openverse, а с вашими ключами — из Pexels, Pixabay и Giphy.")
                    : hub.results.length > 0 ? hub.tr("All results are hidden by your quality filters (⚙).", "Все результаты скрыты вашими фильтрами качества (⚙).")
                    : hub.tr("No results. The status of each source is shown above.", "Ничего не найдено. Состояние каждого источника показано выше.")
            }

            GridView {
                id: grid
                anchors.fill: parent
                visible: !hub.showLibrary
                clip: true
                model: hub.visibleResults
                readonly property int cols: Math.max(1, Math.floor(width / hub.s(240)))
                cellWidth: Math.floor(width / cols)
                cellHeight: hub.s(318)
                cacheBuffer: hub.s(320)
                boundsBehavior: Flickable.StopAtBounds
                C.ScrollBar.vertical: C.ScrollBar {}
                onAtYEndChanged: if (atYEnd && contentHeight > height) hub.loadMore()
                footer: Item {
                    width: grid.width
                    height: hub.hasMore || hub.searching ? hub.s(48) : 0
                    Btn {
                        anchors.centerIn: parent
                        visible: (hub.hasMore || hub.searching) && grid.count > 0
                        label: hub.searching ? hub.tr("Loading…", "Загрузка…") : hub.tr("Load more", "Ещё")
                        active: !hub.searching
                        onClicked: hub.loadMore()
                    }
                }
                delegate: Item {
                    id: cell
                    required property var modelData
                    readonly property var r: modelData
                    readonly property var q: hub.qualityById[r.id] || r.quality || null
                    readonly property var pi: hub.probed[r.id] || null
                    readonly property bool isDl: !!hub.downloaded[r.id]
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: hub.s(5)
                        radius: ThemeBackend.borderRadius
                        color: Qt.alpha(ThemeBackend.surface0, 0.6)
                        border.width: 1
                        border.color: cardHover.hovered ? Qt.alpha(ThemeBackend.mauve, 0.6) : Qt.alpha(ThemeBackend.surface2, 0.35)
                        clip: true
                        HoverHandler { id: cardHover }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: hub.s(6)
                            spacing: hub.s(4)

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: hub.s(140)
                                radius: Math.max(0, ThemeBackend.borderRadius - hub.s(4))
                                color: ThemeBackend.mantle
                                clip: true
                                Image {
                                    id: thumbImg
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: hub.s(360)
                                    source: cell.r.thumbCached ? Caching.fileUrl(cell.r.thumbCache) : (cell.r.thumb || "")
                                }
                                Txt {
                                    anchors.centerIn: parent
                                    visible: thumbImg.status !== Image.Ready
                                    color: ThemeBackend.overlay1
                                    text: thumbImg.status === Image.Error ? hub.tr("preview unavailable", "превью недоступно") : "…"
                                }
                                Row {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: hub.s(5)
                                    spacing: hub.s(4)
                                    Badge { label: (cell.r.format || "?").toUpperCase(); tint: ThemeBackend.blue }
                                    Badge { visible: cell.r.kind !== "image"; label: hub.kindLabel(cell.r.kind); tint: ThemeBackend.teal }
                                    Badge { visible: cell.isDl; label: "󰄬"; tint: ThemeBackend.green }
                                }
                                Badge {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: hub.s(5)
                                    visible: cell.q !== null
                                    label: cell.q ? cell.q.label : ""
                                    tint: hub.qualityColor(cell.q ? cell.q.verdict : "")
                                }
                            }

                            Txt { Layout.fillWidth: true; text: cell.r.title || cell.r.id; font.bold: true }
                            Txt {
                                Layout.fillWidth: true
                                color: cell.r.provenance === "verified" ? ThemeBackend.green : ThemeBackend.subtext0
                                text: cell.r.sourceName + " · " + (cell.r.provenance === "verified" ? "Verified Source" : "Source Unknown")
                            }
                            Txt {
                                Layout.fillWidth: true
                                text: hub.resLabel(cell.pi ? cell.pi.width : cell.r.width, cell.pi ? cell.pi.height : cell.r.height) + " · " + hub.fmtSize(cell.pi ? cell.pi.size : cell.r.size) + (cell.r.originalAvailable ? "" : hub.tr(" · reduced copy", " · уменьшенная копия"))
                                color: cell.r.originalAvailable ? ThemeBackend.text : ThemeBackend.peach
                            }
                            Txt {
                                Layout.fillWidth: true
                                visible: cell.r.kind !== "image"
                                color: ThemeBackend.subtext1
                                text: {
                                    let parts = [];
                                    let fps = cell.pi ? cell.pi.fps : cell.r.fps;
                                    let dur = cell.pi ? cell.pi.duration : cell.r.duration;
                                    let br = cell.pi ? cell.pi.bitrate : cell.r.bitrate;
                                    if (fps) parts.push((Math.round(fps * 100) / 100) + " fps");
                                    if (dur) parts.push(hub.fmtDur(dur));
                                    if (cell.r.kind === "video") parts.push(cell.pi && cell.pi.codec ? cell.pi.codec : hub.tr("codec after download", "кодек после загрузки"));
                                    if (br) parts.push(hub.fmtRate(br, !cell.pi && cell.r.bitrateEstimated));
                                    if (cell.pi && cell.r.kind === "animated") parts.push((cell.pi.frames || 0) + hub.tr(" frames", " кадров"));
                                    return parts.join(" · ");
                                }
                            }
                            Item { Layout.fillHeight: true }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                rowSpacing: hub.s(4)
                                columnSpacing: hub.s(4)
                                Btn { Layout.fillWidth: true; icon: "󰈈"; label: hub.tr("Preview", "Просмотр"); onClicked: hub.previewEntry = cell.r }
                                Btn { Layout.fillWidth: true; icon: cell.isDl ? "󰄬" : "󰇚"; label: cell.isDl ? hub.tr("Saved", "Скачано") : hub.tr("Download", "Скачать"); active: !cell.isDl && hub.dlItem === null; onClicked: hub.download(cell.r, "") }
                                Btn { Layout.fillWidth: true; icon: "󰏫"; label: hub.tr("Edit", "Изменить"); active: hub.ffmpegOk && (cell.isDl || hub.dlItem === null); onClicked: hub.download(cell.r, "edit") }
                                Btn { Layout.fillWidth: true; icon: "󰸉"; label: hub.tr("Apply", "Применить"); accent: ThemeBackend.mauve; fg: ThemeBackend.crust; active: cell.isDl || hub.dlItem === null; onClicked: hub.download(cell.r, "apply") }
                            }
                        }
                    }
                }
            }

            // downloaded / offline library
            GridView {
                id: libGrid
                anchors.fill: parent
                visible: hub.showLibrary
                clip: true
                model: hub.library
                readonly property int cols: Math.max(1, Math.floor(width / hub.s(220)))
                cellWidth: Math.floor(width / cols)
                cellHeight: hub.s(232)
                boundsBehavior: Flickable.StopAtBounds
                C.ScrollBar.vertical: C.ScrollBar {}
                header: Txt {
                    width: libGrid.width
                    height: hub.s(28)
                    color: ThemeBackend.subtext0
                    text: hub.library.length === 0 ? hub.tr("No downloaded wallpapers yet.", "Скачанных обоев пока нет.") : hub.tr("Your wallpapers (Wallpaper Hub downloads first):", "Ваши обои (сначала скачанные через Wallpaper Hub):")
                }
                delegate: Item {
                    id: lcell
                    required property var modelData
                    readonly property var it: modelData
                    readonly property var q: hub.qualityById[it.path] || null
                    width: libGrid.cellWidth
                    height: libGrid.cellHeight
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: hub.s(5)
                        radius: ThemeBackend.borderRadius
                        color: Qt.alpha(ThemeBackend.surface0, 0.6)
                        clip: true
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: hub.s(6)
                            spacing: hub.s(4)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: hub.s(120)
                                radius: Math.max(0, ThemeBackend.borderRadius - hub.s(4))
                                color: ThemeBackend.mantle
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    visible: lcell.it.kind !== "video"
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: hub.s(320)
                                    source: lcell.it.kind !== "video" ? Caching.fileUrl(lcell.it.path) : ""
                                }
                                Txt { anchors.centerIn: parent; visible: lcell.it.kind === "video"; text: "󰕧"; font.family: ThemeBackend.iconFont; font.pixelSize: hub.s(34); color: ThemeBackend.overlay1 }
                                Row {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: hub.s(5)
                                    spacing: hub.s(4)
                                    Badge { label: lcell.it.format.toUpperCase(); tint: ThemeBackend.blue }
                                    Badge { visible: lcell.it.edited; label: hub.tr("EDITED", "ИЗМЕНЕНО"); tint: ThemeBackend.peach }
                                }
                                Badge {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: hub.s(5)
                                    visible: lcell.q !== null
                                    label: lcell.q ? lcell.q.label : ""
                                    tint: hub.qualityColor(lcell.q ? lcell.q.verdict : "")
                                }
                            }
                            Txt { Layout.fillWidth: true; text: lcell.it.title; font.bold: true }
                            Txt { Layout.fillWidth: true; color: ThemeBackend.subtext0; text: (lcell.it.source || hub.tr("local file", "локальный файл")) + " · " + hub.fmtSize(lcell.it.size) }
                            Item { Layout.fillHeight: true }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: hub.s(4)
                                Btn { Layout.fillWidth: true; icon: "󰈈"; onClicked: hub.previewEntry = { local: true, path: lcell.it.path, kind: lcell.it.kind, format: lcell.it.format, title: lcell.it.title, id: lcell.it.path, provenance: lcell.it.provenance, provenanceReason: lcell.it.provenanceReason, sourceName: lcell.it.source } }
                                Btn { Layout.fillWidth: true; icon: "󰏫"; active: hub.ffmpegOk; onClicked: hub.studioPath = lcell.it.path }
                                Btn { Layout.fillWidth: true; icon: "󰸉"; label: hub.tr("Apply", "Применить"); accent: ThemeBackend.mauve; fg: ThemeBackend.crust; onClicked: hub.applyPath(lcell.it.path) }
                            }
                        }
                    }
                }
            }
        }
    }

    // toast
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: hub.s(16)
        visible: hub.toast !== ""
        width: Math.min(parent.width - hub.s(40), toastTxt.implicitWidth + hub.s(28))
        height: toastTxt.implicitHeight + hub.s(16)
        radius: Math.min(height / 2, ThemeBackend.borderRadius)
        color: Qt.alpha(ThemeBackend.crust, 0.92)
        z: 50
        Text {
            id: toastTxt
            anchors.centerIn: parent
            width: Math.min(implicitWidth, hub.width - hub.s(68))
            text: hub.toast
            color: ThemeBackend.text
            font.family: ThemeBackend.fontFamily
            font.pixelSize: hub.s(12)
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    }

    // Overlays are created with the hub object as an initial property, so their
    // bindings never see a null hub.
    onPreviewEntryChanged: {
        if (previewEntry === null) previewLoader.source = "";
        else if (previewLoader.status === Loader.Null) previewLoader.setSource(Qt.resolvedUrl("HubPreview.qml"), { "hub": hub });
    }
    onStudioPathChanged: {
        if (studioPath === "") studioLoader.source = "";
        else if (studioLoader.status === Loader.Null) studioLoader.setSource(Qt.resolvedUrl("WallpaperStudio.qml"), { "hub": hub });
    }

    // Preview overlay, loaded by URL: an error here only disables the overlay.
    Loader {
        id: previewLoader
        anchors.fill: parent
        z: 60
        onStatusChanged: {
            if (status === Loader.Error) {
                hub.notify(hub.tr("Preview panel failed to load (is QtMultimedia installed?)", "Панель просмотра не загрузилась (установлен ли QtMultimedia?)"));
                hub.previewEntry = null;
            }
        }
    }

    // Wallpaper Studio overlay, same isolation.
    Loader {
        id: studioLoader
        anchors.fill: parent
        z: 70
        onStatusChanged: {
            if (status === Loader.Error) {
                hub.notify(hub.tr("Wallpaper Studio failed to load (is QtMultimedia installed?)", "Wallpaper Studio не загрузилась (установлен ли QtMultimedia?)"));
                hub.studioPath = "";
            }
        }
    }
}
