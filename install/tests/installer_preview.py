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


def state():
    rows = []
    for name, status in [("hyprland", "VERIFIED"), ("quickshell", "FAILED"), ("mesa", "VERIFIED")]:
        p = Package(name, "fixture-1", "fixture-repository", 30 * 1048576, name + ".pkg", "fixture")
        p.state, p.received, p.percent = status, p.size, 100
        if name == "quickshell":
            p.attempts, p.mirror = 3, "fixture.invalid"
            if mode == "failed":
                p.error, p.received, p.percent = "Connection timeout", 0, 0
            else:
                p.state, p.percent, p.received = "DOWNLOADING", 47, int(p.size * .47)
                p.rate, p.average, p.eta = 1.6 * 1048576, 1.8 * 1048576, 10
        rows.append(p.public())
    run = dict(status="Failed" if mode == "failed" else "Downloading", code=1 if mode == "failed" else None,
               component="Distribution packages", phase=2, total=6, completed=1, elapsed=42, active=0, idle=0,
               metrics={}, network="Fixture only", processes=[], latest="VISUAL TEST — synthetic package data",
               path="fixture.log", lines=[], prompt="", partial="", secret=False, diagnostic="",
               queue={"stage": "BLOCKED" if mode == "failed" else "DOWNLOAD", "total": 3}, downloads=rows, reports=[])
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
        elif path == "/report.json":
            self.send(state()["run"])
        elif path == "/report.txt":
            self.send(b"VISUAL TEST REPORT - synthetic fixture", "text/plain")
        elif path in {"/", "/installer.js", "/installer.css"}:
            file = DESKTOP / ("index.html" if path == "/" else path[1:])
            self.send(file.read_bytes(), {".html": "text/html", ".js": "text/javascript", ".css": "text/css"}[file.suffix])
        else:
            self.send_error(404)

    def do_POST(self):
        global mode
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if self.path == "/retry":
            mode = "downloading"
        self.send({})


if __name__ == "__main__":
    print("Visual fixture only: http://127.0.0.1:8765", flush=True)
    HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
