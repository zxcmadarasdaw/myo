import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C
import QtMultimedia
import "../../../"

// Wallpaper Hub preview + Original Quality Checker report.
// Loaded by WallpaperHubTab through a Loader URL; `hub` is that tab.
Rectangle {
    id: root
    property var hub: null
    readonly property var e: hub ? hub.previewEntry : null
    readonly property bool local: !!(e && e.local)
    readonly property string path: e ? (local ? e.path : (hub.downloaded[e.id] || "")) : ""
    readonly property string key: e ? (local ? e.path : e.id) : ""
    readonly property var q: hub && key !== "" ? (hub.qualityById[key] || (path !== "" ? hub.qualityById[path] : null) || null) : null
    readonly property var pi: hub && key !== "" ? (hub.probed[key] || (path !== "" ? hub.probed[path] : null) || null) : null
    readonly property string kind: e ? (pi && pi.kind ? pi.kind : e.kind) : "image"
    readonly property string mediaUrl: {
        if (!e) return "";
        if (path !== "") return Caching.fileUrl(path);
        if (kind === "image") return e.preview || e.thumb || "";
        return e.url || "";
    }
    function tr(en, ru) { return hub ? hub.tr(en, ru) : en; }
    function s(v) { return hub ? hub.s(v) : v; }

    color: Qt.alpha(ThemeBackend.crust, 0.94)
    radius: ThemeBackend.borderRadius
    focus: true
    Keys.onEscapePressed: (ev) => { hub.previewEntry = null; ev.accepted = true; }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = true }

    component Txt: Text {
        color: ThemeBackend.text
        font.family: ThemeBackend.fontFamily
        font.pixelSize: root.s(12)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component Act: C.Button {
        font.family: ThemeBackend.fontFamily
        palette.button: ThemeBackend.surface1
        palette.buttonText: ThemeBackend.text
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.s(14)
        spacing: root.s(14)

        // media
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ThemeBackend.borderRadius
            color: ThemeBackend.mantle
            clip: true

            Image {
                id: still
                anchors.fill: parent
                visible: root.kind === "image"
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: 1920
                source: root.kind === "image" ? root.mediaUrl : ""
            }
            AnimatedImage {
                id: anim
                anchors.fill: parent
                visible: root.kind === "animated"
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                playing: visible
                source: root.kind === "animated" ? root.mediaUrl : ""
            }
            Video {
                id: video
                anchors.fill: parent
                visible: root.kind === "video"
                fillMode: VideoOutput.PreserveAspectFit
                loops: MediaPlayer.Infinite
                muted: true
                source: root.kind === "video" ? root.mediaUrl : ""
                Component.onCompleted: if (root.kind === "video") play()
                onErrorOccurred: (err, msg) => videoErr.text = msg
            }
            Txt {
                id: videoErr
                anchors.centerIn: parent
                width: parent.width * 0.8
                horizontalAlignment: Text.AlignHCenter
                color: ThemeBackend.red
                visible: text !== ""
            }
            Txt {
                anchors.centerIn: parent
                color: ThemeBackend.overlay1
                visible: (root.kind === "image" && still.status === Image.Loading) || (root.kind === "animated" && anim.status === AnimatedImage.Loading)
                text: root.tr("Loading preview…", "Загрузка превью…")
            }
            Txt {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: root.s(8)
                color: ThemeBackend.subtext0
                font.pixelSize: root.s(11)
                text: root.path !== "" ? root.tr("Showing the downloaded original", "Показан скачанный оригинал")
                    : root.kind === "image" ? root.tr("Showing the source's preview size, not the original file", "Показано превью источника, а не оригинальный файл")
                    : root.tr("Streaming the original from the source", "Оригинал воспроизводится по сети")
            }
        }

        // details + quality checker
        Flickable {
            Layout.preferredWidth: root.s(340)
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
                    Txt { Layout.fillWidth: true; text: root.e ? (root.e.title || root.e.id) : ""; font.pixelSize: root.s(15); font.bold: true }
                    Act { text: "✕"; onClicked: root.hub.previewEntry = null }
                }
                Txt { Layout.fillWidth: true; color: ThemeBackend.subtext0; text: root.e ? (root.e.sourceName || "") + (root.e.author ? " · " + root.e.author : "") + (root.e.license ? " · " + root.e.license : "") : "" }
                Txt {
                    Layout.fillWidth: true
                    visible: root.e && !!root.e.pageUrl
                    color: ThemeBackend.blue
                    text: root.e && root.e.pageUrl ? root.e.pageUrl : ""
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(root.e.pageUrl) }
                }

                Txt { text: root.tr("File", "Файл"); font.bold: true; Layout.topMargin: root.s(6) }
                Txt {
                    Layout.fillWidth: true
                    text: {
                        if (!root.e) return "";
                        let w = root.pi ? root.pi.width : root.e.width, h = root.pi ? root.pi.height : root.e.height;
                        let lines = [root.tr("Resolution: ", "Разрешение: ") + root.hub.resLabel(w, h) + (root.pi ? root.tr(" (measured)", " (измерено)") : root.tr(" (reported by source)", " (по данным источника)")),
                                     root.tr("Format: ", "Формат: ") + ((root.pi ? root.pi.format : root.e.format) || "?").toUpperCase() + " · " + root.hub.kindLabel(root.kind),
                                     root.tr("Size: ", "Размер: ") + root.hub.fmtSize(root.pi ? root.pi.size : root.e.size)];
                        if (root.pi && root.pi.bitDepth) lines.push(root.tr("Colour depth: ", "Глубина цвета: ") + root.pi.bitDepth + root.tr(" bit per channel", " бит на канал") + (root.pi.pixFmt ? " (" + root.pi.pixFmt + ")" : ""));
                        if (root.kind !== "image") {
                            let fps = root.pi ? root.pi.fps : root.e.fps, dur = root.pi ? root.pi.duration : root.e.duration, br = root.pi ? root.pi.bitrate : root.e.bitrate;
                            lines.push("FPS: " + (fps ? Math.round(fps * 100) / 100 : root.tr("unknown until downloaded", "неизвестно до загрузки")));
                            lines.push(root.tr("Duration: ", "Длительность: ") + (dur ? root.hub.fmtDur(dur) : root.tr("unknown", "неизвестно")));
                            if (root.kind === "video") lines.push(root.tr("Codec: ", "Кодек: ") + (root.pi && root.pi.codec ? root.pi.codec : root.tr("unknown until downloaded", "неизвестно до загрузки")));
                            lines.push(root.tr("Bitrate: ", "Битрейт: ") + (br ? root.hub.fmtRate(br, !root.pi && root.e.bitrateEstimated) : root.tr("unknown", "неизвестно")));
                            if (root.pi && root.pi.frames) lines.push(root.tr("Frames: ", "Кадров: ") + root.pi.frames);
                        }
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

                Txt { text: "Original Quality Checker"; font.bold: true; Layout.topMargin: root.s(8) }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: provTxt.implicitHeight + root.s(12)
                    radius: root.s(6)
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
                    radius: root.s(6)
                    color: Qt.alpha(root.hub ? root.hub.qualityColor(root.q ? root.q.verdict : "") : ThemeBackend.overlay1, 0.16)
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
                    text: root.tr("Not analysed yet. The check downloads this one original and measures detail at several scales, compression blocks and metadata. A resolution alone never makes a file \"Verified\".",
                                  "Ещё не проверено. Проверка скачивает только этот оригинал и измеряет детализацию на нескольких масштабах, блоки сжатия и метаданные. Одно разрешение никогда не делает файл «Verified».")
                }
                Act {
                    Layout.fillWidth: true
                    enabled: root.hub && !root.hub.qualityBusy && (root.path !== "" || root.hub.dlItem === null)
                    text: root.hub && root.hub.qualityBusy ? root.tr("Analysing…", "Анализ…") : root.tr("Check original quality", "Проверить качество оригинала")
                    onClicked: {
                        if (root.path !== "") root.hub.checkQuality(root.path, root.local ? null : root.e);
                        else root.hub.download(root.e, "quality");
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: root.s(8)
                    columns: 2
                    Act { Layout.fillWidth: true; visible: !root.local; enabled: root.path === "" && root.hub && root.hub.dlItem === null; text: root.path !== "" ? root.tr("Downloaded", "Скачано") : root.tr("Download", "Скачать"); onClicked: root.hub.download(root.e, "") }
                    Act {
                        Layout.fillWidth: true
                        enabled: root.hub && root.hub.ffmpegOk
                        text: root.tr("Edit in Studio", "Открыть в Studio")
                        onClicked: { if (root.path !== "") { root.hub.studioPath = root.path; root.hub.previewEntry = null; } else { root.hub.download(root.e, "edit"); root.hub.previewEntry = null; } }
                    }
                    Act {
                        Layout.fillWidth: true
                        Layout.columnSpan: root.local ? 1 : 2
                        text: root.tr("Apply as wallpaper", "Установить обоями")
                        palette.button: ThemeBackend.mauve
                        palette.buttonText: ThemeBackend.crust
                        onClicked: { if (root.path !== "") root.hub.applyPath(root.path); else root.hub.download(root.e, "apply"); }
                    }
                }
            }
        }
    }
}
