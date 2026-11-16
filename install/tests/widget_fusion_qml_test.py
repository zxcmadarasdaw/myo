"""Qt layout and camera checks with a stub editor; no Wayland surfaces."""
import os
from pathlib import Path
import shutil
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
if os.name == "nt":
    os.environ.setdefault("QT_QPA_FONTDIR", str(Path(os.environ["WINDIR"]) / "Fonts"))

from PySide6.QtCore import QObject, QUrl, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView

SOURCE = Path(__file__).resolve().parents[2] / "src/quickshell/widgets/canvas"

app = QGuiApplication([])
messages = []
qInstallMessageHandler(lambda kind, context, message: messages.append(message))

with tempfile.TemporaryDirectory(prefix="serp-fusion-qml-") as folder:
    root = Path(folder)
    canvas = root / "widgets/canvas"
    canvas.mkdir(parents=True)
    for name in ("CanvasMath.js", "WidgetFusion.js", "FusionFrames.qml", "FusionOptions.qml"):
        shutil.copyfile(SOURCE / name, canvas / name)
    (root / "qmldir").write_text("singleton ThemeBackend 1.0 ThemeBackend.qml\n", encoding="utf-8")
    (root / "ThemeBackend.qml").write_text('''pragma Singleton
        import QtQuick
        QtObject {
            property color base: "#222233"
            property color surface0: "#333344"
            property color mauve: "#fab0ff"
            property color text: "#f8f8f8"
            property color subtext0: "#dddddd"
            property string fontFamily: "sans-serif"
        }''', encoding="utf-8")
    (root / "Harness.qml").write_text('''import QtQuick
        import "widgets/canvas"
        Item {
            id: harness
            width: 650; height: 500
            property real cameraX: 0
            property real cameraZoom: 1
            readonly property var style: ({"mode":"horizontal", "style":"custom", "background":"#123456", "dividers":true, "opacity":1})
            FusionFrames {
                anchors.fill: parent
                camera: QtObject { property real viewX: harness.cameraX; property real viewY: 0; property real viewZoom: harness.cameraZoom }
                records: [
                    {wId:"one", wGroup:"g", wFusion:style, wX:110, wY:60, wWidth:100, wHeight:90, wFusionIndex:0},
                    {wId:"two", wGroup:"g", wFusion:style, wX:225, wY:60, wWidth:120, wHeight:90, wFusionIndex:1}
                ]
            }
            FusionOptions {
                objectName: "controls"; x: 365; width: 260; expanded: true
                editor: QtObject {
                    property bool editFusionMember: false
                    property var selectionIdList: ["one", "two"]
                    property var selectedFusion: ({"options": {"mode":"horizontal", "style":"custom", "gap":15,
                       "padding":14, "columns":2, "opacity":1, "radius":6, "background":"#123456",
                       "title":"Dashboard", "dividers":true, "animation":"fade"}, "box":{"w":235, "h":90}})
                }
            }
        }''', encoding="utf-8")
    view = QQuickView()
    view.setSource(QUrl.fromLocalFile(str(root / "Harness.qml")))
    assert view.status() == QQuickView.Ready, view.errors()
    view.show()
    app.processEvents()
    image = view.grabWindow()
    assert image.pixelColor(122, 100).name() == "#123456", messages
    assert any(image.pixelColor(x, 100) != image.pixelColor(222, 100) for x in range(216, 220)), "divider renders in the gap"
    controls = view.rootObject().findChild(QObject, "controls")
    assert 0 < controls.property("implicitHeight") < 350, "Fusion controls fit a bounded scroll area"
    view.rootObject().setProperty("cameraX", 85.0)
    view.rootObject().setProperty("cameraZoom", 0.75)
    app.processEvents()
    moved = view.grabWindow()
    assert moved.pixelColor(26, 75).name() == "#123456", messages
    assert moved.pixelColor(217, 100) != image.pixelColor(217, 100), "frame moves and scales with the camera"
    assert not messages, messages
    view.setSource(QUrl())

print("PASS: Fusion frame, divider, camera transform and editor controls render in Qt")
