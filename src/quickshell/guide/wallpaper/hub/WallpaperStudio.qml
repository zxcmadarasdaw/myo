import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C
import QtQuick.Effects
import QtMultimedia
import Quickshell.Io
import "../../../"

// Wallpaper Studio: edits one wallpaper file into a new copy.
// The original is never modified; results go to <wallpaper dir>/Wallpaper Hub/Edited.
// The live view is an approximation (Qt effects); "Exact preview" renders the
// real ffmpeg result that "Save copy" will produce.
Rectangle {
    id: root
    property var hub: null
    readonly property string path: hub ? hub.studioPath : ""
    property var info: null
    property string status: ""
    property string previewPath: ""
    property string savedPath: ""
    readonly property bool motion: info !== null && (info.kind === "video" || info.kind === "animated")
    readonly property bool isVideo: info !== null && info.kind === "video"
    readonly property real duration: info && info.duration ? info.duration : 0

    // edit parameters (same names as wallhub.py edit --params)
    property real zoom: 1.0
    property real posX: 0.5
    property real posY: 0.5
    property real cropL: 0
    property real cropT: 0
    property real cropR: 0
    property real cropB: 0
    property real brightness: 0
    property real contrast: 1
    property real saturation: 1
    property int temperature: 6500
    property real blur: 0
    property real trimStart: 0
    property real trimEnd: 0
    property real speed: 1
    property string loopMode: "none"

    function tr(en, ru) { return hub ? hub.tr(en, ru) : en; }
    function s(v) { return hub ? hub.s(v) : v; }
    function params() {
        return {
            zoom: zoom, posX: posX, posY: posY,
            cropX: cropL, cropY: cropT, cropW: Math.max(0.05, 1 - cropL - cropR), cropH: Math.max(0.05, 1 - cropT - cropB),
            brightness: brightness, contrast: contrast, saturation: saturation, temperature: temperature, blur: blur,
            trimStart: trimStart, trimEnd: trimEnd, speed: speed, loop: loopMode
        };
    }
    function resetAll() {
        zoom = 1; posX = 0.5; posY = 0.5; cropL = 0; cropT = 0; cropR = 0; cropB = 0;
        brightness = 0; contrast = 1; saturation = 1; temperature = 6500; blur = 0;
        trimStart = 0; trimEnd = duration; speed = 1; loopMode = "none";
        previewPath = "";
    }
    function baseName() {
        let n = path.split("/").pop();
        return n.replace(/\.[A-Za-z0-9]+$/, "");
    }
    function stamp() {
        let d = new Date();
        return d.getFullYear() + String(d.getMonth() + 1).padStart(2, "0") + String(d.getDate()).padStart(2, "0") + "-" + String(d.getHours()).padStart(2, "0") + String(d.getMinutes()).padStart(2, "0") + String(d.getSeconds()).padStart(2, "0");
    }
    function render(preview) {
        if (renderProc.running || !info) return;
        let out = preview ? (Caching.getCacheDir("wallpaper_hub") + "/studio_preview_" + stamp())
                          : (hub.editedDir + "/" + baseName() + "_edit_" + stamp());
        renderProc.isPreview = preview;
        renderProc.command = ["python3", hub.script, "edit", "--input", path, "--output", out, "--params", JSON.stringify(params())].concat(preview ? ["--preview"] : []);
        status = preview ? tr("Rendering exact preview…", "Рендер точного превью…") : tr("Rendering the edited copy… (video can take a while)", "Рендер копии… (видео может занять время)");
        renderProc.running = true;
    }

    color: Qt.alpha(ThemeBackend.crust, 0.96)
    radius: ThemeBackend.borderRadius
    focus: true
    Keys.onEscapePressed: (ev) => { if (!renderProc.running) root.hub.studioPath = ""; ev.accepted = true; }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = true }

    Process {
        id: probeProc
        command: ["python3", root.hub.script, "probe", root.path]
        running: root.path !== ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { root.status = "probe failed"; return; }
                if (!d.ok) { root.status = d.error || "unsupported file"; return; }
                root.info = d.info;
                root.trimEnd = d.info.duration || 0;
            }
        }
    }
    Process {
        id: renderProc
        property bool isPreview: true
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text.trim().split("\n").pop()); } catch (e) { root.status = "render failed"; return; }
                if (!d.ok) { root.status = root.tr("Render failed: ", "Ошибка рендера: ") + d.error; return; }
                if (renderProc.isPreview) {
                    root.previewPath = d.path;
                    root.status = root.tr("Exact preview ready (", "Точное превью готово (") + d.info.width + "×" + d.info.height + ")";
                } else {
                    root.savedPath = d.path;
                    root.status = root.tr("Saved: ", "Сохранено: ") + d.path + " (" + d.info.width + "×" + d.info.height + ", " + root.hub.fmtSize(d.info.size) + ")";
                    root.hub.refreshLibrary();
                }
            }
        }
    }

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
    component Knob: ColumnLayout {
        id: knob
        property string label: ""
        property real from: 0
        property real to: 1
        property real value: 0
        property real step: 0.01
        property string suffix: ""
        property int decimals: 2
        signal moved(real v)
        Layout.fillWidth: true
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Txt { Layout.fillWidth: true; text: knob.label; wrapMode: Text.NoWrap; elide: Text.ElideRight }
            Txt { text: Number(knob.value).toFixed(knob.decimals) + knob.suffix; color: ThemeBackend.subtext0; wrapMode: Text.NoWrap }
        }
        C.Slider {
            Layout.fillWidth: true
            from: knob.from
            to: knob.to
            stepSize: knob.step
            value: knob.value
            onMoved: knob.moved(value)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.s(14)
        spacing: root.s(8)

        RowLayout {
            Layout.fillWidth: true
            Txt { text: "Wallpaper Studio"; font.pixelSize: root.s(17); font.bold: true; wrapMode: Text.NoWrap }
            Txt { Layout.fillWidth: true; color: ThemeBackend.subtext0; elide: Text.ElideMiddle; wrapMode: Text.NoWrap; text: root.path + (root.info ? "  ·  " + root.info.width + "×" + root.info.height + " " + (root.info.format || "").toUpperCase() : "") }
            Act { text: root.tr("Close", "Закрыть"); enabled: !renderProc.running; onClicked: root.hub.studioPath = "" }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.s(12)

            // canvas
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.s(6)
                C.TabBar {
                    id: viewTabs
                    Layout.fillWidth: true
                    C.TabButton { text: root.tr("Live (approximate)", "Живой (приблизительно)") }
                    C.TabButton { text: root.tr("Exact preview", "Точное превью"); enabled: root.previewPath !== "" }
                }
                Rectangle {
                    id: canvas
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: ThemeBackend.mantle
                    radius: ThemeBackend.borderRadius
                    clip: true

                    // live view: crop window -> zoom/position -> colour effects
                    Item {
                        id: live
                        anchors.fill: parent
                        visible: viewTabs.currentIndex === 0
                        readonly property real aspect: root.info && root.info.height ? root.info.width / root.info.height : 16 / 9
                        // visible frame keeps the cropped aspect ratio
                        readonly property real cw: Math.max(0.05, 1 - root.cropL - root.cropR)
                        readonly property real ch: Math.max(0.05, 1 - root.cropT - root.cropB)
                        readonly property real frameAspect: aspect * cw / ch
                        Item {
                            id: frame
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height * live.frameAspect)
                            height: width / live.frameAspect
                            clip: true
                            Item {
                                id: srcHolder
                                // full source scaled so the crop window fills the frame, then zoomed
                                width: frame.width / live.cw * root.zoom
                                height: frame.height / live.ch * root.zoom
                                x: -(root.cropL + (live.cw - live.cw / root.zoom) * root.posX) * width
                                y: -(root.cropT + (live.ch - live.ch / root.zoom) * root.posY) * height
                                visible: false
                                Image {
                                    anchors.fill: parent
                                    visible: root.info !== null && root.info.kind === "image"
                                    source: visible ? Caching.fileUrl(root.path) : ""
                                    asynchronous: true
                                    sourceSize.width: 2560
                                    fillMode: Image.Stretch
                                }
                                AnimatedImage {
                                    anchors.fill: parent
                                    visible: root.info !== null && root.info.kind === "animated"
                                    source: visible ? Caching.fileUrl(root.path) : ""
                                    speed: root.speed
                                    playing: visible
                                }
                                Video {
                                    id: liveVideo
                                    anchors.fill: parent
                                    visible: root.isVideo
                                    source: root.isVideo ? Caching.fileUrl(root.path) : ""
                                    fillMode: VideoOutput.Stretch
                                    muted: true
                                    loops: MediaPlayer.Infinite
                                    playbackRate: root.speed
                                    onPositionChanged: {
                                        if (root.trimEnd > 0 && position > root.trimEnd * 1000) seek(root.trimStart * 1000);
                                        else if (position < root.trimStart * 1000 - 200) seek(root.trimStart * 1000);
                                    }
                                }
                            }
                            MultiEffect {
                                source: srcHolder
                                x: srcHolder.x
                                y: srcHolder.y
                                width: srcHolder.width
                                height: srcHolder.height
                                brightness: Math.max(-1, Math.min(1, root.brightness * 0.5))
                                contrast: Math.max(-1, Math.min(1, (root.contrast - 1) * 0.6))
                                saturation: Math.max(-1, Math.min(1, root.saturation - 1))
                                blurEnabled: root.blur > 0
                                blur: Math.min(1, root.blur / 40)
                                blurMax: 64
                                colorization: Math.min(0.35, Math.abs(root.temperature - 6500) / 5500 * 0.25)
                                colorizationColor: root.temperature < 6500 ? "#ff9a3c" : "#6fa8ff"
                            }
                        }
                    }

                    // exact ffmpeg result
                    Item {
                        anchors.fill: parent
                        visible: viewTabs.currentIndex === 1
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            visible: root.previewPath !== "" && root.info && root.info.kind === "image"
                            source: visible ? Caching.fileUrl(root.previewPath) : ""
                            cache: false
                        }
                        AnimatedImage {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            visible: root.previewPath !== "" && root.info && root.info.kind === "animated"
                            source: visible ? Caching.fileUrl(root.previewPath) : ""
                            playing: visible
                        }
                        Video {
                            id: exactVideo
                            anchors.fill: parent
                            visible: root.previewPath !== "" && root.isVideo
                            source: visible ? Caching.fileUrl(root.previewPath) : ""
                            fillMode: VideoOutput.PreserveAspectFit
                            muted: true
                            loops: MediaPlayer.Infinite
                            onSourceChanged: if (source !== "") play()
                        }
                    }
                    Txt {
                        anchors.centerIn: parent
                        visible: root.info === null
                        color: ThemeBackend.subtext0
                        text: root.status !== "" ? root.status : root.tr("Reading file…", "Чтение файла…")
                    }
                }
            }

            // controls
            Flickable {
                Layout.preferredWidth: root.s(320)
                Layout.fillHeight: true
                contentHeight: controls.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                C.ScrollBar.vertical: C.ScrollBar {}
                ColumnLayout {
                    id: controls
                    width: parent.width - root.s(10)
                    spacing: root.s(4)

                    Txt { text: root.tr("Frame", "Кадр"); font.bold: true }
                    Knob { label: root.tr("Zoom", "Масштаб"); from: 1; to: 4; value: root.zoom; suffix: "×"; onMoved: (v) => root.zoom = v }
                    Knob { label: root.tr("Position X", "Положение X"); value: root.posX; onMoved: (v) => root.posX = v }
                    Knob { label: root.tr("Position Y", "Положение Y"); value: root.posY; onMoved: (v) => root.posY = v }
                    Knob { label: root.tr("Crop left", "Обрезка слева"); to: 0.45; value: root.cropL; onMoved: (v) => root.cropL = v }
                    Knob { label: root.tr("Crop right", "Обрезка справа"); to: 0.45; value: root.cropR; onMoved: (v) => root.cropR = v }
                    Knob { label: root.tr("Crop top", "Обрезка сверху"); to: 0.45; value: root.cropT; onMoved: (v) => root.cropT = v }
                    Knob { label: root.tr("Crop bottom", "Обрезка снизу"); to: 0.45; value: root.cropB; onMoved: (v) => root.cropB = v }
                    Txt { Layout.fillWidth: true; visible: root.zoom > 1; color: ThemeBackend.peach; font.pixelSize: root.s(11); text: root.tr("Zoom enlarges pixels: the saved copy is an upscale of the cropped area, not new detail.", "Масштаб увеличивает пиксели: сохранённая копия — увеличение обрезанной области, а не новые детали.") }

                    Txt { text: root.tr("Colour", "Цвет"); font.bold: true; Layout.topMargin: root.s(6) }
                    Knob { label: root.tr("Brightness", "Яркость"); from: -1; to: 1; value: root.brightness; onMoved: (v) => root.brightness = v }
                    Knob { label: root.tr("Contrast", "Контрастность"); from: 0.2; to: 3; value: root.contrast; onMoved: (v) => root.contrast = v }
                    Knob { label: root.tr("Saturation", "Насыщенность"); from: 0; to: 3; value: root.saturation; onMoved: (v) => root.saturation = v }
                    Knob { label: root.tr("Colour temperature", "Температура цвета"); from: 2000; to: 12000; step: 100; decimals: 0; suffix: " K"; value: root.temperature; onMoved: (v) => root.temperature = Math.round(v) }
                    Knob { visible: !root.motion; label: root.tr("Blur", "Размытие"); from: 0; to: 40; step: 0.5; decimals: 1; value: root.blur; onMoved: (v) => root.blur = v }

                    Txt { visible: root.motion; text: root.tr("Motion", "Движение"); font.bold: true; Layout.topMargin: root.s(6) }
                    Knob { visible: root.motion && root.duration > 0; label: root.tr("Start", "Начало"); to: Math.max(0.1, root.duration); step: 0.1; decimals: 1; suffix: " s"; value: root.trimStart; onMoved: (v) => { root.trimStart = Math.min(v, root.trimEnd - 0.2); } }
                    Knob { visible: root.motion && root.duration > 0; label: root.tr("End", "Конец"); to: Math.max(0.1, root.duration); step: 0.1; decimals: 1; suffix: " s"; value: root.trimEnd; onMoved: (v) => { root.trimEnd = Math.max(v, root.trimStart + 0.2); } }
                    Knob { visible: root.motion; label: root.tr("Playback speed", "Скорость"); from: 0.25; to: 4; step: 0.05; suffix: "×"; value: root.speed; onMoved: (v) => root.speed = v }
                    RowLayout {
                        visible: root.motion
                        Layout.fillWidth: true
                        Txt { text: root.tr("Loop", "Зацикливание"); wrapMode: Text.NoWrap }
                        C.ComboBox {
                            Layout.fillWidth: true
                            model: [root.tr("Normal loop", "Обычный цикл"), root.tr("Ping-pong (forward + reverse, ≤30 s)", "Пинг-понг (вперёд + назад, ≤30 с)")]
                            currentIndex: root.loopMode === "pingpong" ? 1 : 0
                            onActivated: (i) => root.loopMode = i === 1 ? "pingpong" : "none"
                        }
                    }
                    Txt { Layout.fillWidth: true; visible: root.motion; color: ThemeBackend.subtext0; font.pixelSize: root.s(11); text: root.tr("Video wallpapers always loop in the engine; the saved copy has no audio track.", "Видеообои всегда зацикливаются движком; у сохранённой копии нет звуковой дорожки.") }

                    Txt { Layout.fillWidth: true; Layout.topMargin: root.s(6); color: ThemeBackend.subtext1; text: root.status; visible: root.status !== "" && root.info !== null }
                    C.BusyIndicator { visible: renderProc.running; running: visible; Layout.alignment: Qt.AlignHCenter }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        Act { Layout.fillWidth: true; text: root.tr("Reset", "Сбросить"); enabled: !renderProc.running; onClicked: root.resetAll() }
                        Act { Layout.fillWidth: true; text: root.tr("Exact preview", "Точное превью"); enabled: !renderProc.running && root.info !== null; onClicked: { root.render(true); viewTabs.currentIndex = 1; } }
                        Act { Layout.fillWidth: true; text: root.tr("Save copy", "Сохранить копию"); enabled: !renderProc.running && root.info !== null; onClicked: root.render(false) }
                        Act {
                            Layout.fillWidth: true
                            text: root.tr("Apply saved copy", "Применить копию")
                            enabled: root.savedPath !== "" && !renderProc.running
                            palette.button: ThemeBackend.mauve
                            palette.buttonText: ThemeBackend.crust
                            onClicked: root.hub.applyPath(root.savedPath)
                        }
                    }
                    Txt { Layout.fillWidth: true; color: ThemeBackend.subtext0; font.pixelSize: root.s(11); text: root.tr("The original file stays untouched; edits are saved as a new file in ", "Оригинал не изменяется; правки сохраняются новым файлом в ") + (root.hub ? root.hub.editedDir : "") }
                }
            }
        }
    }

    onInfoChanged: if (isVideo) liveVideo.play()
}
