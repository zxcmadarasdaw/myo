import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C
import QtMultimedia
import "../../../"

// Search Wallpapers preview: zoomable image, GIF and video playback, real file
// data and the Original Quality Checker. Loaded by WallpaperSearchTab through a
// Loader URL (`hub` is the tab), so a missing QtMultimedia only disables this
// overlay. Sound never starts by itself: video is muted until you unmute it.
Rectangle {
    id: root
    objectName: "searchPreview"
    property var hub: null
    readonly property var e: hub ? WallpaperSearch.resolvedResult(hub.previewEntry) : null
    readonly property bool local: !!(e && e.local)
    readonly property bool external: !!(e && !WallpaperSearch.canFetch(e) && path === "")
    readonly property string path: e ? (local ? e.path : (WallpaperSearch.downloaded[e.id] || "")) : ""
    readonly property string key: e ? (local ? e.path : e.id) : ""
    readonly property var q: key !== "" ? (WallpaperSearch.qualityById[key] || (path !== "" ? WallpaperSearch.qualityById[path] : null) || null) : null
    readonly property var pi: key !== "" ? (WallpaperSearch.probed[key] || (path !== "" ? WallpaperSearch.probed[path] : null) || null) : null
    readonly property string converted: WallpaperSearch.preparedAnimations[path] || ""
    readonly property bool apng: !!(e && (pi?.format || e.format) === "apng")
    readonly property string realKind: e ? (pi?.kind || e.kind) : "image"
    readonly property string kind: converted !== "" ? "video" : apng ? "image" : realKind
    readonly property var savedFavorite: e ? WallpaperSearch.favorites[e.id] || null : null

    // What is on screen: the downloaded original, the remote original (on demand)
    // or the source's own preview rendition.
    property bool wantOriginal: false
    property bool wantVideoStream: false
    readonly property string imageUrl: {
        if (!e) return "";
        if (path !== "") return Caching.fileUrl(path);
        if (wantOriginal) return e.url || "";
        let cached = WallpaperSearch.thumbFor(e);
        // never pull a large original just to preview; "Load original" does that on request
        if (e.thumbHelper) return cached !== "" ? Caching.fileUrl(cached) : "";
        return e.preview || e.thumb || "";
    }
    readonly property string animUrl: !e ? "" : (path !== "" ? Caching.fileUrl(path) : (e.previewAnimation || e.url || ""))
    readonly property string videoUrl: {
        if (!e) return "";
        if (converted !== "") return Caching.fileUrl(converted);
        if (external) return "";
        if (path !== "") return Caching.fileUrl(path);
        if (e.previewVideo) return e.previewVideo;
        return wantVideoStream ? (e.url || "") : "";
    }
    readonly property string showing: path !== "" ? "local"
                                     : kind === "image" ? (wantOriginal ? "remote-original" : "preview")
                                     : kind === "video" ? (e && e.previewVideo ? "preview-video" : (wantVideoStream ? "remote-original" : "poster"))
                                     : "remote-original"

    function tr(en, ru) { return WallpaperSearch.tr(en, ru); }
    function s(v) { return hub ? hub.s(v) : v; }
    function close() { hub.previewEntry = null; }
    function openApng() {
        if (path !== "") WallpaperSearch.prepareAnimation(path, "");
        else WallpaperSearch.download(e, "preview-animation");
    }

    color: ThemeBackend.crust
    focus: true
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: (ev) => { root.close(); ev.accepted = true; }
    Keys.onSpacePressed: (ev) => { root.togglePlay(); ev.accepted = true; }
    Keys.onLeftPressed: (ev) => {
        ev.accepted = ev.modifiers === Qt.NoModifier;
        if (ev.accepted) root.hub.stepPreview(-1);
    }
    Keys.onRightPressed: (ev) => {
        ev.accepted = ev.modifiers === Qt.NoModifier;
        if (ev.accepted) root.hub.stepPreview(1);
    }
    // Block clicks and wheel from reaching the tab underneath.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = true }

    component Txt: Text {
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: root.s(12)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component Tool: Rectangle {
        id: tool
        property string label: ""
        property string icon: ""
        property bool on: false
        property bool active: true
        property bool primary: false
        signal clicked()
        implicitHeight: root.s(32)
        implicitWidth: toolRow.implicitWidth + root.s(label !== "" ? 20 : 14)
        radius: root.s(9)
        opacity: active ? 1 : 0.45
        color: primary ? (toolMa.containsMouse && active ? Qt.lighter(ThemeBackend.mauve, 1.1) : ThemeBackend.mauve)
             : on ? Qt.alpha(ThemeBackend.mauve, 0.3)
             : (toolMa.containsMouse && active ? Qt.alpha(ThemeBackend.text, 0.14) : Qt.alpha(ThemeBackend.surface1, 0.85))
        Behavior on color { ColorAnimation { duration: 110 } }
        Row {
            id: toolRow
            anchors.centerIn: parent
            spacing: root.s(6)
            Text { visible: tool.icon !== ""; text: tool.icon; color: tool.primary ? ThemeBackend.crust : ThemeBackend.text; font.family: ThemeBackend.iconFont; font.pixelSize: root.s(15); anchors.verticalCenter: parent.verticalCenter }
            Text { visible: tool.label !== ""; text: tool.label; color: tool.primary ? ThemeBackend.crust : ThemeBackend.text; font.family: ThemeBackend.fontFamily; font.pixelSize: root.s(12); font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: toolMa; anchors.fill: parent; hoverEnabled: true; cursorShape: tool.active ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (tool.active) tool.clicked() }
    }

    // ------------------------------------------------------------------ zoom
    property real zoom: 1
    property bool fitMode: true
    readonly property real srcW: still.implicitWidth > 0 ? still.implicitWidth : 1
    readonly property real srcH: still.implicitHeight > 0 ? still.implicitHeight : 1
    readonly property real fitZoom: Math.min(viewer.width / srcW, viewer.height / srcH)
    readonly property real shownZoom: fitMode ? fitZoom : zoom
    function setZoom(z, cx, cy) {
        let old = shownZoom;
        let nz = Math.max(Math.min(fitZoom, 1) * 0.5, Math.min(8, z));
        let px = (viewer.contentX + (cx === undefined ? viewer.width / 2 : cx)) / old;
        let py = (viewer.contentY + (cy === undefined ? viewer.height / 2 : cy)) / old;
        fitMode = false;
        zoom = nz;
        viewer.contentX = Math.max(0, px * nz - (cx === undefined ? viewer.width / 2 : cx));
        viewer.contentY = Math.max(0, py * nz - (cy === undefined ? viewer.height / 2 : cy));
    }
    function oneToOne() {
        if (path === "" && !wantOriginal) wantOriginal = true;
        pendingOneToOne = true;
        if (still.status === Image.Ready && (path !== "" || still.source.toString() === e.url)) applyOneToOne();
    }
    property bool pendingOneToOne: false
    function applyOneToOne() {
        pendingOneToOne = false;
        setZoom(1);
    }

    // ------------------------------------------------------------------ playback
    property bool loopOn: true
    property bool muted: true
    property bool paused: false
    onKeyChanged: {
        fitMode = true;
        wantOriginal = false;
        wantVideoStream = false;
        pendingOneToOne = false;
        paused = false;
        muted = true;
        if (videoErr) videoErr.text = "";
        if (collectionField) collectionField.text = savedFavorite?.collection || "";
    }
    function togglePlay() {
        if (kind === "video") { if (video.playbackState === MediaPlayer.PlayingState) video.pause(); else video.play(); }
        else if (kind === "animated") paused = !paused;
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.s(14)
        spacing: root.s(14)

        // ------------------------------------------------------------ media
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.s(8)

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.s(14)
                color: ThemeBackend.mantle
                clip: true

                // still images: zoom with the wheel, drag to pan
                Flickable {
                    id: viewer
                    anchors.fill: parent
                    visible: root.kind === "image"
                    contentWidth: Math.max(width, root.srcW * root.shownZoom)
                    contentHeight: Math.max(height, root.srcH * root.shownZoom)
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    interactive: !root.fitMode
                    Image {
                        id: still
                        objectName: "previewImage"
                        width: root.srcW * root.shownZoom
                        height: root.srcH * root.shownZoom
                        x: Math.max(0, (viewer.contentWidth - width) / 2)
                        y: Math.max(0, (viewer.contentHeight - height) / 2)
                        asynchronous: true
                        cache: false
                        smooth: root.shownZoom < 1
                        mipmap: root.shownZoom < 0.5
                        source: root.kind === "image" ? root.imageUrl : ""
                        onStatusChanged: if (status === Image.Ready && root.pendingOneToOne) root.applyOneToOne()
                    }
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (ev) => root.setZoom(root.shownZoom * (ev.angleDelta.y > 0 ? 1.18 : 1 / 1.18), ev.x - viewer.contentX, ev.y - viewer.contentY)
                    }
                }

                AnimatedImage {
                    id: anim
                    anchors.fill: parent
                    visible: root.kind === "animated"
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    playing: visible && !root.paused
                    source: root.kind === "animated" ? root.animUrl : ""
                    onCurrentFrameChanged: if (!root.loopOn && frameCount > 1 && currentFrame === frameCount - 1) root.paused = true
                }

                Image {
                    id: poster
                    anchors.fill: parent
                    visible: root.kind === "video" && root.videoUrl === ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: root.kind === "video" && root.e ? (root.e.thumbHelper ? Caching.fileUrl(WallpaperSearch.thumbFor(root.e)) : (root.e.preview || root.e.thumb || "")) : ""
                }
                Video {
                    id: video
                    objectName: "previewVideo"
                    anchors.fill: parent
                    visible: root.kind === "video" && root.videoUrl !== ""
                    fillMode: VideoOutput.PreserveAspectFit
                    loops: root.loopOn ? MediaPlayer.Infinite : 1
                    muted: root.muted
                    source: root.kind === "video" ? root.videoUrl : ""
                    onSourceChanged: if (source.toString() !== "") play()
                    onErrorOccurred: (err, msg) => videoErr.text = msg
                }
                Txt {
                    id: videoErr
                    anchors.centerIn: parent
                    width: parent.width * 0.8
                    horizontalAlignment: Text.AlignHCenter
                    color: ThemeBackend.red
                    visible: text !== "" && root.kind === "video"
                }
                Column {
                    anchors.centerIn: parent
                    spacing: root.s(8)
                    visible: root.showing === "poster"
                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.e?.id === WallpaperSearch.resolvingPeer ? root.tr("Checking available video…", "Проверяем доступные варианты видео…")
                             : root.external ? root.tr("Video plays on the source page.", "Видео воспроизводится на странице источника.")
                                            : root.tr("This source has no small preview clip.", "У источника нет маленького превью-ролика.")
                        color: ThemeBackend.subtext1
                    }
                    Tool {
                        objectName: "streamOriginal"
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !root.external
                        icon: "󰐊"
                        label: root.tr("Stream the original", "Воспроизвести оригинал") + (root.e && root.e.size ? " (" + WallpaperSearch.fmtSize(root.e.size) + ")" : "")
                        onClicked: root.wantVideoStream = true
                    }
                    Tool {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.external && !!(root.e && root.e.pageUrl)
                        label: root.tr("Open source", "Открыть источник")
                        onClicked: Qt.openUrlExternally(root.e.pageUrl)
                    }
                }
                Txt {
                    anchors.centerIn: parent
                    color: ThemeBackend.overlay1
                    visible: (root.kind === "image" && still.status === Image.Loading) || (root.kind === "animated" && anim.status === AnimatedImage.Loading)
                    text: root.tr("Loading…", "Загрузка…") + (root.kind === "image" && still.progress > 0 ? " " + Math.round(still.progress * 100) + "%" : "")
                }
                Txt {
                    anchors.centerIn: parent
                    color: ThemeBackend.red
                    visible: (root.kind === "image" && still.status === Image.Error) || (root.kind === "animated" && anim.status === AnimatedImage.Error)
                    text: root.tr("This file could not be shown.", "Этот файл не удалось показать.")
                }
                Txt {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - root.s(40), root.s(420))
                    horizontalAlignment: Text.AlignHCenter
                    color: ThemeBackend.subtext0
                    visible: root.kind === "image" && root.imageUrl === "" && !!root.e && !!root.e.thumbHelper
                    text: WallpaperSearch.thumbFailed(root.e)
                          ? root.tr("The source did not deliver a preview; the file may have been removed there. “Load original” checks it.",
                                    "Источник не отдал превью — возможно, файл у него удалён. «Загрузить оригинал» это проверит.")
                          : root.tr("Loading the preview…", "Загрузка превью…")
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: root.s(8)
                    radius: root.s(7)
                    color: Qt.alpha(ThemeBackend.crust, 0.8)
                    implicitWidth: showTxt.implicitWidth + root.s(14)
                    implicitHeight: showTxt.implicitHeight + root.s(8)
                    Txt {
                        id: showTxt
                        anchors.centerIn: parent
                        wrapMode: Text.NoWrap
                        color: ThemeBackend.subtext1
                        font.pixelSize: root.s(11)
                        text: ({
                            "local": root.tr("Downloaded original", "Скачанный оригинал"),
                            "remote-original": root.tr("Original from the source", "Оригинал из источника"),
                            "preview": root.tr("Source preview (reduced) — use 1:1 for the original", "Превью источника (уменьшено) — 1:1 покажет оригинал"),
                            "preview-video": root.tr("Small preview clip — the original is downloaded on Apply", "Маленький превью-ролик — оригинал скачивается при установке"),
                            "poster": root.tr("Poster frame", "Кадр-обложка")
                        })[root.showing] + (root.kind === "image" && still.status === Image.Ready ? " · " + Math.round(still.implicitWidth) + "×" + Math.round(still.implicitHeight) + " · " + Math.round(root.shownZoom * 100) + "%" : "")
                    }
                }
            }

            // controls
            RowLayout {
                Layout.fillWidth: true
                spacing: root.s(6)
                Tool {
                    objectName: "cinemaPrev"
                    visible: root.hub && root.hub.previewIndex >= 0
                    label: "‹"
                    active: visible && root.hub.previewIndex > 0
                    onClicked: root.hub.stepPreview(-1)
                }
                Tool {
                    objectName: "cinemaNext"
                    visible: root.hub && root.hub.previewIndex >= 0
                    label: "›"
                    active: visible && root.hub.previewIndex + 1 < WallpaperSearch.results.count
                    onClicked: root.hub.stepPreview(1)
                }
                Tool { visible: root.kind === "image"; label: root.tr("Fit", "Вписать"); on: root.fitMode; onClicked: root.fitMode = true }
                Tool { visible: root.kind === "image" && !root.external; objectName: "oneToOne"; label: "1:1"; on: !root.fitMode && Math.abs(root.zoom - 1) < 0.01; onClicked: root.oneToOne() }
                Tool { visible: root.kind === "image"; icon: "󰛭"; onClicked: root.setZoom(root.shownZoom / 1.25) }
                Tool { visible: root.kind === "image"; icon: "󰛮"; onClicked: root.setZoom(root.shownZoom * 1.25) }
                Tool {
                    visible: root.kind === "image" && !root.external && root.path === "" && !root.wantOriginal
                    label: root.tr("Load original", "Загрузить оригинал") + (root.e && root.e.size ? " · " + WallpaperSearch.fmtSize(root.e.size) : "")
                    onClicked: root.wantOriginal = true
                }
                Tool {
                    visible: root.apng && root.converted === "" && !root.external
                    label: root.tr("Play animation", "Воспроизвести анимацию")
                    icon: "󰐊"
                    active: !WallpaperSearch.preparing && !WallpaperSearch.downloading
                    onClicked: root.openApng()
                }
                Tool {
                    visible: root.kind !== "image" && (!root.external || root.animUrl !== "")
                    objectName: "playPause"
                    icon: (root.kind === "video" ? video.playbackState === MediaPlayer.PlayingState : !root.paused) ? "󰏤" : "󰐊"
                    label: (root.kind === "video" ? video.playbackState === MediaPlayer.PlayingState : !root.paused) ? root.tr("Pause", "Пауза") : root.tr("Play", "Играть")
                    active: root.kind !== "video" || root.videoUrl !== ""
                    onClicked: root.togglePlay()
                }
                Tool { visible: root.kind !== "image" && (!root.external || root.animUrl !== ""); objectName: "loopToggle"; icon: "󰑖"; label: root.tr("Loop", "Повтор"); on: root.loopOn; onClicked: { root.loopOn = !root.loopOn; if (root.loopOn) root.paused = false; } }
                Tool { visible: root.kind === "video" && !root.external; objectName: "muteToggle"; icon: root.muted ? "󰖁" : "󰕾"; on: !root.muted; onClicked: root.muted = !root.muted }
                C.Slider {
                    Layout.fillWidth: true
                    visible: root.kind === "video" && video.duration > 0
                    from: 0
                    to: Math.max(1, video.duration)
                    value: video.position
                    onMoved: video.position = value
                }
                Txt {
                    visible: root.kind === "video" && video.duration > 0
                    wrapMode: Text.NoWrap
                    color: ThemeBackend.subtext0
                    text: WallpaperSearch.fmtDur(video.position / 1000) + " / " + WallpaperSearch.fmtDur(video.duration / 1000)
                }
                Txt {
                    visible: root.kind === "animated" && anim.frameCount > 0
                    wrapMode: Text.NoWrap
                    color: ThemeBackend.subtext0
                    text: root.tr("frame ", "кадр ") + (anim.currentFrame + 1) + " / " + anim.frameCount
                }
                Item { Layout.fillWidth: root.kind === "image" }
            }
        }

        // ------------------------------------------------------------ details
        Flickable {
            Layout.preferredWidth: root.s(350)
            Layout.fillHeight: true
            contentHeight: info.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: C.ScrollBar {}

            ColumnLayout {
                id: info
                width: parent.width - root.s(8)
                spacing: root.s(6)

                RowLayout {
                    Layout.fillWidth: true
                    Txt { Layout.fillWidth: true; text: root.e ? (root.e.title || root.e.id) : ""; font.pixelSize: root.s(15); font.bold: true; maximumLineCount: 3; elide: Text.ElideRight }
                    Tool { objectName: "previewClose"; icon: "󰅖"; onClicked: root.close() }
                }
                Txt { Layout.fillWidth: true; color: ThemeBackend.subtext0; text: root.e ? (root.e.sourceName || "") + (root.e.author ? " · " + root.e.author : "") + (root.e.license ? " · " + root.e.license : "") : "" }
                Rectangle {
                    visible: root.e?.source === "giphy"
                    implicitWidth: root.s(117)
                    implicitHeight: root.s(28)
                    radius: root.s(5)
                    color: "#161616"
                    Image { anchors.fill: parent; anchors.margins: 2; fillMode: Image.PreserveAspectFit; source: parent.visible ? Qt.resolvedUrl("PoweredByGiphy.png") : "" }
                }
                Txt {
                    Layout.fillWidth: true
                    visible: !!(root.e && root.e.pageUrl)
                    color: ThemeBackend.blue
                    font.underline: true
                    text: root.e && root.e.pageUrl ? root.e.pageUrl : ""
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(root.e.pageUrl) }
                }

                Txt { text: root.tr("File", "Файл"); font.bold: true; Layout.topMargin: root.s(6) }
                Txt {
                    objectName: "fileInfo"
                    Layout.fillWidth: true
                    text: {
                        if (!root.e) return "";
                        let w = root.pi ? root.pi.width : root.e.width, h = root.pi ? root.pi.height : root.e.height;
                        let lines = [root.tr("Resolution: ", "Разрешение: ") + WallpaperSearch.resLabel(w, h) + (root.pi ? root.tr(" (measured in the file)", " (измерено в файле)") : root.tr(" (reported by the source)", " (по данным источника)")),
                                     root.tr("Format: ", "Формат: ") + ((root.pi ? root.pi.format : root.e.format) || "?").toUpperCase() + " · " + WallpaperSearch.kindLabel(root.realKind),
                                     root.tr("Size: ", "Размер: ") + WallpaperSearch.fmtSize(root.pi ? root.pi.size : root.e.size)];
                        if (root.pi && root.pi.bitDepth) lines.push(root.tr("Colour depth: ", "Глубина цвета: ") + root.pi.bitDepth + root.tr(" bit per channel", " бит на канал") + (root.pi.pixFmt ? " (" + root.pi.pixFmt + ")" : ""));
                        if (root.realKind !== "image") {
                            let fps = root.pi ? root.pi.fps : root.e.fps, dur = root.pi ? root.pi.duration : root.e.duration, br = root.pi ? root.pi.bitrate : root.e.bitrate;
                            lines.push("FPS: " + (fps ? Math.round(fps * 100) / 100 : root.tr("known after download", "известно после загрузки")));
                            lines.push(root.tr("Duration: ", "Длительность: ") + (dur ? WallpaperSearch.fmtDur(dur) : root.tr("unknown", "неизвестно")));
                            if (root.realKind === "video") lines.push(root.tr("Codec: ", "Кодек: ") + (root.pi && root.pi.codec ? root.pi.codec : root.tr("known after download", "известен после загрузки")));
                            lines.push(root.tr("Bitrate: ", "Битрейт: ") + (br ? WallpaperSearch.fmtRate(br, !root.pi && root.e.bitrateEstimated) : root.tr("unknown", "неизвестно")));
                            if (root.pi && root.pi.frames) lines.push(root.tr("Frames: ", "Кадров: ") + root.pi.frames);
                        }
                        if (root.e.created) lines.push(root.tr("Uploaded: ", "Загружено: ") + root.e.created.slice(0, 10));
                        if (root.e.favorites || root.e.views) lines.push(root.tr("Popularity: ", "Популярность: ") + (root.e.favorites || 0) + root.tr(" favourites, ", " в избранном, ") + (root.e.views || 0) + root.tr(" views", " просмотров"));
                        if (root.pi && root.pi.tags) {
                            let t = Object.keys(root.pi.tags).slice(0, 4).map(k => k + "=" + root.pi.tags[k]);
                            if (t.length) lines.push(root.tr("Metadata: ", "Метаданные: ") + t.join(", "));
                        }
                        return lines.join("\n");
                    }
                }
                Repeater {
                    model: root.e && root.e.notes ? root.e.notes : []
                    delegate: Txt { required property string modelData; Layout.fillWidth: true; color: ThemeBackend.peach; text: "• " + modelData }
                }

                Txt { text: root.tr("Original Quality Checker", "Проверка качества оригинала"); font.bold: true; Layout.topMargin: root.s(8) }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: provTxt.implicitHeight + root.s(12)
                    radius: root.s(8)
                    color: Qt.alpha(root.e && root.e.provenance === "verified" ? ThemeBackend.green : ThemeBackend.overlay1, 0.16)
                    Txt {
                        id: provTxt
                        anchors.fill: parent
                        anchors.margins: root.s(6)
                        text: root.e ? ((root.e.provenance === "verified" ? "Verified Source — " : "Source Unknown — ") + (root.e.provenanceReason || root.tr("no reliable origin data", "нет достоверных данных о происхождении"))) : ""
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.q !== null
                    implicitHeight: qCol.implicitHeight + root.s(12)
                    radius: root.s(8)
                    color: Qt.alpha(!root.q ? ThemeBackend.overlay1 : root.q.verdict === "upscale" ? ThemeBackend.red : root.q.verdict === "lowdetail" ? ThemeBackend.peach : root.q.verdict === "ok" ? ThemeBackend.green : ThemeBackend.overlay1, 0.16)
                    ColumnLayout {
                        id: qCol
                        anchors.fill: parent
                        anchors.margins: root.s(6)
                        spacing: root.s(3)
                        Txt { Layout.fillWidth: true; font.bold: true; text: root.q ? root.q.label : "" }
                        Repeater {
                            model: root.q && root.q.reasons ? root.q.reasons : []
                            delegate: Txt { required property string modelData; Layout.fillWidth: true; text: "• " + modelData }
                        }
                        Txt { Layout.fillWidth: true; color: ThemeBackend.subtext0; font.pixelSize: root.s(11); text: root.q && root.q.note ? root.q.note : "" }
                    }
                }
                Txt {
                    Layout.fillWidth: true
                    visible: root.q === null
                    color: ThemeBackend.subtext0
                    font.pixelSize: root.s(11)
                    text: root.tr("Not analysed yet. The check downloads this one original and measures detail at several scales, compression blocks and metadata. A big resolution alone never proves an original: an enlarged picture is reported as a possible upscale.",
                                  "Ещё не проверено. Проверка скачивает только этот оригинал и измеряет детализацию на нескольких масштабах, блоки сжатия и метаданные. Большое разрешение само по себе не доказывает оригинальность: увеличенная картинка помечается как возможный апскейл.")
                }
                Tool {
                    Layout.fillWidth: true
                    visible: !root.external
                    active: !WallpaperSearch.qualityBusy && (root.path !== "" || !WallpaperSearch.downloading)
                    label: WallpaperSearch.qualityBusy ? root.tr("Analysing…", "Анализ…") : root.tr("Check original quality", "Проверить качество оригинала")
                    onClicked: {
                        if (root.path !== "") WallpaperSearch.checkQuality(root.path, root.local ? null : root.e);
                        else WallpaperSearch.download(root.e, "quality");
                    }
                }
                Tool {
                    Layout.fillWidth: true
                    visible: root.external && root.kind !== "video" && !!root.e?.pageUrl
                    label: root.tr("Open source", "Открыть источник")
                    onClicked: Qt.openUrlExternally(root.e.pageUrl)
                }

                RowLayout {
                    Layout.fillWidth: true
                    C.TextField {
                        id: collectionField
                        Layout.fillWidth: true
                        placeholderText: root.tr("Collection (optional)", "Коллекция (необязательно)")
                        maximumLength: 60
                        text: root.savedFavorite?.collection || ""
                        onAccepted: if (root.e) WallpaperSearch.saveFavorite(root.e, text, false)
                    }
                    Tool {
                        objectName: "previewFavorite"
                        label: root.savedFavorite ? root.tr("Saved", "В избранном") : root.tr("Favorite", "В избранное")
                        icon: root.savedFavorite ? "󰓎" : "󰓒"
                        active: !WallpaperSearch.favoriteBusy
                        onClicked: {
                            const collection = collectionField.text.trim();
                            WallpaperSearch.saveFavorite(root.e, collection, !!root.savedFavorite && root.savedFavorite.collection === collection);
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: root.s(8)
                    columns: 2
                    visible: !root.external
                    columnSpacing: root.s(6)
                    rowSpacing: root.s(6)
                    Tool {
                        Layout.fillWidth: true
                        visible: !root.local
                        objectName: "previewDownload"
                        icon: root.path !== "" ? "󰄬" : "󰇚"
                        active: root.path === "" && !WallpaperSearch.downloading
                        label: root.path !== "" ? root.tr("Downloaded", "Скачано") : root.e?.originalAvailable === false ? root.tr("Download copy", "Скачать копию") : root.tr("Download original", "Скачать оригинал")
                        onClicked: WallpaperSearch.download(root.e, "")
                    }
                    Tool {
                        Layout.fillWidth: true
                        objectName: "previewEdit"
                        icon: "󰏫"
                        active: WallpaperSearch.ffmpegOk && (root.path !== "" || !WallpaperSearch.downloading)
                        label: root.tr("Edit in Studio", "Открыть в Studio")
                        onClicked: {
                            if (root.path !== "") { root.hub.studioPath = root.path; root.close(); }
                            else { WallpaperSearch.download(root.e, "edit"); root.close(); }
                        }
                    }
                    Tool {
                        Layout.fillWidth: true
                        Layout.columnSpan: root.local ? 1 : 2
                        objectName: "previewApply"
                        primary: true
                        icon: "󰸉"
                        active: root.path !== "" || !WallpaperSearch.downloading
                        label: root.tr("Apply as wallpaper", "Установить обоями")
                        onClicked: { if (root.path !== "") root.hub.applyPath(root.path); else WallpaperSearch.download(root.e, "apply"); }
                    }
                }
                Txt {
                    Layout.fillWidth: true
                    visible: WallpaperSearch.downloading && WallpaperSearch.dlItem && root.e && WallpaperSearch.dlItem.id === root.e.id
                    color: ThemeBackend.mauve
                    text: root.tr("Downloading… ", "Загрузка… ") + WallpaperSearch.fmtSize(WallpaperSearch.dlDone) + (WallpaperSearch.dlTotal > 0 ? " / " + WallpaperSearch.fmtSize(WallpaperSearch.dlTotal) : "")
                }
            }
        }
    }
}
