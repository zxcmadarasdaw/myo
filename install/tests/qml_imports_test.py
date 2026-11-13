"""Regression test for "WallpaperGif is not a type" under Quickshell.

    python3 install/tests/qml_imports_test.py

1. install/modules/qml_check.py passes on src/quickshell and catches the two
   known failure shapes on small fixtures:
     * a sibling type used by a file that is reached only through another
       directory's qmldir (WallpaperEngine -> WallpaperGif);
     * `import "dir"` of a directory without qmldir that Quickshell never
       scans (ThemessTab -> themess/ThemessPreview).
2. With PySide6 (skipped if missing): real Qt loads QML over HTTP, a remote
   scheme like Quickshell's qs:. Declaring `WallpaperGif {}` there fails with
   the same error chain as on Fedora, while the GIF layer exactly as written in
   WallpaperEngine.qml (Loader by URL) loads, animates a GIF and reports a
   damaged one. This is not a Wayland/Hyprland test.
"""
import functools
import http.server
import os
import re
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHELL = ROOT / "src" / "quickshell"
sys.path.insert(0, str(ROOT / "install" / "modules"))
import qml_check  # noqa: E402

failures = []


def check(condition, label):
    print(("PASS: " if condition else "FAIL: ") + label)
    if not condition:
        failures.append(label)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


# 1. Static check -------------------------------------------------------------
problems = qml_check.check(SHELL)
check(not problems, "all local QML types in src/quickshell resolve under Quickshell"
      + "".join("\n    %s:%d: %s" % (p.relative_to(SHELL).as_posix(), n, m) for p, n, m in problems))

with tempfile.TemporaryDirectory(prefix="qml-check-", ignore_cleanup_errors=True) as directory:
    fx = Path(directory)
    write(fx / "Shell.qml", "import QtQuick\nItem { Engine {} }\n")
    write(fx / "qmldir", "Engine 1.0 wallpaper/Engine.qml\nTab 1.0 guide/Tab.qml\n")
    write(fx / "wallpaper/Engine.qml", "import QtQuick\nimport \"../\"\nItem {\n    WallpaperGif {}\n}\n")
    write(fx / "wallpaper/WallpaperGif.qml", "import QtQuick\nItem {}\n")
    write(fx / "guide/Tab.qml", "import QtQuick\nimport \"themess\"\nItem {\n    ThemessPreview {}\n}\n")
    write(fx / "guide/themess/ThemessPreview.qml", "import QtQuick\nItem {}\n")
    found = {(p.name, m.split()[0]) for p, _, m in qml_check.check(fx)}
    check(("Engine.qml", "WallpaperGif") in found, "qml_check flags WallpaperGif reached only via the root qmldir")
    check(("Tab.qml", "ThemessPreview") in found, "qml_check flags a type from an unscanned directory without qmldir")
    write(fx / "guide/themess/qmldir", "ThemessPreview 1.0 ThemessPreview.qml\n")
    write(fx / "wallpaper/qmldir", "WallpaperGif 1.0 WallpaperGif.qml\n")
    check(not qml_check.check(fx), "qml_check accepts the same tree once the directories have a qmldir")

# 2. Real Qt over a remote scheme ---------------------------------------------
try:
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    os.environ.setdefault("QT_QUICK_BACKEND", "software")
    from PySide6.QtCore import QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlComponent, QQmlEngine
except ImportError:
    print("SKIP: Qt remote-loading test (PySide6 not installed: pip install --user PySide6)")
else:
    app = QGuiApplication([])

    def wait_for(predicate, timeout=8.0):
        end = time.time() + timeout
        while time.time() < end:
            app.processEvents()
            if predicate():
                return True
            time.sleep(0.01)
        return predicate()

    def gif_bytes(frames=3):
        # Minimal animated 4x4 GIF (same generator as wallpaper_qml_test.py).
        data = bytearray(b"GIF89a\x04\x00\x04\x00\xf1\x00\x00")
        data += b"\x00\x00\x00\xff\xff\xff\xff\x00\x00\x00\xff\x00"
        data += b"\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00"
        for index in range(frames):
            data += b"\x21\xf9\x04\x04\x0a\x00\x00\x00\x2c\x00\x00\x00\x00\x04\x00\x04\x00\x00"
            codes = [4] + [index % 4] * 16 + [5]
            bits, nbits, size, out = 0, 0, 3, bytearray()
            for n, code in enumerate(codes):
                bits |= code << nbits
                nbits += size
                while nbits >= 8:
                    out.append(bits & 0xFF)
                    bits >>= 8
                    nbits -= 8
                if n >= 1 and 4 + 2 + n == (1 << size) and size < 12:
                    size += 1
            if nbits:
                out.append(bits & 0xFF)
            data += bytes([2, len(out)]) + out + b"\x00"
        return bytes(data + b"\x3b")

    engine_src = (SHELL / "wallpaper/WallpaperEngine.qml").read_text(encoding="utf-8")
    match = re.search(r"\n(\s*)Loader \{\n\s*id: gifLayerA\n.*?\n\1\}\n", engine_src, re.S)
    check(match is not None, "WallpaperEngine.qml contains the gifLayerA Loader")
    layer = match.group(0) if match else ""
    for old, new in (("Caching.fileUrl(barWindow.pathA)", "host.gifUrl"),
                     ("!barWindow.playbackPaused && !GpuCompatibility.effective.fallback && !barWindow.performanceMode", "true"),
                     ("barWindow.reportLoadError(barWindow.pathA, reason)", "host.failure = reason")):
        layer = layer.replace(old, new)
    check(not re.search(r"barWindow|Caching|GpuCompatibility", layer),
          "gifLayerA only depends on the substituted engine properties")

    with tempfile.TemporaryDirectory(prefix="qml-remote-", ignore_cleanup_errors=True) as directory:
        tree = Path(directory)
        write(tree / "qmldir", "Engine 1.0 wallpaper/Engine.qml\nOldEngine 1.0 wallpaper/OldEngine.qml\n")
        write(tree / "Host.qml", "import QtQuick\nItem { width: 64; height: 64; property var engine: Engine { anchors.fill: parent } }\n")
        write(tree / "OldHost.qml", "import QtQuick\nItem { OldEngine {} }\n")
        write(tree / "wallpaper/WallpaperGif.qml", (SHELL / "wallpaper/WallpaperGif.qml").read_text(encoding="utf-8"))
        write(tree / "wallpaper/OldEngine.qml",
              "import QtQuick\nItem {\n    WallpaperGif { imageUrl: \"\"; playing: true }\n}\n")
        write(tree / "wallpaper/Engine.qml",
              "import QtQuick\nItem {\n    id: host\n    property url gifUrl: \"\"\n    property string failure: \"\"\n"
              "    readonly property var gifItem: gifLayerA.item\n" + layer + "}\n")
        (tree / "anim.gif").write_bytes(gif_bytes())
        (tree / "broken.gif").write_bytes(gif_bytes()[:40])

        class Quiet(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(tree)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d/" % server.server_address[1]
        try:
            qml = QQmlEngine()

            def load(name):
                component = QQmlComponent(qml, QUrl(base + name))
                wait_for(lambda: not component.isLoading())
                return component

            old = load("OldHost.qml")
            errors = " ".join(e.toString() for e in old.errors())
            check(old.isError() and "WallpaperGif is not a type" in errors,
                  "remote load reproduces 'WallpaperGif is not a type' for a declared WallpaperGif")

            new = load("Host.qml")
            host = new.create() if new.isReady() else None
            check(host is not None, "remote load of the Loader-based GIF layer succeeds: "
                  + " ".join(e.toString() for e in new.errors()))
            if host is not None:
                engine_obj = host.property("engine")
                check(wait_for(lambda: engine_obj.property("gifItem") is not None),
                      "WallpaperGif.qml is loaded by URL over the remote scheme")
                # QML comes over the remote scheme as under Quickshell; the GIF
                # itself is a file:// URL there too (Caching.fileUrl). An HTTP GIF
                # overflows the stack in AnimatedImage under PySide even with the
                # old declaration, so it would test the harness, not the shell.
                engine_obj.setProperty("gifUrl", QUrl.fromLocalFile(str(tree / "anim.gif")))
                gif = engine_obj.property("gifItem")
                check(wait_for(lambda: gif.property("item") is not None and gif.property("item").property("frameCount") >= 2),
                      "GIF wallpaper animates (several frames) through the remote GIF layer")
                check(gif.property("item") is not None and gif.property("item").property("playing") is True,
                      "GIF is playing")
                engine_obj.setProperty("gifUrl", QUrl.fromLocalFile(str(tree / "broken.gif")))
                check(wait_for(lambda: engine_obj.property("failure") != ""),
                      "damaged GIF is reported through Connections: " + str(engine_obj.property("failure")))
                engine_obj.setProperty("gifUrl", QUrl.fromLocalFile(str(tree / "still.png")))
                check(wait_for(lambda: gif.property("active") is False), "GIF layer is inactive for non-GIF files")
        finally:
            server.shutdown()

if failures:
    print("\n%d check(s) failed" % len(failures))
    sys.exit(1)
print("\nPASS: QML imports resolve under Quickshell rules")
