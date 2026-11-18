#!/usr/bin/env python3
"""Desktop and terminal entry points for the Serpantinum installer."""

import argparse
import collections
import errno
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, HTTPServer


from download_queue import DOWNLOAD_MODES


HERE = Path(__file__).resolve().parent
INSTALLER = HERE / "install.sh"
ACTIONS = {
    "install": "Install", "verify": "Verify", "repair": "Repair",
    "update": "Update", "missing": "Install Missing",
}
COMPOSITORS = ("hyprland", "niri", "sway", "mango")
OPTIONS = {
    "config": "Deploy compositor and Kitty configuration",
    "replace": "Replace matching config files with mandatory backups",
    "backup": "Take a private settings snapshot first",
    "global-launchers": "Install compatibility launch links in /usr/local/bin",
    "services": "Configure system and PipeWire services (includes PAM)",
    "sddm": "Install and configure SDDM and its theme",
    "wayland": "Use the SDDM Wayland greeter",
    "display-manager": "Switch the current display manager to SDDM",
    "engines": "Install Ski, Audio DSP, Core and Gamma",
    "vpn": "Install offline VPN and system TUN integration",
    "fonts": "Install Iosevka Nerd Fonts",
    "wallpapers": "Download a small wallpaper selection",
    "full-wallpapers": "Download the full wallpaper collection",
    "sync": "Refresh pacman databases and upgrade all system packages",
    "aur": "Allow the reviewed AUR fallback for Quickshell",
    "build": "Allow source builds and their build dependencies",
    "telemetry": "Send anonymous installation telemetry",
    "launch": "Start Serpantinum after verification",
}
ANSI = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]|\x1b[()][0-9A-Z]")
CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f]")
PROMPT = re.compile(
    r"@@ask\b|\[\s*(?:[yn]/[yn]|[yn]/[yn]/[?])\s*\]|"
    r"Enter a (?:selection|number)|\(default[ =:]|"
    r"(?:password|passphrase).*:\s*$|\?\s*$", re.I,
)
SECRET_PROMPT = re.compile(r"(?:password|passphrase).*:\s*$|\[Serpantinum sudo\]", re.I)
TRANSFER = re.compile(r"(?:download|receiving objects|[KMG]i?B/s)", re.I)
NETWORK_ERROR = re.compile(r"could not resolve|failed retrieving|could not connect|network is unreachable|"
                           r"connection timed out|failed to download|failed to fetch|SSL certificate", re.I)
COUNTER = re.compile(r"^[([]\s*(\d+)\s*/\s*(\d+)\s*[)\]]\s*(.*)")
RATE = re.compile(r"\b\d+(?:\.\d+)?\s*[KMGT]?i?B/s\b", re.I)
SIZE = re.compile(r"\b\d+(?:\.\d+)?\s*[KMGT]i?B\b(?!/s)", re.I)
PERCENT = re.compile(r"(?<![\d.])(\d{1,3}(?:\.\d+)?)%")
DIAGNOSTICS = (
    (NETWORK_ERROR, "Check the active connection and repository mirrors. Retry after reaching the server."),
    (re.compile(r"disk full|no space left|insufficient.*(?:free|space)|not enough free disk", re.I),
     "Free space on the reported filesystem and review the installation plan again."),
    (re.compile(r"db\.lck|unable to lock database|waiting for process with pid", re.I),
     "Let the other package manager finish. Retry when the package database lock is released."),
    (re.compile(r"invalid.*signature|unknown trust|signature verification failed|public key is not installed", re.I),
     "Check the system clock and the repository signing key. Use trusted repository keys when retrying."),
    (re.compile(r"conflicting dependencies|package conflict|conflicting files|transaction test error", re.I),
     "Review the conflicting packages or files in the journal and resolve the transaction before retrying."),
)


def clean(value):
    return CONTROL.sub("", ANSI.sub("", value))


def normalize_plan(data):
    action = data.get("action")
    compositors = data.get("compositors")
    options = data.get("options")
    if not isinstance(action, str) or action not in ACTIONS or not isinstance(compositors, list) or not isinstance(options, list):
        raise ValueError("Invalid installation plan.")
    if any(not isinstance(name, str) or name not in COMPOSITORS for name in compositors) or any(
        not isinstance(name, str) or name not in OPTIONS for name in options
    ):
        raise ValueError("Unknown component or option.")
    download_mode = data.get("download_mode", "balanced")
    if not isinstance(download_mode, str) or download_mode not in DOWNLOAD_MODES:
        raise ValueError("Unknown package download mode.")
    chosen = set(options) if action != "verify" else set()
    if {"wayland", "display-manager"} & chosen and "sddm" not in chosen:
        raise ValueError("Select SDDM before changing its greeter or switching display managers.")
    if "full-wallpapers" in chosen and "wallpapers" not in chosen:
        raise ValueError("Enable wallpaper downloads before choosing the full pack.")
    return {
        "action": action,
        "compositors": [name for name in COMPOSITORS if name in compositors],
        "options": [name for name in OPTIONS if name in chosen],
        "download_mode": download_mode,
    }


def backend_args(mode, plan=None, resume=1):
    if plan is None:
        return ["bash", str(INSTALLER), mode, "inspect", "auto"]
    return [
        "bash", str(INSTALLER), mode, plan["action"],
        ",".join(plan["compositors"]), ",".join(plan["options"]), str(resume), plan.get("download_mode", "balanced"),
    ]


def probe(plan=None):
    result = subprocess.run(
        backend_args("--manager-probe", plan), stdin=subprocess.DEVNULL,
        capture_output=True, text=True, errors="replace", timeout=90,
    )
    records = collections.defaultdict(list)
    for line in result.stdout.splitlines():
        name, *fields = clean(line).split("\t")
        if fields:
            records[name].append(fields)
    if result.returncode != 0 or not records["meta"]:
        raise ValueError(clean(result.stderr.strip()) or "The installer could not read the system inventory.")
    warnings = dict.fromkeys(clean(line) for line in result.stderr.splitlines() if line.strip())
    records["warning"].extend([line] for line in warnings)
    return records


def installer_state_dir():
    home = Path.home()
    state = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state") / "serpantinum"
    legacy = home / ".local/state/serpantinum"
    if not (state / "version").exists() and (legacy / "version").is_file():
        state = legacy
    return state


def atomic_text(path, contents):
    fd, temporary = tempfile.mkstemp(prefix=".install-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as target:
            target.write(contents)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def log_file():
    state = installer_state_dir()
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, path = tempfile.mkstemp(prefix="install.", suffix=".log", dir=state, text=True)
    return os.fdopen(fd, "w", encoding="utf-8", buffering=1), path


def process_activity(pid):
    """Read installer descendants, including a sudo monitor where visible."""
    queue = [pid]
    rows = []
    visited = set()
    for child in queue:
        if child in visited or len(visited) >= 256:
            continue
        visited.add(child)
        try:
            proc = Path("/proc") / str(child)
            name, _, stats = (proc / "stat").read_text().rpartition(") ")
            fields = stats.split()
            ticks = int(fields[11]) + int(fields[12])
            rows.append((child, ticks, name.partition("(")[2]))
            queue.extend(int(n) for n in (proc / f"task/{child}/children").read_text().split())
        except (OSError, ValueError, IndexError):
            continue
    return rows


class Run:
    def __init__(self, command):
        import codecs
        import pty

        self.log, self.path = log_file()
        self.started = self.last_event = self.last_activity = time.monotonic()
        self.lines = collections.deque(maxlen=800)
        self.cursor = self.phase = self.completed = 0
        self.total = None
        self.finished = None
        self.status = "Preparing"
        self.component = "Serpantinum"
        self.latest = self.pending = self.prompt = ""
        self.secret = self.cancelled = False
        self.reply_in_flight = False
        self.exit_code = None
        self.network = "No transfer reported"
        self.diagnostic = ""
        self.metrics = {}
        self.downloads = {}
        self.queue = {}
        self.reports = []
        self.integration = "PENDING"
        self.integration_detail = ""
        self.components = {}
        self.children = []
        self.next_sample = 0
        self.decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        env = dict(os.environ, TERM="dumb", PAGER="cat", NO_COLOR="1", LC_ALL="C.UTF-8")
        try:
            self.pid, self.fd = pty.fork()
        except OSError:
            self.log.close()
            raise
        if self.pid == 0:
            try:
                os.execvpe(command[0], command, env)
            except OSError as exc:
                os.write(2, f"Cannot start installation worker. {exc}\n".encode())
            os._exit(127)
        import fcntl
        import struct
        import termios
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 36, 120, 0, 0))
        os.set_blocking(self.fd, False)

    def append(self, message):
        self.cursor += 1
        self.lines.append((self.cursor, message))
        self.log.write(message + "\n")
        self.latest = message

    def consume(self, line):
        line = clean(line).strip()
        if not line:
            return
        fields = line.split("\t")
        if fields[0] in {"@@queue", "@@report"} and len(fields) == 2:
            try:
                event = json.loads(fields[1])
            except (ValueError, TypeError):
                return
            if not isinstance(event, dict):
                return
            if fields[0] == "@@report":
                event["packages"] = list(self.downloads.values())
                self.reports.append(event)
                self.save_reports()
                self.append(f"Download: {event.get('download', 'PENDING')} · "
                            f"{event.get('downloaded', 0)}/{event.get('total', 0)} checksums verified · "
                            f"Verification: {event.get('verification', 'PENDING')} · "
                            f"Installation: {event.get('installation', 'PENDING')}")
                if event.get("error"):
                    self.append(event["error"])
                for pkg in event["packages"]:
                    if pkg.get("error"):
                        self.append(f"{pkg['name']}: {pkg['error']} · attempts {pkg['attempts']} · {pkg['mirror']}")
                return
            if event.get("reset"):
                self.downloads = {}
            self.queue = event
            package = event.get("package")
            if isinstance(package, dict) and package.get("name"):
                previous = self.downloads.get(package["name"], {})
                self.downloads[package["name"]] = package
                if previous.get("state") != package.get("state"):
                    self.append(f"{package['name']} {package['version']} · {package['state']} · {package.get('error', '')}")
                self.component = package["name"]
                self.metrics = {"package": package["name"], "percent": package.get("percent")}
            self.status = {"DOWNLOAD": "Downloading", "VERIFYING": "Verifying", "INSTALLING": "Installing",
                           "BLOCKED": "Failed", "READY": "Verifying", "INSTALLED": "Installing"}.get(event.get("stage"), "Downloading")
            self.network = "Measured package file bytes"
            return
        if len(fields) == 4 and fields[0] == "@@component":
            name, state, detail = fields[1:]
            self.components[name] = dict(state=state, detail=detail)
            self.append(f"{name} · {state} · {detail}")
            return
        if len(fields) == 3 and fields[0] == "@@integration":
            self.integration, self.integration_detail = fields[1:]
            self.append(self.integration_detail)
            return
        if len(fields) == 5 and fields[0] == "@@phase" and all(v.isdigit() for v in fields[1:3]):
            self.phase, self.total = map(int, fields[1:3])
            self.status, self.component = fields[3:]
            self.metrics = {}
            self.append(f"{self.status} · {self.component}")
            return
        if len(fields) == 2 and fields[0] == "@@done" and fields[1].isdigit():
            self.completed = int(fields[1])
            return
        if len(fields) == 3 and fields[0] == "@@activity":
            self.status, self.component = fields[1:]
            self.metrics = {}
            self.append(f"{self.status} · {self.component}")
            return
        line = line.removeprefix("@@ask\t")
        self.append(line)
        if NETWORK_ERROR.search(line):
            self.network = "Transfer error reported"
        for pattern, diagnostic in DIAGNOSTICS:
            if pattern.search(line):
                self.diagnostic = diagnostic
                break
        count = COUNTER.match(line)
        installing = False
        if count:
            done, total, text = count.groups()
            if re.search(r"\b(?:installing|upgrading|reinstalling)\b", text, re.I):
                installing = True
                self.status = "Updating" if "upgrading" in text.lower() else "Installing"
                self.metrics = {"package": text, "count": f"{done} / {total} (current package)"}
        speed, size = RATE.search(line), SIZE.search(line)
        percent = PERCENT.search(line)
        if not installing and (speed or (percent and (TRANSFER.search(line) or line.startswith("#")))):
            self.status = "Downloading"
            self.network = "Transfer reported by backend"
            self.metrics = {}
            if percent and float(percent[1]) <= 100:
                self.metrics["percent"] = float(percent[1])
            if speed:
                self.metrics["rate"] = speed[0]
            if size:
                self.metrics["size"] = size[0]
            if count:
                self.metrics["package"] = count[3].split("|", 1)[0].strip()
                self.metrics["count"] = f"{count[1]} / {count[2]} (current transfer)"
        if re.search(r"==> (?:Starting (?:build|prepare)\(\)|Making package)", line):
            self.status = "Building"
            self.metrics = {}

    def update(self):
        if self.fd is None:
            self.reap()
            return
        now = time.monotonic()
        for _ in range(16):
            try:
                chunk = os.read(self.fd, 16384)
            except BlockingIOError:
                break
            except OSError as exc:
                if exc.errno != errno.EIO:
                    raise
                chunk = b""
            if not chunk:
                self.consume(self.pending + self.decoder.decode(b"", final=True))
                os.close(self.fd)
                self.fd = None
                break
            self.last_event = self.last_activity = now
            self.reply_in_flight = False
            split = re.split(r"[\r\n]", self.pending + self.decoder.decode(chunk))
            for line in split[:-1]:
                self.consume(line)
            self.pending = split[-1][-16384:]
        if self.fd is None:
            self.reap()
            return
        tail = clean(self.pending).strip()
        if not tail and PROMPT.search(self.latest):
            tail = self.latest
        self.secret = self.echo_disabled() or bool(SECRET_PROMPT.search(tail))
        self.prompt = tail if not self.cancelled and not self.reply_in_flight and PROMPT.search(tail) else ""
        if now >= self.next_sample:
            rows = process_activity(self.pid)
            if rows != self.children:
                self.last_activity = now
                self.children = rows
            self.next_sample = now + 2

    def reap(self):
        if self.exit_code is not None:
            return
        waited, status = os.waitpid(self.pid, os.WNOHANG)
        if not waited:
            return
        self.exit_code = os.waitstatus_to_exitcode(status)
        self.finished = time.monotonic()
        self.status = ("Cancelled" if self.cancelled else
                       "Completed" if self.exit_code == 0 else "Failed")
        self.pending = self.prompt = ""
        if self.exit_code and self.total == 6 and self.phase in {4, 5, 6} and self.integration == "PENDING":
            self.integration = "CANCELLED" if self.cancelled else "FAILED"
            self.integration_detail = f"Phase {self.phase} · {self.latest}"
        self.append(f"{self.status} · exit {self.exit_code}")
        if self.reports or self.queue or self.components or self.integration != "PENDING":
            self.save_reports()
        self.log.close()

    def echo_disabled(self):
        import termios
        try:
            return not termios.tcgetattr(self.fd)[3] & termios.ECHO
        except (OSError, termios.error):
            return False

    def answer(self, answer, secret):
        if self.fd is None or self.cancelled or self.reply_in_flight:
            raise ValueError("The worker is not accepting another response yet.")
        if not isinstance(answer, str) or len(answer.encode()) > 1024 or any(ord(c) < 32 or ord(c) == 127 for c in answer):
            raise ValueError("Enter a single line of terminal input.")
        if (secret or self.secret) and not self.echo_disabled():
            raise ValueError("The terminal has not disabled echo. Wait for the password prompt before sending.")
        self.reply_in_flight = True
        if self.prompt:
            self.append(self.prompt.removeprefix("@@ask\t"))
        self.pending = self.prompt = ""
        os.write(self.fd, (answer + "\n").encode())

    def cancel(self):
        if self.fd is not None and not self.cancelled:
            self.cancelled = True
            self.prompt = ""
            self.append("Cancel requested. Waiting for the current command to stop safely.")
            os.write(self.fd, b"\x03")

    def state(self, after):
        now = self.finished or time.monotonic()
        return dict(
            status="Waiting for Input" if self.prompt else "Cancelling" if self.cancelled and self.fd is not None else self.status,
            component=self.component, latest=self.latest, partial=clean(self.pending),
            prompt=self.prompt.removeprefix("@@ask\t"), secret=self.secret,
            phase=self.phase, total=self.total, completed=self.completed,
            elapsed=int(now - self.started), idle=int(now - self.last_event),
            active=int(now - self.last_activity), processes=sorted({row[2] for row in self.children}),
            network=self.network, metrics=self.metrics, diagnostic=self.diagnostic, path=self.path, code=self.exit_code,
            queue=self.queue, downloads=list(self.downloads.values()), reports=self.reports,
            integration=self.integration, integration_detail=self.integration_detail, components=self.components,
            lines=[(idx, line) for idx, line in self.lines if idx > after],
        )

    def report(self):
        return {"status": self.status, "exit_code": self.exit_code,
                "integration": self.integration, "integration_detail": self.integration_detail, "components": self.components,
                "transactions": self.reports,
                "current": dict(self.queue, packages=list(self.downloads.values()))}

    def save_reports(self):
        if not getattr(self, "path", None):
            return
        report = self.report()
        try:
            for suffix, contents in (("json", json.dumps(report, ensure_ascii=False, indent=2)),
                                     ("txt", report_text(report))):
                atomic_text(Path(self.path + ".report." + suffix), contents)
        except OSError:
            self.append("Could not save report on disk. Use Export Installation Report while this window is open.")


class Manager:
    def __init__(self):
        self.inventory = probe()
        self.plan = None
        self.review_key = None
        self.active_plan = None
        self.run = None
        self.launch_error = ""
        self.launch_checked = False
        self.resume_phase = self.review_resume = 1
        self.saved_phase = None
        self.last_snapshot = 0
        self.checkpoint = installer_state_dir() / "install.resume.json"
        try:
            self.boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        except OSError:
            self.boot = None

    def saved(self):
        try:
            saved = json.loads(self.checkpoint.read_text())
            if saved["distro"] != self.inventory["meta"][0][1] or saved["commit"] != self.inventory["meta"][0][4]:
                return None
            plan = normalize_plan(saved["plan"])
            phase = saved["phase"] if saved["boot"] == self.boot else 1
            if type(phase) is not int or phase not in range(1, 7) or plan["action"] == "verify":
                return None
            backend = self.inventory["meta"][0][2]
            cache = Path(os.getenv("XDG_CACHE_HOME") or Path.home() / ".cache") / "serpantinum-installer/packages" / backend
            return dict(plan=plan, phase=phase, cache_available=cache.is_dir())
        except (OSError, ValueError, KeyError, TypeError, AttributeError):
            return None

    def persist(self):
        if self.active_plan["action"] == "verify" or not self.run.phase:
            return
        try:
            phase = min(6, max(self.resume_phase, self.run.completed + 1))
            if self.run.exit_code == 0 and not self.run.cancelled:
                self.checkpoint.unlink(missing_ok=True)
            elif phase != self.saved_phase:
                atomic_text(self.checkpoint, json.dumps(dict(plan=self.active_plan, phase=phase, boot=self.boot,
                    distro=self.inventory["meta"][0][1], commit=self.inventory["meta"][0][4], log=self.run.path)))
                self.saved_phase = phase
        except OSError as exc:
            self.run.append(f"Could not save installation checkpoint. {exc}")

    def review(self, data, saved=False):
        resume = self.saved() if saved else None
        if saved and not resume:
            raise ValueError("The saved installation plan is unavailable.")
        plan = resume["plan"] if resume else normalize_plan(data)
        self.review_resume = resume["phase"] if resume else 1
        pm = self.inventory["meta"][0][2]
        if pm != "pacman" and set(plan["options"]) & {"sync", "aur"}:
            raise ValueError("AUR and synchronization options apply to pacman.")
        records = probe(plan)
        if resume:
            cache = "Existing archives will be rechecked." if resume["cache_available"] else "Previous package cache is unavailable."
            records["change"].append([f"Resume at phase {self.review_resume}. {cache}"])
        if plan["action"] != "verify":
            records["change"].append([f"Package download mode: {plan['download_mode'].title()}."])
        if "launch" in plan["options"]:
            records["change"].append(["Start Serpantinum in this session after successful verification."])
        self.plan = plan if not records["error"] else None
        self.review_key = secrets.token_urlsafe(18) if self.plan else None
        records["approval"] = self.review_key
        return records

    def start(self, mode="start", approval=None):
        if self.run and self.run.exit_code is None:
            raise ValueError("An installation is already running.")
        resume = self.review_resume
        if mode in {"retry", "restart"}:
            if not self.run or (self.run.exit_code == 0 and not self.run.cancelled):
                raise ValueError("There is no failed or cancelled operation to recover.")
            resume = (self.run.phase or self.resume_phase) if mode == "retry" else 1
            plan = self.active_plan
        else:
            if not self.plan or approval != self.review_key:
                raise ValueError("Review and approve the current installation plan first.")
            plan = self.plan
            self.plan = self.review_key = None
        self.run = Run(backend_args("--manager-run", plan, resume))
        self.active_plan = plan
        self.resume_phase = resume
        self.saved_phase = None
        self.last_snapshot = time.monotonic()
        self.persist()
        self.launch_checked = False
        self.launch_error = ""

    def launch(self):
        if not self.run or self.run.exit_code != 0 or self.run.cancelled:
            raise ValueError("A successful check is required before launching.")
        if not os.environ.get("WAYLAND_DISPLAY"):
            raise ValueError("Open a Wayland session to run the shell.")
        launcher = Path.home() / ".local/bin/serpantinumd"
        if not os.access(launcher, os.X_OK):
            raise ValueError("The user launcher is missing.")
        env = dict(os.environ)
        env.pop("SERPANTINUM_INSTALLER", None)
        subprocess.Popen([str(launcher), "start"], start_new_session=True,
                         env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL)

    def update(self):
        if not self.run:
            return
        self.run.update()
        if not self.launch_checked:
            self.persist()
        now = time.monotonic()
        if self.run.exit_code is None and self.run.queue and now - self.last_snapshot >= 5:
            self.run.save_reports()
            self.last_snapshot = now
        if self.run.exit_code is not None and not self.launch_checked:
            self.launch_checked = True
            if self.run.exit_code == 0 and not self.run.cancelled and "launch" in self.active_plan["options"]:
                try:
                    self.launch()
                except (OSError, ValueError) as exc:
                    self.launch_error = str(exc)

    def cancel_and_wait(self):
        if self.run and self.run.exit_code is None:
            self.run.cancel()
            while self.run.exit_code is None:
                self.update()
                time.sleep(0.1)


def report_text(report):
    from download_queue import redact
    lines = ["SERPANTINUM INSTALLATION REPORT", f"Status: {report['status']}",
             f"System integration: {report.get('integration', 'PENDING')}", report.get("integration_detail", "")]
    for name, component in report.get("components", {}).items():
        lines.append(f"{name}: {component['state']} · {component['detail']}")
    transactions = report["transactions"] or [report["current"]]
    for number, transaction in enumerate(transactions, 1):
        packages = transaction.get("packages", [])
        lines.extend([f"Transaction {number}: {transaction.get('stage', 'unknown')}",
                      f"Total: {len(packages)}", transaction.get("error", "")])
        for label in ("download", "verification", "installation"):
            lines.append(f"{label.title()}: {transaction.get(label, 'PENDING')}")
        lines.extend(transaction.get("native_errors", []))
        for pkg in packages:
            lines.append(f"{pkg['name']} {pkg['version']} [{pkg['repository']}] {pkg['state']} | "
                         f"{pkg['received']} / {pkg['size']} bytes | Attempts: {pkg['attempts']} | "
                         f"Mirror: {pkg['mirror']} | {pkg['error']} {pkg['detail']}")
    return redact("\n".join(lines))


def summary(inventory, packages=False):
    os_name, distro, manager, version, commit, state = inventory["meta"][0]
    print(f"\nSERPANTINUM  {version} / {commit}")
    print(f"{os_name} ({distro}) · {manager} · {state}")
    for warning in inventory["warning"] + inventory["error"]:
        print(f"! {warning[0]}")
    for component, state, detail in inventory["component"]:
        print(f"  {component:22} {state:16} {detail}")
    if packages:
        for state in ("Installed", "Missing"):
            print(f"  {state}: " + (", ".join(name for name, value in inventory["package"] if value == state) or "—"))


def print_plan(records):
    summary(records, packages=True)
    for path, minimum, free in records["disk"]:
        print(f"  Space at {path} · {minimum} KiB required before transactions · {free} KiB free")
    for change in records["change"]:
        print(f"  • {change[0]}")


def terminal_run(manager):
    import getpass
    import termios

    cursor = 0
    run = manager.run
    last_status = None
    last_transfer = 0
    while run.exit_code is None:
        try:
            manager.update()
            state = run.state(cursor)
            for cursor, line in state["lines"]:
                print(line, flush=True)
            queue = state["queue"]
            if queue.get("stage") == "DOWNLOAD" and state["elapsed"] > last_transfer:
                last_transfer = state["elapsed"]
                print(f"Downloads {queue.get('active', 0)}/{queue.get('limit', 0)} · "
                      f"{(queue.get('rate') or 0) / 1048576:.2f} MiB/s · "
                      f"Completed {queue.get('completed', 0)}/{queue.get('total', 0)} · "
                      f"Failed {queue.get('failed', 0)} · Deferred {queue.get('deferred', 0)}")
                for pkg in state["downloads"]:
                    if pkg["state"] == "DOWNLOADING":
                        progress = f"{pkg['percent']:.1f}%" if pkg["percent"] is not None else f"{pkg['received']} bytes"
                        rate = f"{pkg['rate'] / 1048576:.2f} MiB/s" if pkg["rate"] is not None else "measuring"
                        print(f"  {pkg['name']} {pkg['version']} · {progress} · {rate}")
            prompt = state["prompt"]
            if prompt and prompt != last_status:
                print(f"Waiting for Input · {prompt}", flush=True)
            if prompt:
                last_status = prompt
                answer = getpass.getpass("> ") if state["secret"] else input("> ")
                run.answer(answer, state["secret"])
                last_status = None
            elif run.exit_code is None and select.select([sys.stdin], [], [], 0.2)[0]:
                # For prompts with no recognizable wording, Enter opens manual input.
                if not sys.stdin.readline():
                    run.cancel()
                    continue
                if state["partial"]:
                    print(state["partial"])
                answer = getpass.getpass("Worker input: ") if state["secret"] else input("Worker input: ")
                run.answer(answer, state["secret"])
            elif run.exit_code is None and state["elapsed"] % 15 == 0 and state["elapsed"] != last_status:
                last_status = state["elapsed"]
                if last_status:
                    print(f"{state['status']} · {last_status}s · last output {state['idle']}s ago · "
                          f"{', '.join(state['processes']) or 'worker running'}")
        except (KeyboardInterrupt, EOFError):
            run.cancel()
        except (ValueError, termios.error) as exc:
            print(exc, file=sys.stderr)
        if run.exit_code is None:
            time.sleep(0.05)
    status = run.status
    if run.exit_code == 0 and not run.cancelled and manager.active_plan["action"] != "verify":
        status = "INSTALLATION COMPLETED"
        if any(report.get("native_errors") for report in run.reports):
            status += " WITH WARNINGS"
    print(f"{status} · Log {run.path}")
    if run.exit_code != 0 and run.diagnostic:
        print(run.diagnostic)
    if manager.launch_error:
        print(manager.launch_error)


def terminal(manager):
    summary(manager.inventory, packages=True)
    print("\nCtrl+C requests cancellation during a run. Enter opens manual input for an unrecognized prompt.")
    while True:
        saved = manager.saved()
        print("\n" + "   ".join(f"{i}. {label}" for i, label in enumerate(ACTIONS.values(), 1)) +
              ("   R. Review saved plan" if saved else "") + "   Q. Quit")
        value = input("Action: ").strip().lower()
        if value == "q":
            return
        try:
            if value == "r" and saved:
                records = manager.review({}, saved=True)
            elif value in {"1", "2", "3", "4", "5"}:
                records = manager.review(terminal_plan(manager, list(ACTIONS)[int(value) - 1]))
            else:
                continue
            print_plan(records)
            if not manager.plan or input("Approve this plan? [y/N] ").strip().lower() != "y":
                continue
            manager.start(approval=records["approval"])
            while True:
                terminal_run(manager)
                if manager.run.exit_code == 0 and not manager.run.cancelled:
                    if "launch" not in manager.active_plan["options"] and input("Launch Serpantinum? [y/N] ").strip().lower() == "y":
                        manager.launch()
                    break
                choice = input("Retry step [r], restart plan [a], or return to actions [Enter]: ").strip().lower()
                if choice not in {"r", "a"}:
                    break
                manager.start("retry" if choice == "r" else "restart")
            manager.inventory = probe()
        except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
            print(exc, file=sys.stderr)


def terminal_plan(manager, action):
    defaults = manager.inventory["selected"][0][0].split() or ["hyprland"]
    compositors = input(f"Compositor(s) [{' '.join(defaults)}]: ").lower().split() or defaults
    options = []
    download_mode = "balanced"
    if action != "verify":
        available = [name for name in OPTIONS if name not in {"aur", "sync"} or manager.inventory["meta"][0][2] == "pacman"]
        for i, name in enumerate(available, 1):
            print(f"  {i:2}. {OPTIONS[name]}")
        suggested = [str(available.index(name) + 1) for name in ("config", "backup")]
        print(f"  Suggested first install: configuration and a private snapshot ({' '.join(suggested)}).")
        options = [available[int(n) - 1] for n in input("Option numbers [none]: ").split()
                   if n.isdecimal() and 1 <= int(n) <= len(available)]
        download_mode = input("Download mode (Stable 1, Balanced 4, Fast 8, Adaptive 1–8) [Balanced]: ").strip().lower() or "balanced"
    return dict(action=action, compositors=compositors, options=options, download_mode=download_mode)


class LocalServer(HTTPServer):
    allow_reuse_address = False
    timeout = 0.12

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(1)
        return connection, address


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def send(self, status, payload, content_type="application/json"):
        if not isinstance(payload, bytes):
            payload = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'self'; "
                         "font-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
        self.end_headers()
        self.wfile.write(payload)

    def authorized(self, post=False):
        return (self.headers.get("Host") == self.server.host and
                (not post or self.headers.get("Origin") == self.server.origin) and
                hmac.compare_digest(self.headers.get("X-Installer-Key", "").encode(),
                                    self.server.key.encode()))

    def do_GET(self):
        path, _, query = self.path.partition("?")
        if self.headers.get("Host") != self.server.host:
            self.send(403, {"error": "Invalid host."})
            return
        assets = {
            "/": ("index.html", "text/html; charset=utf-8"),
            "/installer.css": ("installer.css", "text/css; charset=utf-8"),
            "/installer.js": ("installer.js", "text/javascript; charset=utf-8"),
        }
        if path in assets:
            name, mime = assets[path]
            self.send(200, (HERE / "desktop" / name).read_bytes(), mime)
            return
        if not self.authorized():
            self.send(403, {"error": "Open the installer link from its terminal."})
            return
        manager = self.server.manager
        if path == "/inventory":
            self.server.connected = True
            self.send(200, dict(inventory=manager.inventory, actions=ACTIONS, options=OPTIONS, compositors=COMPOSITORS, saved=manager.saved()))
        elif path == "/status":
            after = int(query) if query.isdecimal() and len(query) < 12 else 0
            self.send(200, dict(run=manager.run.state(after) if manager.run else None, launchError=manager.launch_error))
        elif path == "/journal" and manager.run:
            self.send(200, Path(manager.run.path).read_bytes(), "text/plain; charset=utf-8")
        elif path in {"/report.json", "/report.txt"} and manager.run:
            report = manager.run.report()
            if path.endswith(".json"):
                self.send(200, report)
            else:
                self.send(200, report_text(report), "text/plain; charset=utf-8")
        else:
            self.send(404, {"error": "Unknown installer route."})

    def do_POST(self):
        manager = self.server.manager
        try:
            size = int(self.headers.get("Content-Length", 0))
            if size <= 0 or size > 8192:
                raise ValueError("Invalid request size.")
            body = self.rfile.read(size)
            if not self.authorized(post=True):
                self.send(403, {"error": "Invalid installer session."})
                return
            data = json.loads(body)
            if not isinstance(data, dict):
                raise ValueError("Expected an installation request.")
            if self.path in {"/review", "/review-saved", "/refresh"} and manager.run and manager.run.exit_code is None:
                raise ValueError("Wait for the current operation to finish.")
            if self.path in {"/review", "/review-saved"}:
                self.send(200, manager.review(data, saved=self.path == "/review-saved"))
                return
            if self.path == "/refresh":
                manager.inventory = probe()
                manager.plan = None
                self.send(200, manager.inventory)
                return
            if self.path == "/start":
                manager.start(approval=data.get("approval"))
            elif self.path == "/retry":
                manager.start("retry")
            elif self.path == "/restart":
                manager.start("restart")
            elif self.path == "/cancel" and manager.run:
                manager.run.cancel()
            elif self.path == "/answer" and manager.run:
                manager.run.answer(data.get("answer"), data.get("secret") is True)
            elif self.path == "/launch":
                manager.launch()
            elif self.path == "/close":
                if manager.run and manager.run.exit_code is None:
                    raise ValueError("Cancel the operation and wait for it to stop before closing.")
                self.server.closed = True
            else:
                self.send(404, {"error": "Unknown installer action."})
                return
            self.send(200, {"ok": True})
        except (ValueError, OSError, subprocess.TimeoutExpired) as exc:
            self.send(400, {"error": str(exc)})


def desktop(manager):
    with LocalServer(("127.0.0.1", 0), Handler) as server:
        server.host = f"127.0.0.1:{server.server_port}"
        server.origin = f"http://{server.host}"
        server.key = secrets.token_urlsafe(32)
        server.manager = manager
        server.closed = False
        server.connected = False
        url = f"{server.origin}/#{server.key}"
        print(f"Opening Serpantinum installer. Keep this process open.\n{url}", flush=True)
        opened = subprocess.Popen(["xdg-open", url], stdin=subprocess.DEVNULL,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            status = opened.wait(timeout=0.3)
            if status != 0:
                return False
        except subprocess.TimeoutExpired:
            pass
        startup_deadline = time.monotonic() + 45
        while not server.closed:
            manager.update()
            server.handle_request()
            if not server.connected and (opened.poll() not in {None, 0} or time.monotonic() > startup_deadline):
                print("Could not open the browser installer. Switching to the terminal interface.", file=sys.stderr)
                return False
        return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--tui", action="store_true")
    mode.add_argument("--check", action="store_true", help="print a read-only inventory and exit")
    args = parser.parse_args()
    manager = None

    def stop(_signum, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, stop)
    try:
        manager = Manager()
        if args.check:
            summary(manager.inventory, packages=True)
        elif not args.tui and (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")) and shutil.which("xdg-open") and desktop(manager):
            pass
        elif sys.stdin.isatty():
            terminal(manager)
        else:
            print("Open a terminal for --tui or use --check for the read-only inventory.", file=sys.stderr)
            return 1
    except (KeyboardInterrupt, EOFError):
        if manager:
            manager.cancel_and_wait()
        return 130
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"Serpantinum installer: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
