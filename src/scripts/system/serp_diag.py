#!/usr/bin/env python3
"""Serpantinum diagnostics (Settings -> Diagnostics).

  serp_diag.py summary                 -> JSON with versions, dependencies, crashes, shell errors, module checks
  serp_diag.py export [--keep-home] [--keep-user] [--keep-tokens] [--no-settings] [--include-dumps]
                                       -> writes ~/serpantinum-diagnostics-<time>.tar.gz, prints JSON

Everything stays on this machine: nothing is uploaded. By default the export
replaces the home path, user name and host name, masks token-like strings and
API keys, never reads shell/terminal history and never includes
~/.config/serpantinum/secrets.
"""
import argparse
import datetime
import getpass
import glob
import io
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tarfile

HOME = os.path.expanduser("~")
SERP_DIR = os.environ.get("SERPANTINUM_DIR") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
QS_DIR = os.path.join(SERP_DIR, "quickshell")
STATE = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
SHELL_LOG = os.path.join(STATE, "serpantinum", "logs", "shell.log")
CRASH_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "quickshell", "crashes")
SETTINGS = os.environ.get("QS_SETTINGS") or os.path.join(HOME, ".config", "serpantinum", "settings.json")
ERROR_RE = re.compile(r"(ERROR|error:|WARN|warning|caused by|is not a type|unavailable|Segmentation|crash|Failed to load|failed \d+ times|exited with code)", re.I)


def run(cmd, timeout=6):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()
    except FileNotFoundError:
        return 127, "", "not installed"
    except subprocess.TimeoutExpired:
        return 124, "", "timed out"
    except OSError as e:
        return 126, "", str(e)


def first_line(s):
    return (s or "").splitlines()[0].strip() if s else ""


def qt_version():
    for cmd in (["qtpaths6", "--qt-version"], ["qtpaths-qt6", "--qt-version"], ["qtpaths", "--qt-version"]):
        code, out, _ = run(cmd)
        if code == 0 and out:
            return first_line(out), " ".join(cmd)
    code, out, _ = run(["rpm", "-q", "--qf", "%{VERSION}", "qt6-qtbase"])
    if code == 0 and out and "not installed" not in out:
        return out, "rpm qt6-qtbase"
    code, out, _ = run(["quickshell", "--version"])
    m = re.search(r"Qt\s*([\d.]+)", out or "")
    if m:
        return m.group(1), "quickshell --version"
    return "", ""


def qml_module_dirs():
    dirs = []
    for d in ("/usr/lib64/qt6/qml", "/usr/lib/qt6/qml", "/usr/lib/x86_64-linux-gnu/qt6/qml", "/run/current-system/sw/lib/qt-6/qml"):
        if os.path.isdir(d):
            dirs.append(d)
    for d in (os.environ.get("QML_IMPORT_PATH", "") + ":" + os.environ.get("QML2_IMPORT_PATH", "")).split(":"):
        if d and os.path.isdir(d):
            dirs.append(d)
    return dirs


def check_qml_module(name):
    rel = name.replace(".", "/")
    for d in qml_module_dirs():
        if os.path.isfile(os.path.join(d, rel, "qmldir")):
            return True, os.path.join(d, rel)
    return False, ""


def dependencies():
    cmds = [("quickshell", True, "shell runtime"), ("python3", True, "helper scripts"), ("ffmpeg", True, "video snapshots, Wallpaper Studio"),
            ("ffprobe", True, "file checks, video info"), ("pgrep", True, "process checks"), ("curl", False, "updater, weather"),
            ("hyprctl", False, "Hyprland IPC"), ("matugen", False, "colours from wallpaper"), ("wl-paste", False, "clipboard"),
            ("grim", False, "screenshots")]
    out = []
    for c, req, why in cmds:
        out.append({"name": c, "ok": bool(shutil.which(c)), "required": req, "purpose": why})
    known = bool(qml_module_dirs())
    for mod, req, why in (("QtMultimedia", True, "video wallpapers, previews"), ("QtQuick.Effects", True, "blur, MultiEffect"),
                          ("QtQuick.Controls", True, "settings UI"), ("Quickshell", True, "shell types")):
        ok, where = check_qml_module(mod)
        out.append({"name": "QML " + mod, "ok": ok if known else None, "required": req, "purpose": why, "where": where})
    code, _, _ = run(["rpm", "-q", "qt6-qtimageformats"])
    if code != 127:
        out.append({"name": "qt6-qtimageformats", "ok": code == 0, "required": False, "purpose": "WebP/AVIF wallpapers"})
    return out


def crashes(limit=8):
    items = []
    dirs = [d for d in glob.glob(os.path.join(CRASH_DIR, "*")) if os.path.isdir(d)]
    for d in sorted(dirs, key=os.path.getmtime, reverse=True)[:limit]:
        files, info = [], ""
        for f in sorted(os.listdir(d)):
            fp = os.path.join(d, f)
            try:
                size = os.path.getsize(fp)
            except OSError:
                continue
            files.append({"name": f, "size": size})
            if not info and size < 200000 and (f.endswith((".txt", ".log")) or f == "info"):
                try:
                    with open(fp, "r", encoding="utf-8", errors="replace") as fh:
                        info = fh.read(3000)
                except OSError:
                    pass
        items.append({"dir": d, "time": datetime.datetime.fromtimestamp(os.path.getmtime(d)).isoformat(timespec="seconds"),
                      "files": files, "info": info})
    return items


def tail_file(path, max_bytes):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        f.seek(0, 2)
        size = f.tell()
        f.seek(max(0, size - max_bytes))
        return f.read()


def shell_errors(limit=60):
    if not os.path.isfile(SHELL_LOG):
        return [], False
    try:
        lines = tail_file(SHELL_LOG, 400000).splitlines()
    except OSError:
        return [], True
    return [l for l in lines if ERROR_RE.search(l)][-limit:], True


def module_checks():
    """Static checks that catch 'X is not a type' before Quickshell does."""
    out, missing = [], []
    for qmldir in glob.glob(os.path.join(QS_DIR, "**", "qmldir"), recursive=True):
        base = os.path.dirname(qmldir)
        try:
            with open(qmldir, encoding="utf-8") as f:
                for line in f:
                    parts = line.split()
                    if len(parts) < 2 or parts[0] in ("module", "#", "import", "depends", "plugin", "classname", "typeinfo"):
                        continue
                    target = parts[-1]
                    if target.endswith((".qml", ".js")) and not os.path.isfile(os.path.join(base, target)):
                        missing.append(os.path.relpath(os.path.join(base, target), QS_DIR))
        except OSError:
            pass
    out.append({"name": "qmldir registrations", "ok": not missing,
                "detail": ("missing: " + ", ".join(missing)) if missing else "all registered QML/JS files exist"})
    for rel in ("Shell.qml", "wallpaper/WallpaperEngine.qml", "wallpaper/WallpaperGif.qml", "guide/wallpaper/hub/WallpaperHubTab.qml",
                "guide/wallpaper/hub/HubPreview.qml", "guide/wallpaper/hub/WallpaperStudio.qml"):
        ok = os.path.isfile(os.path.join(QS_DIR, rel))
        out.append({"name": rel, "ok": ok, "detail": "present" if ok else "missing"})
    eng = os.path.join(QS_DIR, "wallpaper", "WallpaperEngine.qml")
    if os.path.isfile(eng):
        with open(eng, encoding="utf-8") as f:
            by_url = 'Qt.resolvedUrl("WallpaperGif.qml")' in f.read()
        out.append({"name": "GIF layer loading", "ok": by_url,
                    "detail": "WallpaperGif is loaded by URL, so a GIF problem cannot stop the shell" if by_url
                    else "WallpaperGif is referenced as a type: may fail with 'WallpaperGif is not a type'"})
    for script in ("scripts/wallpaper/wallhub.py", "scripts/system/serp_diag.py"):
        ok = os.path.isfile(os.path.join(SERP_DIR, script))
        out.append({"name": script, "ok": ok, "detail": "present" if ok else "missing"})
    return out


def wallpaper_engine():
    main = os.path.join(QS_DIR, "Shell.qml")
    if not shutil.which("quickshell"):
        return {"ipc": None, "detail": "quickshell is not installed"}
    code, out, err = run(["quickshell", "ipc", "-p", main, "call", "wallpaper", "getWallpaperPath", ""], timeout=5)
    if code == 0:
        return {"ipc": True, "detail": ("engine answered; current wallpaper: " + out) if out else "engine answered; no wallpaper set"}
    return {"ipc": False, "detail": first_line(err) or "no answer (is the shell running?)"}


def summary():
    code, qs, _ = run(["quickshell", "--version"])
    qtv, qtsrc = qt_version()
    hyp = ""
    c, out, _ = run(["hyprctl", "version", "-j"])
    if c == 0:
        try:
            d = json.loads(out)
            hyp = (d.get("version") or d.get("tag") or "") + (" (" + d.get("commit", "")[:8] + ")" if d.get("commit") else "")
        except ValueError:
            hyp = first_line(out)
    osname = sys.platform
    try:
        with open("/etc/os-release", encoding="utf-8") as f:
            m = re.search(r'^PRETTY_NAME="?([^"\n]+)', f.read(), re.M)
            osname = m.group(1) if m else osname
    except OSError:
        pass
    live = False
    try:
        with open("/proc/cmdline", encoding="utf-8") as f:
            live = "rd.live" in f.read()
    except OSError:
        pass
    errs, log_found = shell_errors()
    version = ""
    for vf in (os.path.join(SERP_DIR, "version.txt"), os.path.join(SERP_DIR, "..", "version.txt")):
        try:
            with open(vf, encoding="utf-8") as f:
                version = f.read().strip()
            # git checkouts without symlink support store the link target as text
            if version and not version.endswith(".txt"):
                break
            version = ""
        except OSError:
            pass
    return {
        "ok": True, "time": datetime.datetime.now().isoformat(timespec="seconds"),
        "serpantinum": version, "serpantinumDir": SERP_DIR,
        "quickshell": first_line(qs) if code == 0 else "not found", "qt": qtv or "unknown", "qtSource": qtsrc,
        "hyprland": hyp or "not running / not found", "os": osname, "liveSession": live,
        "session": {"wayland": os.environ.get("WAYLAND_DISPLAY", ""), "desktop": os.environ.get("XDG_CURRENT_DESKTOP", "")},
        "dependencies": dependencies(), "crashes": crashes(), "crashDir": CRASH_DIR,
        "shellLog": SHELL_LOG, "shellLogFound": log_found, "shellErrors": errs,
        "modules": module_checks(), "wallpaperEngine": wallpaper_engine(),
    }


TOKEN_RES = [
    (re.compile(r"(?i)((?:api[_-]?key|apikey|token|secret|password|passwd|authorization|bearer)[\"']?\s*[:=]\s*[\"']?)([^\s\"',;&]{6,})"), r"\1<redacted>"),
    (re.compile(r"(?i)([?&](?:key|api_key|apikey|token|access_token)=)[^&\s\"']+"), r"\1<redacted>"),
    (re.compile(r"\b[A-Za-z0-9_\-]{32,}\b"), "<redacted-token>"),
]


def redactor(keep_home, keep_user, keep_tokens):
    user = getpass.getuser()
    host = socket.gethostname()

    def fn(text):
        if not keep_home:
            text = text.replace(HOME, "~")
        if not keep_user:
            if user and len(user) > 2:
                text = re.sub(r"\b" + re.escape(user) + r"\b", "<user>", text)
            if host and len(host) > 2:
                text = re.sub(r"\b" + re.escape(host) + r"\b", "<host>", text)
        if not keep_tokens:
            for rx, rep in TOKEN_RES:
                text = rx.sub(rep, text)
        return text
    return fn


def add_text(tar, name, text):
    data = text.encode("utf-8")
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mtime = int(datetime.datetime.now().timestamp())
    info.mode = 0o600
    tar.addfile(info, io.BytesIO(data))


def export(a):
    red = redactor(a.keep_home, a.keep_user, a.keep_tokens)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    out = a.out or os.path.join(HOME, "serpantinum-diagnostics-%s.tar.gz" % stamp)
    s = summary()
    included = []
    with tarfile.open(out, "w:gz") as tar:
        add_text(tar, "summary.json", red(json.dumps(s, ensure_ascii=False, indent=2)))
        included.append("summary.json")
        if os.path.isfile(SHELL_LOG):
            add_text(tar, "shell.log", red(tail_file(SHELL_LOG, 2 * 1024 * 1024)))
            included.append("shell.log (last 2 MB)")
        for c in s["crashes"]:
            base = "crashes/" + os.path.basename(c["dir"]) + "/"
            for f in c["files"]:
                fp = os.path.join(c["dir"], f["name"])
                is_dump = f["name"].endswith((".dmp", ".dump")) or "minidump" in f["name"].lower()
                if (is_dump and not a.include_dumps) or f["size"] > 64 * 1024 * 1024:
                    continue
                try:
                    if is_dump:
                        tar.add(fp, arcname=base + f["name"])
                    else:
                        add_text(tar, base + f["name"], red(tail_file(fp, 4 * 1024 * 1024)))
                except OSError:
                    continue
                included.append(base + f["name"])
        if not a.no_settings and os.path.isfile(SETTINGS):
            try:
                with open(SETTINGS, encoding="utf-8") as f:
                    data = json.load(f)
                for k in ("location", "weather", "profile", "lastLocation", "manualLocation"):
                    if k in data:
                        data[k] = "<removed>"
                add_text(tar, "settings.json", red(json.dumps(data, ensure_ascii=False, indent=2)))
                included.append("settings.json (location/profile removed)")
            except (OSError, ValueError):
                pass
        code, out_j, _ = run(["journalctl", "--user", "-n", "300", "--no-pager", "-o", "short-iso", "_COMM=quickshell"], timeout=8)
        if code == 0 and out_j:
            add_text(tar, "journal-quickshell.txt", red(out_j))
            included.append("journal-quickshell.txt")
        add_text(tar, "README.txt",
                 "Serpantinum diagnostic report created %s.\nRedaction: home path %s, user/host names %s, tokens %s; crash dumps %s.\n"
                 "Shell/terminal history and ~/.config/serpantinum/secrets are never included.\nThis archive was not uploaded anywhere.\n"
                 % (stamp, "kept" if a.keep_home else "replaced", "kept" if a.keep_user else "replaced",
                    "kept" if a.keep_tokens else "masked", "included" if a.include_dumps else "excluded"))
    try:
        os.chmod(out, 0o600)
    except OSError:
        pass
    print(json.dumps({"ok": True, "path": out, "size": os.path.getsize(out), "included": included}, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser(description="Serpantinum diagnostics")
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("summary")
    e = sp.add_parser("export")
    e.add_argument("--keep-home", action="store_true")
    e.add_argument("--keep-user", action="store_true")
    e.add_argument("--keep-tokens", action="store_true")
    e.add_argument("--no-settings", action="store_true")
    e.add_argument("--include-dumps", action="store_true")
    e.add_argument("--out", default="")
    a = ap.parse_args()
    try:
        if a.cmd == "summary":
            print(json.dumps(summary(), ensure_ascii=False))
        else:
            export(a)
    except Exception as ex:
        print(json.dumps({"ok": False, "error": "%s: %s" % (type(ex).__name__, ex)}))


if __name__ == "__main__":
    main()
