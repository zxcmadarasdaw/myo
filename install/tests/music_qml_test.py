"""Real Qt rendering/bindings with stubbed Quickshell transport, NOT a Wayland test."""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
if os.name == "nt":
    os.environ.setdefault("QT_QPA_FONTDIR", str(Path(os.environ["WINDIR"])/"Fonts"))
from PySide6.QtCore import QObject, QUrl, QMetaObject, Q_ARG, Q_RETURN_ARG, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication, QFont, QImage, QColor
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickView

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT/"src/quickshell"
OUT = ROOT/"reports/music-studio"
app = QGuiApplication([])
app.setFont(QFont("Segoe UI", 10))
messages = []
qInstallMessageHandler(lambda kind, context, message: messages.append(message))
checks = 0


def check(value, label):
    global checks
    checks += 1
    print(("PASS: " if value else "FAIL: ") + label)
    if not value:
        raise AssertionError(label + "\n" + "\n".join(messages))


def spin():
    for _ in range(20):
        app.processEvents()
        time.sleep(0.005)


with tempfile.TemporaryDirectory(prefix="serpantinum-music-") as directory:
    root = Path(directory)

    def write(path, text):
        p = root/path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def singleton(name, body, directory=".", imports=""):
        write(f"{directory}/{name}.qml", f"pragma Singleton\nimport QtQuick\n{imports}\nQtObject {{ {body} }}")
        with (root/directory/"qmldir").open("a") as f:
            f.write(f"singleton {name} 1.0 {name}.qml\n")

    shutil.copytree(SRC/"widgets/faces/music", root/"widgets/faces/music")
    for name in ("AudioStudioView.qml", "StudioSlider.qml", "StudioButton.qml", "StudioComboBox.qml"):
        write(f"media/{name}", (SRC/"media"/name).read_text(encoding="utf-8"))
    write("media/qmldir", "AudioStudioView 1.0 AudioStudioView.qml\nStudioSlider 1.0 StudioSlider.qml\nStudioButton 1.0 StudioButton.qml\nStudioComboBox 1.0 StudioComboBox.qml\n")
    write("singletons/audio/MprisController.qml", (SRC/"singletons/audio/MprisController.qml").read_text(encoding="utf-8"))
    write("qmldir", "singleton MprisController 1.0 singletons/audio/MprisController.qml\n")
    singleton("ThemeBackend", '''property color base: "#11131e"; property color text: "#e9e7f4";
        property color subtext0: "#a6abc5"; property color surface0: "#242839"; property color surface1: "#33384e";
        property color surface2: "#535775"; property color mauve: "#c5a2ff"; property color sky: "#7ee6ed";
        property color blue: "#89b4fa"; property color red: "#f38ba8"; property color peach: "#ffbf89"; property real elementOpacity: 0.94; property real borderRadius: 18;
        property string fontFamily: "Segoe UI"''')
    singleton("GpuCompatibility", 'property var effective: ({profile:"Balanced"}); property bool shadersAllowed: true; property bool blurAllowed: true')
    singleton("Config", 'property bool dataReady: true; function getSetting(k,f) { return f; } function setSetting(k,v) {}')
    singleton("Scaler", "function s(x) { return x; }")
    singleton("Sounds", "function playSfx(path, volume) {}")
    singleton("Caching", 'property string qsDir: "/fixture"')
    singleton("Spectrum", 'property var barLevels: []; property int consumers: 0; function registerConsumer() { consumers++; } function unregisterConsumer() { consumers--; }')
    singleton("Audio", '''property QtObject defaultSink: QtObject {
            property QtObject audio: QtObject { property real volume: 0.5; property bool muted: false }
        }
        function getNodeName(n) { return "Test output Р’В· PipeWire stub"; }
        function setVolume(n,v) { if(n) n.audio.volume=v/100; }
        function toggleMute(n) { if(n) n.audio.muted=!n.audio.muted; }''')
    singleton("MusicEffects", '''property var eqState: ({b1:0,b2:0,b3:0,b4:0,b5:0,b6:0,b7:0,b8:0,b9:0,b10:0,
        preset:"Flat",balance:0,dyneq:false,effects:true}); property var presets: ["Flat","Bass Boost","Rock"];
        property bool available: true; property bool busy: false; property string error: ""; property string notice: "";
        property var calls: []; function command(args) { calls=calls.concat([args]); }''')
    write("reusables/qmldir", "GlassFill 1.0 GlassFill.qml\nWallpaperBlur 1.0 WallpaperBlur.qml\nVisualizer 1.0 Visualizer.qml\n")
    write("reusables/GlassFill.qml", "import QtQuick\nItem { property real radius; property bool allowed; property color tintColor }")
    write("reusables/WallpaperBlur.qml", "import QtQuick\nItem { property real radius }")
    write("reusables/Visualizer.qml", "import QtQuick\nItem { property bool active; property bool previewDemo; property color color; property int count; property bool mirrored }")
    write("Quickshell/qmldir", "module Quickshell\nSingleton 1.0 Singleton.qml\n")
    write("Quickshell/Singleton.qml", "import QtQuick\nItem {}")
    write("Quickshell/Io/qmldir", "module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n")
    write("Quickshell/Io/Process.qml", '''import QtQuick
        QtObject { property var command: []; property bool running: false;
        property QtObject stdout; property QtObject stderr; signal exited(int code); }''')
    write("Quickshell/Io/StdioCollector.qml", 'import QtQuick\nQtObject { property string text: ""; signal streamFinished(); }')
    write("Quickshell/Services/Mpris/qmldir", "module Quickshell.Services.Mpris\nMprisPlayer 1.0 MprisPlayer.qml\n")
    write("Quickshell/Services/Mpris/MprisPlayer.qml", '''import QtQuick
        QtObject { property string dbusName: ""; property string identity: "";
        property string trackTitle: ""; property string trackArtist: ""; property string trackArtUrl: "";
        property var metadata: ({}); property int playbackState: 1; property bool isPlaying: false;
        property real position: 42; property real length: 240;
        property bool canControl: true; property bool canPlay: true; property bool canPause: true;
        property bool canGoPrevious: true; property bool canGoNext: true; property bool canSeek: true;
        property bool lengthSupported: true; property bool positionSupported: true;
        property string lastAction: ""; signal postTrackChanged();
        function play() { lastAction="play"; isPlaying=true; } function pause() { lastAction="pause"; isPlaying=false; }
        function next() { lastAction="next"; } function previous() { lastAction="previous"; } }''')
    singleton("Mpris", "property QtObject players: QtObject { property list<MprisPlayer> values: [] }", "Quickshell/Services/Mpris")
    singleton("MprisPlaybackState", "enum State { Stopped, Paused, Playing }", "Quickshell/Services/Mpris")
    write("Harness.qml", '''import QtQuick
        import Quickshell.Services.Mpris
        import "."
        Item {
            width: 570; height: 620
            MprisPlayer { id: first; dbusName: "org.mpris.MediaPlayer2.first"; identity: "Player One"; trackTitle: "Midnight Current"; trackArtist: "Serpantinum"; isPlaying: true }
            MprisPlayer { id: second; dbusName: "org.mpris.MediaPlayer2.second"; identity: "Player Two"; trackTitle: "Second Track" }
            Component.onCompleted: Mpris.players.values = [first,second]
            property alias surface: loader.item
            Loader { id: loader; objectName: "loader"; anchors.fill: parent }
            function load(url: string) { loader.source=url; }
            function state(): string { return JSON.stringify({player:MprisController.activePlayerId, position:MprisController.livePosition, action:MprisController.activePlayer ? MprisController.activePlayer.lastAction : "", calls:MusicEffects.calls, consumers:Spectrum.consumers}); }
            function selectSecond() { MprisController.selectedBus=second.dbusName; }
            function removeSecond() { Mpris.players.values=[first]; }
            function selectAuto() { Mpris.players.values=[first,second]; MprisController.selectedBus=""; first.isPlaying=false; second.isPlaying=true; }
            function noPlayers() { Mpris.players.values=[]; }
            function unavailable() { MusicEffects.available=false; MusicEffects.error="Р СњР ВµРЎвЂљ Р В°РЎС“Р Т‘Р С‘Р С•Р Т‘Р Р†Р С‘Р В¶Р С”Р В° РІР‚вЂќ РЎС“РЎРѓРЎвЂљР В°Р Р…Р С•Р Р†Р С‘РЎвЂљР Вµ serpantinum-audio"; Audio.defaultSink=null; }
            function changeTrack(url: string) { first.trackTitle="Updated metadata"; first.trackArtUrl=url; MprisController.artUrl=url; }
            function restricted() { first.canGoNext=false; first.canSeek=false; first.lengthSupported=false; }
            function restore() { Mpris.players.values=[first]; first.canGoNext=true; first.canSeek=true; first.lengthSupported=true; }
        }''')

    view = QQuickView()
    view.engine().addImportPath(str(root))
    view.setSource(QUrl.fromLocalFile(str(root/"Harness.qml")))
    check(view.status() == QQuickView.Ready, "QML test harness loads: " + str(view.errors()))
    view.show()
    harness = view.rootObject()

    def invoke(name):
        QMetaObject.invokeMethod(harness, name)
        spin()

    def state():
        return json.loads(QMetaObject.invokeMethod(harness, "state", Q_RETURN_ARG(str)))

    def find_item(item, name):
        if item.objectName() == name:
            return item
        for child in item.childItems():
            found = find_item(child, name)
            if found is not None:
                return found
        return None

    def load(path):
        QMetaObject.invokeMethod(harness, "load", Q_ARG(str, path))
        spin()
        return harness.findChild(QObject, "loader").property("item")

    check(state()["player"].endswith("first"), "auto selects playing MPRIS application by dbusName")
    invoke("selectSecond")
    check(state()["player"].endswith("second"), "manual selection overrides another playing application")
    invoke("removeSecond")
    check(state()["player"].endswith("first"), "disconnected selected player falls back automatically")
    invoke("selectAuto")
    check(state()["player"].endswith("second"), "Auto follows changed playback state")
    invoke("restore")
    OUT.mkdir(parents=True, exist_ok=True)
    for variant in ("CompactGlass", "Minimal", "AlbumCover", "Vinyl", "NeonMusic", "FloatingPlayer"):
        view.setWidth(420)
        view.setHeight(150)
        harness.setWidth(420)
        harness.setHeight(150)
        face = load(f"widgets/faces/music/MusicFace{variant}.qml")
        check(face is not None, variant + " loads actual QML")
        check(face.findChild(QObject,"nextTrack").property("enabled"), variant + " enables supported next action")
        spin()
        view.grabWindow().save(str(OUT/f"{variant}.png"))
    view.setWidth(340); view.setHeight(140); harness.setWidth(340); harness.setHeight(140); spin()
    check(view.grabWindow().save(str(OUT/"compact-minimum.png")), "minimum compact layout renders")
    for name, action in [("nextTrack","next"),("previousTrack","previous"),("playPause","play"),("playPause","pause")]:
        QMetaObject.invokeMethod(face.findChild(QObject,name), "clicked")
        spin()
        check(state()["action"] == action, "transport reaches MPRIS " + action)
    artwork = QImage(32,32,QImage.Format_RGB32)
    artwork.fill(QColor("#7e55a9"))
    artwork.save(str(root/"art.png"))
    QMetaObject.invokeMethod(harness,"changeTrack",Q_ARG(str,QUrl.fromLocalFile(str(root/"art.png")).toString()))
    spin()
    check(face.findChild(QObject,"trackTitle").property("text") == "Updated metadata", "changed title updates the compact widget")
    check(face.findChild(QObject,"albumArt").property("source").toString().endswith("art.png"), "changed artwork updates the compact widget")
    invoke("restricted")
    check(not face.findChild(QObject,"nextTrack").property("enabled"), "unsupported next is disabled")
    check(not face.findChild(QObject,"trackSeek").property("enabled"), "unsupported seeking is disabled")
    invoke("noPlayers")
    check(not face.findChild(QObject,"playPause").property("enabled"), "no player disables transport")
    check(state()["position"] == 0, "disconnected player clears the old playhead")
    invoke("restore")
    view.setWidth(570); view.setHeight(620)
    harness.setWidth(570); harness.setHeight(620)
    studio = load("media/AudioStudioView.qml")
    check(studio is not None, "Audio Studio loads actual QML")
    band = find_item(studio,"eqBand1")
    check(band is not None and band.property("enabled"), "available engine enables EQ")
    band.setProperty("value", 6)
    QMetaObject.invokeMethod(band,"moved")
    spin()
    check(state()["calls"][-1] == ["set_band",1,6], "EQ slider sends real band command")
    tone = find_item(studio,"tone_mid")
    tone.setProperty("value",3)
    QMetaObject.invokeMethod(tone,"moved")
    check(state()["calls"][-1] == ["set_tone","mid",3], "Mid sends a real grouped-band command")
    studio.setProperty("showVisualizer",True); spin()
    check(state()["consumers"] == 1, "optional spectrum subscribes to existing Spectrum")
    studio.setProperty("showVisualizer",False); spin()
    check(state()["consumers"] == 0, "hidden spectrum releases its consumer")
    for material in ("liquid","mica","neon","minimal"):
        studio.setProperty("material",material); spin()
        check(view.grabWindow().save(str(OUT/f"studio-{material}.png")), material + " render saved")
    invoke("unavailable")
    check(not band.property("enabled"), "missing engine disables EQ")
    check(not find_item(studio,"masterVolume").property("enabled"), "disconnected device disables volume")
    check("serpantinum-audio" in find_item(studio,"audioStatus").property("text"), "missing engine displays the required component")
    view.setWidth(320); view.setHeight(240); harness.setWidth(320); harness.setHeight(240); spin()
    view.grabWindow().save(str(OUT/"studio-small-unavailable.png"))
    check(not messages, "no QML warnings/errors: " + "\n".join(messages))
    view.setSource(QUrl())
    del view
    spin()
    # Fresh engine loads the real shared effects controller and legacy state bridge.
    registry = (root/"qmldir").read_text().replace("singleton MusicEffects 1.0 MusicEffects.qml", "singleton MusicEffects 1.0 singletons/audio/MusicEffects.qml")
    write("qmldir", registry)
    write("singletons/audio/MusicEffects.qml", (SRC/"singletons/audio/MusicEffects.qml").read_text(encoding="utf-8"))
    for name in ("MusicPlayerState", "MusicEqualizerState"):
        write(f"media/{name}.qml", (SRC/f"media/{name}.qml").read_text(encoding="utf-8"))
        with (root/"media/qmldir").open("a") as f:
            f.write(f"{name} 1.0 {name}.qml\n")
    write("EffectsHarness.qml", '''import QtQuick
        import "."
        import "media"
        Item {
            MusicEqualizerState { id: bridge; visible: false }
            function test(): string {
                let result = {};
                result.initiallyUnavailable = !MusicEffects.available;
                MusicEffects.command(["set_band",1,9]);
                result.unavailableDoesNotQueue = MusicEffects.queue.length === 0;
                MusicEffects.available = true;
                MusicEffects.command(["set_band",1,2]);
                MusicEffects.command(["set_band",1,3]);
                MusicEffects.command(["set_band",2,4]);
                result.dragCoalesced = MusicEffects.queue.length === 2 && MusicEffects.queue[0][2] === "3";
                result.notOptimistic = MusicEffects.eqState.b1 === 0;
                MusicEffects.current = ["set_band",1,3];
                MusicEffects.finish(1, JSON.stringify({ok:false,available:false,error:"engine rejected"}), "");
                result.failurePreservesState = MusicEffects.eqState.b1 === 0 && MusicEffects.queue.length === 0 && !MusicEffects.available;
                let next = Object.assign({}, MusicEffects.eqState, {b1:3});
                MusicEffects.finish(0, JSON.stringify({ok:true,available:true,state:next,presets:["Flat"]}), "");
                result.acknowledgedState = MusicEffects.eqState.b1 === 3 && bridge.eqData.b1 === 3;
                bridge.visible = true;
                result.subscribed = MusicEffects.consumers === 1;
                bridge.visible = false;
                result.unsubscribed = MusicEffects.consumers === 0;
                MusicEffects.finish(0, "invalid json", "helper failed");
                result.invalidResponseFailsClosed = !MusicEffects.available && MusicEffects.error.indexOf("helper failed") >= 0;
                return JSON.stringify(result);
            }
        }''')
    engine = QQmlEngine()
    engine.addImportPath(str(root))
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(root/"EffectsHarness.qml")))
    obj = component.create()
    check(obj is not None, "real effects controller and legacy state bridge load: " + str(component.errors()))
    result = json.loads(QMetaObject.invokeMethod(obj, "test", Q_RETURN_ARG(str)))
    for label, passed in result.items():
        check(passed, label)
    check(not messages, "shared effects controller has no QML errors: " + "\n".join(messages))
    del obj, component, engine

print(f"PASS: {checks} Qt checks (transport/material shaders stubbed; no Fedora/Wayland)")


