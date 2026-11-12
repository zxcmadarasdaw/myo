"""Qt test for wallpaper URL handling and the animated GIF layer.

Checks with real Qt (offscreen, software renderer):
  * Caching.fileUrl turns paths containing spaces, '#', '%', '?' and
    non-ASCII characters into URLs that Image/AnimatedImage actually load;
  * Caching.serpantinumDir falls back to the install tree when the
    SERPANTINUM_DIR variable is missing (no dependency on the working dir);
  * WallpaperGif animates a multi-frame GIF and reports a damaged GIF
    through its `failed` signal instead of failing silently.

Quickshell is stubbed; this is not a Wayland/Hyprland test.
    .tools/qtvenv/Scripts/python install/tests/wallpaper_qml_test.py
"""
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
if os.name == "nt":
    os.environ.setdefault("QT_QPA_FONTDIR", str(Path(os.environ["WINDIR"]) / "Fonts"))
from PySide6.QtCore import QUrl, qInstallMessageHandler
from PySide6.QtGui import QColor, QGuiApplication, QImage
from PySide6.QtQml import QQmlComponent, QQmlEngine

ROOT = Path(__file__).resolve().parents[2]
app = QGuiApplication([])
messages = []
qInstallMessageHandler(lambda kind, context, message: messages.append(message))
failures = []


def check(condition, label):
    print(("PASS: " if condition else "FAIL: ") + label)
    if not condition:
        failures.append(label)


def wait_for(predicate, timeout=5.0):
    end = time.time() + timeout
    while time.time() < end:
        app.processEvents()
        if predicate():
            return True
        time.sleep(0.01)
    return predicate()


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_gif(path, frames=3):
    # Qt can write GIF only with extra plugins; build a minimal animated GIF.
    width = height = 4
    data = bytearray(b"GIF89a" + width.to_bytes(2, "little") + height.to_bytes(2, "little") + b"\xf1\x00\x00")
    data += b"\x00\x00\x00\xff\xff\xff\xff\x00\x00\x00\xff\x00"  # 4-colour palette
    data += b"\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00"
    for index in range(frames):
        data += b"\x21\xf9\x04\x04\x0a\x00\x00\x00"  # 100 ms delay
        data += b"\x2c\x00\x00\x00\x00" + width.to_bytes(2, "little") + height.to_bytes(2, "little") + b"\x00"
        # LZW, min code size 2: clear, 16 pixels of colour (index % 4), end.
        colour = index % 4
        codes = [4] + [colour] * 16 + [5]
        bits, nbits, size, out = 0, 0, 3, bytearray()
        for n, code in enumerate(codes):
            bits |= code << nbits
            nbits += size
            while nbits >= 8:
                out.append(bits & 0xFF)
                bits >>= 8
                nbits -= 8
            # Codes 6.. are added to the table after every pixel; widen at 8.
            if n >= 1 and 4 + 2 + n == (1 << size) and size < 12:
                size += 1
        if nbits:
            out.append(bits & 0xFF)
        data += bytes([2, len(out)]) + out + b"\x00"
    data += b"\x3b"
    path.write_bytes(bytes(data))


with tempfile.TemporaryDirectory(prefix="wallpaper-qml-", ignore_cleanup_errors=True) as directory:
    root = Path(directory)
    shell = root / "src/quickshell"
    (shell / "singletons/system").mkdir(parents=True)
    (shell / "wallpaper").mkdir(parents=True)
    shutil.copyfile(ROOT / "src/quickshell/singletons/system/Caching.qml", shell / "singletons/system/Caching.qml")
    shutil.copyfile(ROOT / "src/quickshell/wallpaper/WallpaperGif.qml", shell / "wallpaper/WallpaperGif.qml")
    write(shell / "qmldir", "singleton Caching 1.0 singletons/system/Caching.qml\n")

    stubs = root / "stubs"
    write(stubs / "Quickshell/qmldir", "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n")
    write(stubs / "Quickshell/Quickshell.qml",
          "pragma Singleton\nimport QtQuick\nQtObject {\n"
          "  function env(name) { return name === 'HOME' ? '/home/test' : ''; }\n"
          "  function execDetached(args) {}\n}\n")

    # '?' is legal in Linux file names but not on Windows test machines.
    media = root / ("Wallpapers #1 100% ок" if os.name == "nt" else "Wallpapers #1 100% ?ок")
    media.mkdir()
    png = media / "pic #2 50%.png"
    image = QImage(8, 8, QImage.Format_RGB32)
    image.fill(QColor("#336699"))
    check(image.save(str(png)), "test PNG written")
    gif = media / "anim #3.gif"
    make_gif(gif)
    broken = media / "broken.gif"
    broken.write_bytes(b"GIF89a\x04\x00\x04\x00garbage")

    engine = QQmlEngine()
    engine.addImportPath(str(stubs))

    def posix(path):
        text = str(path).replace("\\", "/")
        return text if text.startswith("/") else "/" + text

    probe = QQmlComponent(engine)
    probe.setData(b"""
import QtQuick
import "src/quickshell"
Item {
    property string dir: Caching.serpantinumDir
    function url(p) { return Caching.fileUrl(p); }
}
""", QUrl.fromLocalFile(str(root / "probe.qml")))
    item = probe.create()
    check(item is not None, "Caching singleton loads: " + "; ".join(e.toString() for e in probe.errors()))
    if item is not None:
        expected = posix(root / "src")
        check(item.property("dir").rstrip("/").endswith(expected.rstrip("/").split(":", 1)[-1]),
              "serpantinumDir falls back to install tree without SERPANTINUM_DIR (got %s)" % item.property("dir"))

        def file_url(path):
            result = item.url(posix(path))
            # Windows drive paths: Qt wants file:///E:/..., the shell sees /E:/...
            return result

        url_png = file_url(png)
        check("%23" in url_png and "%25" in url_png and (os.name == "nt" or "%3F" in url_png), "special characters are escaped: " + url_png)
        check(QUrl(url_png).toLocalFile().replace("\\", "/").endswith("pic #2 50%.png"), "URL round-trips to the file name")

        viewer = QQmlComponent(engine)
        viewer.setData(b"""
import QtQuick
Image { asynchronous: false; property int st: status }
""", QUrl.fromLocalFile(str(root / "viewer.qml")))
        img = viewer.create()
        img.setProperty("source", QUrl(url_png))
        check(wait_for(lambda: img.property("st") == 1), "Image loads PNG from a path with # and %")

        gif_host = QQmlComponent(engine)
        gif_host.setData(b"""
import QtQuick
import "src/quickshell/wallpaper"
Item {
    width: 64; height: 64
    property string failure: ""
    property url gifUrl: ""
    property bool gifActive: gifLayer.active
    property int gifStatus: gifLayer.item ? gifLayer.item.status : -1
    property int gifFrames: gifLayer.item ? gifLayer.item.frameCount : 0
    property bool gifPlaying: gifLayer.item ? gifLayer.item.playing : false
    WallpaperGif {
        id: gifLayer
        anchors.fill: parent
        imageUrl: parent.gifUrl
        playing: true
        onFailed: reason => parent.failure = reason
    }
}
""", QUrl.fromLocalFile(str(root / "gifhost.qml")))
        host = gif_host.create()
        check(host is not None, "WallpaperGif instantiates: " + "; ".join(e.toString() for e in gif_host.errors()))
        if host is not None:
            host.setProperty("gifUrl", QUrl(file_url(gif)))
            check(wait_for(lambda: host.property("gifStatus") == 1),
                  "AnimatedImage loads GIF from a path with #")
            check(host.property("gifFrames") >= 2, "GIF has several frames (%s)" % host.property("gifFrames"))
            check(host.property("gifPlaying") is True, "GIF is playing")
            host.setProperty("gifUrl", QUrl(file_url(png)))
            check(wait_for(lambda: host.property("gifActive") is False), "GIF layer inactive for non-GIF files")
            host.setProperty("gifUrl", QUrl(file_url(broken)))
            check(wait_for(lambda: host.property("failure") != ""), "damaged GIF reports failure: " + str(host.property("failure")) + " status=%s frames=%s" % (host.property("gifStatus"), host.property("gifFrames")))

if failures:
    print("\n".join(messages[-10:]))
    sys.exit(1)
print("PASS: wallpaper URL handling and GIF layer")
