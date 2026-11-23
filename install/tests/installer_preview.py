"""Local visual fixture for the installer UI. NEVER installs or downloads packages.

Run: python install/tests/installer_preview.py
Open http://127.0.0.1:8765 — all displayed package data is synthetic test data.
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from download_queue import Package

DESKTOP = Path(__file__).resolve().parents[1] / "desktop"
mode = "failed"
update_started = False
live = "--live" in sys.argv


def state():
    rows = []
    for name, status in [("hyprland", "VERIFIED"), ("quickshell", "FAILED"), ("mesa", "VERIFIED")]:
        p = Package(name, "fixture-1", "fixture-repository", 30 * 1048576, name + ".pkg", "fixture")
        p.state, p.received, p.percent = status, p.size, 100
        p.checksum_verified = status == "VERIFIED"
        if name == "quickshell":
            p.attempts, p.mirror = 3, "fixture.invalid"
            if mode == "failed":
                p.error, p.received, p.percent = "Connection timeout", 0, 0
            else:
                p.state, p.percent, p.received = "DOWNLOADING", 47, int(p.size * .47)
                p.rate, p.average, p.eta = 1.6 * 1048576, 1.8 * 1048576, 10
        if mode == "downloading" and name == "mesa":
            p.state, p.percent, p.received = "DOWNLOADING", 62, int(p.size * .62)
            p.checksum_verified = False
            p.rate, p.average, p.eta = 2.8 * 1048576, 2.7 * 1048576, 4
        rows.append(p.public())
    run = dict(status="Failed" if mode == "failed" else "Downloading", code=1 if mode == "failed" else None,
               component="Distribution packages", phase=2, total=6, completed=1, elapsed=42, active=0, idle=0,
               metrics={}, network="Fixture only", processes=[], latest="VISUAL TEST — synthetic package data",
               path="fixture.log", lines=[], prompt="", partial="", secret=False, diagnostic="",
               queue={"stage": "BLOCKED" if mode == "failed" else "DOWNLOAD", "total": 3, "limit": 4,
                      "rate": sum(p["rate"] or 0 for p in rows), "download": "FAILED" if mode == "failed" else "RUNNING"}, downloads=rows, reports=[])
    return {"run": run, "launchError": ""}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, data, mime="application/json"):
        body = json.dumps(data).encode() if mime == "application/json" else data
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/inventory":
            self.send(dict(inventory={"meta": [["CachyOS · VISUAL TEST", "cachyos", "pacman", "fixture", "unknown", "fresh"]],
                                      "selected": [["hyprland"]], "component": [], "package": [], "disk": []},
                           actions={"install": "Install"}, compositors=["hyprland"], options={}))
        elif path == "/status":
            self.send(state())
        elif path == "/updates/status":
            run = None
            if update_started:
                run = dict(state()["run"], path="/tmp/system-update.fixture.log", phase=0, total=None)
            self.send(dict(pm="pacman", mode="balanced", checking=False, run=run, operation="upgrade",
                           approval=None if live or update_started else "preview-only",
                           plan=dict(os="CachyOS · VISUAL TEST", live=live, reboot="kernel_changed",
                                     download=3 * 1048576, change=225 * 1024, repos=["fixture-repository"],
                                     disks=[dict(paths=["/var", "/usr"], free=32 * 1048576, required=10 * 1048576)],
                                     packages=[dict(name="linux-cachyos", old="1", version="2", repo="fixture-repository")],
                                     snapshot=not live, actions=["aur", "flatpak-user"])))
        elif path == "/updates/history":
            self.send([dict(id="system-update.fixture.log", date=1700000000, operation="upgrade", status="Completed")])
        elif path == "/updates/report":
            self.send(dict(id="system-update.fixture.log", journal="VISUAL TEST REPORT"))
        elif path == "/report.json":
            self.send(state()["run"])
        elif path == "/report.txt":
            self.send(b"VISUAL TEST REPORT - synthetic fixture", "text/plain")
        elif path in {"/", "/installer.js", "/installer.css", "/system-updates.js"}:
            file = DESKTOP / ("index.html" if path == "/" else path[1:])
            self.send(file.read_bytes(), {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                                          ".css": "text/css; charset=utf-8"}[file.suffix])
        else:
            self.send_error(404)

    def do_POST(self):
        global mode, update_started
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if self.path in {"/retry", "/updates/upgrade"}:
            mode = "downloading"
        if self.path == "/updates/upgrade":
            update_started = True
        self.send({})


if __name__ == "__main__":
    print("Visual fixture only: http://127.0.0.1:8765", flush=True)
    HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
