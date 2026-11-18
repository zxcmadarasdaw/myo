#!/usr/bin/env python3
"""Concurrent repository prefetch. Native managers own dependency/signature checks.

No package operation runs as part of an individual download. JSON events carry
measured bytes; command output is used only for diagnostics, never progress.
"""
import argparse
import base64
from collections import deque
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from dataclasses import dataclass, field, asdict
import hashlib
import heapq
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import urlsplit


STATES = "QUEUED CHECKING DOWNLOADING DOWNLOADED VERIFYING VERIFIED INSTALLING RETRYING DEFERRED FAILED INSTALLED".split()
GOOD = {"VERIFIED", "INSTALLED"}
DOWNLOAD_MODES = {"stable": 1, "balanced": 4, "fast": 8, "adaptive": 4}


def redact(value):
    # Repository credentials, subscription paths and query tokens never enter reports.
    return re.sub(r'(?:https?|ftp|file)://[^\s\"<>]+',
                  lambda m: (urlsplit(m[0]).hostname or "local") + "/[redacted]", str(value))


def reason(message, code=None):
    text = str(message).lower()
    for pattern, label in [
        ("no space|disk space", "Insufficient disk space"),
        ("permission denied|not permitted", "Permission denied"),
        ("checksum|sha256", "Checksum mismatch"),
        ("error invoking external downloader", "External downloader failed"),
        ("signature|gpg|public key", "Invalid package signature"),
        ("could not resolve|name or service|dns", "DNS resolution failure"),
        ("reset by peer|connection reset", "Connection reset"),
        ("404", "HTTP 404"), ("403", "HTTP 403"),
        (r"\b(?:ssl|tls|certificate)\b", "SSL/TLS error"),
        ("timeout|timed out|too slow", "Connection timeout"),
        ("conflict|unsatisfied|nothing provides|dependencies", "Dependency conflict"),
        ("target not found|no match|package not found", "Package not found"),
        ("cancel|interrupt", "Cancelled by user"),
        ("couldn't connect|failed to connect|no mirrors|unavailable", "Mirror unavailable"),
    ]:
        if re.search(pattern, text):
            return label
    return {5: "DNS resolution failure", 6: "DNS resolution failure", 7: "Mirror unavailable",
            23: "Insufficient disk space", 28: "Connection timeout", 35: "SSL/TLS error",
            37: "Mirror file unavailable", 56: "Connection reset", 60: "SSL/TLS error", 63: "Archive exceeds its declared size"}.get(code, "Unknown error")


@dataclass
class Package:
    name: str
    version: str
    repository: str
    size: int | None
    filename: str
    checksum: str
    urls: list = field(default_factory=list, repr=False)
    algorithm: str = "sha256"
    state: str = "QUEUED"
    received: int = 0
    attempts: int = 0
    error: str = ""
    detail: str = ""
    mirror: str = ""
    rate: float | None = None
    average: float | None = None
    percent: float | None = None
    eta: float | None = None
    warning: str = ""
    history: list = field(default_factory=list)
    signature: str = field(default="", repr=False)
    checksum_verified: bool = False

    def public(self):
        value = asdict(self)
        value.pop("urls")
        value.pop("signature")
        return value


@dataclass
class Settings:
    warning: float = 30
    timeout: float = 60
    attempts: int = 3
    connect: float = 15
    backoff: float = 2
    mode: str = "balanced"

    def __post_init__(self):
        if self.mode not in DOWNLOAD_MODES:
            raise ValueError("Unknown download mode")
        if not (all(math.isfinite(v) for v in (self.warning, self.timeout, self.connect, self.backoff))
                and 0 < self.warning < self.timeout and 1 <= self.attempts <= 10 and self.connect > 0 and self.backoff >= 0):
            raise ValueError("Require finite 0 < warning < timeout, 1 <= attempts <= 10 and connect > 0")


class TransferError(Exception):
    def __init__(self, message, code=None):
        super().__init__(redact(message)[:1024])
        self.reason = reason(message, code)


def measured(package, received, elapsed, interval, delta):
    package.received = received
    package.rate = max(0, delta) / interval if interval > 0 else None
    package.average = received / elapsed if elapsed > 0 else None
    package.percent = min(100, received * 100 / package.size) if package.size else None
    package.eta = max(0, package.size - received) / package.rate if package.size and package.rate else None


class CurlTransfer:
    def __call__(self, package, url, path, settings, notify):
        command = ["curl", "--fail", "--location", "--silent", "--show-error",
                   "--no-buffer",
                   "--proto", "=https,http,ftp,file", "--proto-redir", "=https,http,ftp",
                   "--connect-timeout", str(settings.connect), "--retry", "0",
                   "--output", str(path)]
        if package.size:
            command.extend(["--max-filesize", str(package.size)])
        command.extend(["--", url])
        with tempfile.TemporaryFile() as errors:
            process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=errors)
            start = last_progress = sample = time.monotonic()
            previous = 0
            try:
                while True:
                    now = time.monotonic()
                    received = path.stat().st_size if path.exists() else 0
                    measured(package, received, now - start, now - sample, received - previous)
                    if received > previous:
                        last_progress = now
                        package.warning = ""
                    elif now - last_progress >= settings.warning:
                        package.warning = f"No byte progress for {int(now - last_progress)}s"
                    notify(package)
                    previous, sample = received, now
                    code = process.poll()
                    if code is not None:
                        if code:
                            errors.seek(0)
                            raise TransferError(errors.read(16384).decode(errors="replace"), code)
                        return
                    if now - last_progress >= settings.timeout:
                        raise TransferError("Connection timeout: no byte progress")
                    try:
                        process.wait(timeout=0.25)
                    except subprocess.TimeoutExpired:
                        pass
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


class Parallelism:
    def __init__(self, mode):
        self.limit = DOWNLOAD_MODES[mode]
        self.adaptive = mode == "adaptive"
        self.healthy = 0
        self.slow = 0
        self.baseline = 0

    def reduce(self):
        if self.adaptive:
            self.limit = max(1, self.limit // 2)
            self.healthy = self.slow = self.baseline = 0

    def sample(self, rate, busy, backlog):
        if not self.adaptive:
            return
        if not backlog or busy != self.limit:
            self.healthy = self.slow = self.baseline = 0
            return
        if self.baseline and rate < self.baseline * 0.4:
            self.slow += 1
            self.healthy = 0
            if self.slow >= 3:
                self.reduce()
            return
        self.slow = 0
        if rate > 0:
            self.baseline = max(rate, self.baseline * 0.9)
            self.healthy += 1
            if self.healthy >= 3 and self.limit < 8:
                self.limit += 1
                self.healthy = self.baseline = 0


class Queue:
    def __init__(self, packages, cache, settings=None, emit=None, transfer=None):
        self.packages = packages
        self.cache = Path(cache)
        self.settings = settings or Settings()
        self.emit = emit or (lambda event: print("@@queue\t" + json.dumps(event), flush=True))
        self.transfer = transfer or CurlTransfer()
        self.stage = "DOWNLOAD"
        self.error = ""
        self.storage = {}
        self.extra_space = 0
        self.parallelism = Parallelism(self.settings.mode)
        self.events = threading.Lock()
        self.stop = threading.Event()
        self.native_errors = []
        self.outcomes = dict(download="PENDING", verification="PENDING", installation="PENDING")

    def notify(self, package=None):
        if self.stop.is_set():
            raise InterruptedError("Cancelled by user")
        with self.events:
            active = [p for p in self.packages if p.state == "DOWNLOADING"]
            self.emit({"stage": self.stage, "package": package.public() if package else None,
                       "total": len(self.packages), "completed": sum(p.checksum_verified for p in self.packages),
                       "failed": sum(p.state == "FAILED" for p in self.packages),
                       "deferred": sum(p.state in {"DEFERRED", "FAILED"} for p in self.packages),
                       "mode": self.settings.mode, "limit": self.parallelism.limit, "active": len(active),
                       "rate": sum(p.rate or 0 for p in active),
                       "error": self.error, "storage": self.storage, "native_errors": self.native_errors, **self.outcomes})

    def state(self, package, state):
        package.state = state
        self.notify(package)

    def valid(self, package, path):
        if not path.is_file() or path.is_symlink():
            return False
        if package.size is not None and path.stat().st_size != package.size:
            return False
        if not package.checksum or package.algorithm not in {"sha256", "sha512", "sha384", "sha224", "sha1", "md5"}:
            return False
        digest = hashlib.new(package.algorithm)
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest().lower() == package.checksum.lower()

    def copy_verified(self, package, source, target):
        with tempfile.TemporaryDirectory(prefix=".download-", dir=target.parent) as temp:
            part = Path(temp) / target.name
            shutil.copyfile(source, part)
            if not self.valid(package, part):
                raise TransferError(f"Checksum mismatch: {package.filename}")
            os.replace(part, target)

    def run(self):
        self.stage = "DOWNLOAD"
        self.error = ""
        self.outcomes["download"] = "RUNNING"
        self.cache.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.emit({"reset": True, "stage": self.stage, "total": len(self.packages)})
        pending = deque()
        missing = 0
        for package in self.packages:
            package.attempts = 0
            package.checksum_verified = False
            self.state(package, "CHECKING")
            path = self.cache / package.filename
            try:
                if self.valid(package, path):
                    self.complete(package, path)
                    continue
            except OSError:
                # A replacement may still be possible if only the old archive is unreadable.
                pass
            missing += package.size or 0
            pending.append(package)
            self.state(package, "QUEUED")
        free = shutil.disk_usage(self.cache).free
        temp = Path(tempfile.gettempdir())
        self.storage = {"cache": str(self.cache), "cache_free": free, "download_required": missing,
                        "cache_required": missing + self.extra_space,
                        "temporary_directory": str(temp), "temporary_free": shutil.disk_usage(temp).free,
                        "warning": "Insufficient disk space for the full queue" if missing + self.extra_space + 16 * 1024 * 1024 > free else ""}
        meminfo = Path("/proc/meminfo")
        if meminfo.is_file():
            match = re.search(r"^MemAvailable:\s+(\d+)", meminfo.read_text(), re.M)
            self.storage["memory_available"] = int(match[1]) * 1024 if match else None
        self.storage["live"] = Path("/run/archiso").exists() or Path("/run/initramfs/live").exists()
        self.notify()
        pool = ThreadPoolExecutor(max_workers=8)
        running = {}
        delayed = []
        sample_at = time.monotonic() + 1
        try:
            while pending or running or delayed:
                now = time.monotonic()
                while delayed and delayed[0][0] <= now:
                    pending.append(heapq.heappop(delayed)[2])
                if now >= sample_at:
                    active = [p for p in running.values() if p.state == "DOWNLOADING"]
                    self.parallelism.sample(sum(p.rate or 0 for p in active), len(active), bool(pending))
                    sample_at = now + 1
                    self.notify()
                while pending and len(running) < self.parallelism.limit:
                    package = pending.popleft()
                    running[pool.submit(self.download, package)] = package
                timeout = min(0.25, max(0, delayed[0][0] - now)) if delayed else 0.25
                if not running:
                    time.sleep(timeout)
                    continue
                finished, _ = wait(running, timeout=timeout, return_when=FIRST_COMPLETED)
                for future in finished:
                    package = running.pop(future)
                    if future.result():
                        self.parallelism.reduce()
                        sample_at = time.monotonic() + 1
                        self.notify()
                    if package.state == "DEFERRED":
                        heapq.heappush(delayed, (time.monotonic() + self.settings.backoff, package.filename, package))
        except KeyboardInterrupt:
            self.stage = "CANCELLED"
            self.error = "Cancelled by user"
            self.outcomes["download"] = "CANCELLED"
            self.stop.set()
            raise
        except BaseException:
            self.stop.set()
            raise
        finally:
            pool.shutdown(wait=True, cancel_futures=True)
            self.stop.clear()
            if self.stage == "CANCELLED":
                for package in self.packages:
                    if package.state not in GOOD and package.state != "FAILED":
                        package.error = self.error
                        self.state(package, "FAILED")
        success = all(p.state in GOOD for p in self.packages)
        self.outcomes["download"] = "SUCCESS" if success else "FAILED"
        self.stage = "DOWNLOAD_COMPLETED" if success else "BLOCKED"
        self.notify()
        return success

    def complete(self, package, path):
        package.received = path.stat().st_size
        package.percent = 100 if package.size else None
        package.rate = package.average = package.eta = None
        package.error = package.detail = package.warning = ""
        package.checksum_verified = True
        self.state(package, "VERIFIED")

    def download(self, package):
        path = self.cache / package.filename
        attempt = package.attempts
        package.attempts += 1
        package.received = 0
        package.rate = package.average = package.percent = package.eta = None
        package.warning = package.error = package.detail = ""
        if attempt:
            self.state(package, "RETRYING")
        try:
            if package.size and shutil.disk_usage(self.cache).free < package.size + 16 * 1024 * 1024:
                raise TransferError("Insufficient disk space")
            if not package.urls:
                raise TransferError("No mirrors available")
            url = package.urls[attempt % len(package.urls)]
            package.mirror = urlsplit(url).hostname or "local"
            with tempfile.TemporaryDirectory(prefix=".download-", dir=self.cache) as temp:
                part = Path(temp) / (package.filename + ".part")
                self.state(package, "DOWNLOADING")
                self.transfer(package, url, part, self.settings, self.notify)
                self.state(package, "DOWNLOADED")
                self.state(package, "VERIFYING")
                if not self.valid(package, part):
                    raise TransferError("Checksum mismatch")
                os.replace(part, path)
            self.complete(package, path)
            return False
        except (TransferError, OSError) as exc:
            if self.stop.is_set():
                raise
            package.error = exc.reason if isinstance(exc, TransferError) else reason(exc)
            package.detail = redact(exc)[:1024]
            package.history.append({"attempt": package.attempts, "mirror": package.mirror,
                                    "reason": package.error, "detail": package.detail})
            local_failure = package.error in {"Insufficient disk space", "Permission denied"}
            self.state(package, "FAILED" if local_failure or package.attempts >= self.settings.attempts else "DEFERRED")
            return isinstance(exc, TransferError) and not local_failure

    def report(self):
        return {"stage": self.stage, "error": self.error, "total": len(self.packages),
                "downloaded": sum(p.checksum_verified for p in self.packages),
                "failed": sum(p.state == "FAILED" for p in self.packages),
                **self.outcomes, "native_errors": self.native_errors,
                "mode": self.settings.mode,
                "packages": [p.public() for p in self.packages]}


def command(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, errors="replace",
                            env=dict(os.environ, LC_ALL="C"))
    if result.returncode:
        raise TransferError(result.stderr or result.stdout or f"Command exited {result.returncode}")
    return result.stdout


def install_command(args, queue):
    with subprocess.Popen(args, stderr=subprocess.PIPE, env=dict(os.environ, LC_ALL="C.UTF-8")) as process:
        tail = b""
        pending = b""
        diagnostics = deque(maxlen=8)
        while chunk := process.stderr.read1(4096):
            sys.stderr.buffer.write(chunk)
            sys.stderr.buffer.flush()
            tail = (tail + chunk)[-4096:]
            lines = (pending + chunk).split(b"\n")
            pending = lines.pop()[:4096]
            for line in lines:
                if re.match(rb"^error:", line, re.IGNORECASE):
                    diagnostics.append(redact(line.decode(errors="replace"))[:256])
        status = process.wait()
    if status:
        raise TransferError(tail.decode(errors="replace").strip()[-1024:] or
                            f"Native transaction exited with status {status}")
    if re.match(rb"^error:", pending, re.IGNORECASE):
        diagnostics.append(redact(pending.decode(errors="replace"))[:256])
    queue.native_errors.extend(dict.fromkeys(diagnostics))
    return status


class Pacman:
    def __init__(self, cache, work, upgrade=False, repo_options=(), parallel=4):
        self.cache = Path(cache)
        self.config = Path(work) / "pacman.conf"
        self.offline = Path(work) / "cache-only.conf"
        self.empty = Path(work) / "resolve"
        self.empty.mkdir()
        self.staged = Path(work) / "staged"
        self.staged.mkdir()
        # pacman-conf expands Include and preserves effective repository/SigLevel policy.
        content = command(["pacman-conf"])
        if "[options]" not in content:
            raise TransferError("Cannot read effective pacman options")
        content = re.sub(r"(?m)^[ \t]*(?:ParallelDownloads|XferCommand)[ \t]*=.*$", "", content)
        content = content.replace("[options]", f"[options]\nParallelDownloads = {parallel}", 1)
        self.config.write_text(content, encoding="utf-8")
        # Keep the libalpm downloader and sandbox intact. There is no network
        # source in the final configuration, even if the native solver needs more files.
        offline = re.sub(r"(?m)^[ \t]*CacheServer[ \t]*=.*$", "", content)
        offline = re.sub(r"(?m)^[ \t]*Server[ \t]*=.*$", "", offline)
        offline = re.sub(r"(?m)^\[(?!options\])[^\n]+\]$", r"\g<0>\nServer = file:///dev/null", offline)
        self.offline.write_text(offline, encoding="utf-8")
        self.upgrade = upgrade
        self.system_caches = command(["pacman-conf", "CacheDir"]).splitlines()
        self.mirrors = {}
        self.has_cache_servers = re.search(r"(?m)^[ \t]*CacheServer[ \t]*=", content) is not None

    def resolve(self, targets):
        # %s is bytes left to download, so resolve against an empty cache to
        # obtain the full archive size even when the real cache already has it.
        output = command(["pacman", "--config", str(self.config), "--cachedir", str(self.empty),
                          "-Spu" if self.upgrade else "-Sp", "--needed", "--print-format",
                          "SPQ:%n\t%v\t%r\t%s\t%f\t%h\t%l\t%g", "--", *targets])
        packages = []
        for line in output.splitlines():
            if not line.startswith("SPQ:"):
                continue
            name, version, repo, size, filename, checksum, url, signature = line[4:].split("\t")
            if repo not in self.mirrors:
                config_args = ["pacman-conf", "--config", str(self.config), "--repo", repo]
                cache_servers = command([*config_args, "CacheServer"]).splitlines() if self.has_cache_servers else []
                self.mirrors[repo] = cache_servers, command([*config_args, "Server"]).splitlines()
            cache_servers, mirrors = self.mirrors[repo]
            urls = [server.rstrip("/") + "/" + filename for server in cache_servers]
            urls.append(url)
            urls.extend(server.rstrip("/") + "/" + filename for server in mirrors)
            urls = list(dict.fromkeys(urls))
            packages.append(Package(name, version, repo, int(size) if size.isdigit() else None,
                                    filename, checksum, urls, signature=signature))
        return packages

    def seed(self, queue):
        for package in queue.packages:
            target = queue.cache / package.filename
            if queue.valid(package, target):
                continue
            for cache in self.system_caches:
                source = Path(cache) / package.filename
                if queue.valid(package, source):
                    queue.copy_verified(package, source, target)
                    break

    def stage_signature(self, queue, package):
        path = self.cache / (package.filename + ".sig")
        with tempfile.TemporaryDirectory(prefix=".signature-", dir=self.cache) as temp:
            part = Path(temp) / path.name
            if package.signature and package.signature != "(null)":
                part.write_bytes(base64.b64decode(package.signature, validate=True))
            elif path.is_file() and not path.is_symlink():
                return  # libalpm verifies the cached detached signature
            else:
                for cache in self.system_caches:
                    source = Path(cache) / path.name
                    if source.is_file():
                        shutil.copyfile(source, part)
                        break
                else:
                    # A repository without embedded signatures may publish sidecars.
                    # The native transaction enforces that repository's signature policy.
                    for url in package.urls[:queue.settings.attempts]:
                        parsed = urlsplit(url)
                        url = parsed._replace(path=parsed.path + ".sig").geturl()
                        result = subprocess.run(
                            ["curl", "--fail", "--silent", "--location", "--proto", "=https,http,ftp,file",
                             "--proto-redir", "=https,http,ftp", "--max-filesize", "16384",
                             "--connect-timeout", str(queue.settings.connect), "--max-time",
                             str(queue.settings.timeout), "--output", str(part), "--", url],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        if not result.returncode:
                            break
                    else:
                        return
            os.replace(part, path)

    def native(self, queue, targets, download_only):
        # libalpm creates its sandbox download directory under the first CacheDir.
        # Use an accessible, per-operation scratch directory, then read the private
        # archive cache as root. No archive is copied into the scratch directory.
        operation = "-Su" if self.upgrade else "-S"
        flags = [operation + "w", "--noconfirm"] if download_only else [operation]
        scratch = Path(tempfile.mkdtemp(prefix="serpantinum-alpm-", dir="/var/tmp"))
        try:
            scratch.chmod(0o711)
            args = ["sudo", "pacman", "--config", str(self.offline), "--cachedir", str(scratch),
                    "--cachedir", str(self.staged), *flags, "--needed", "--", *targets]
            return command(args) if download_only else install_command(args, queue)
        finally:
            # libalpm 16 may leave an empty 0700 directory owned by DownloadUser.
            # rmdir needs access to its parent only. Recursive cleanup tries to
            # list/chmod it and can replace the real transaction result with EPERM.
            try:
                for directory in scratch.glob("download-*"):
                    directory.rmdir()
                scratch.rmdir()
            except OSError as exc:
                print(f"Could not remove libalpm scratch directory {scratch}: {exc}", file=sys.stderr)

    def verify(self, queue, targets):
        for package in queue.packages:
            archive = self.cache / package.filename
            (self.staged / archive.name).symlink_to(archive)
            self.stage_signature(queue, package)
            signature = self.cache / (package.filename + ".sig")
            if signature.is_file() and not signature.is_symlink():
                (self.staged / signature.name).symlink_to(signature)
        self.native(queue, targets, download_only=True)

    def install(self, queue, targets):
        return self.native(queue, targets, download_only=False)


class Dnf:
    """Use the host's matching DNF solver; curl consumes its repository metadata."""
    def __init__(self, cache, work, upgrade=False, repo_options=()):
        self.cache = Path(cache)
        self.repo_options = list(repo_options)
        self.disabled = [s.split("=", 1)[1] for s in repo_options if s.startswith("--disablerepo=")]
        self.api = None
        self.native_paths = {}
        self.operation = "install"
        self.metadata = self.cache / ("metadata5" if shutil.which("dnf5") else "metadata4")

    def resolve(self, targets):
        if shutil.which("dnf5"):
            return self.resolve5(targets)
        return self.resolve4(targets)

    def resolve5(self, targets):
        try:
            import libdnf5
            import libdnf5.base
            import libdnf5.repo
            import libdnf5.rpm
        except ImportError as exc:
            raise TransferError("DNF5 Python API unavailable; install python3-libdnf5 with the native package manager and retry") from exc
        import fnmatch
        self.api = base = libdnf5.base.Base()
        base.load_config()
        config = base.get_config()
        config.cachedir = str(self.metadata)
        config.max_parallel_downloads = 1
        config.timeout = 15
        config.retries = 1
        base.setup()
        sack = base.get_repo_sack()
        sack.create_repos_from_system_configuration()
        for repo in libdnf5.repo.RepoQuery(base):
            if any(fnmatch.fnmatch(repo.get_id(), pattern) for pattern in self.disabled):
                repo.disable()
        sack.update_and_load_enabled_repos(True)
        goal = libdnf5.base.Goal(base)
        for target in targets:
            (goal.add_rpm_upgrade if self.operation == "upgrade" else goal.add_rpm_install)(target)
        transaction = goal.resolve()
        if transaction.get_problems():
            raise TransferError("Dependency conflict: " + str(transaction.get_resolve_logs_as_strings()))
        packages = []
        for item in transaction.get_transaction_packages():
            pkg = item.get_package()
            if pkg.get_repo_id() == "@System":
                continue
            checksum = pkg.get_checksum()
            self.native_paths[Path(pkg.get_location()).name] = Path(pkg.get_package_path())
            packages.append(Package(pkg.get_name(), pkg.get_evr(), pkg.get_repo_id(), pkg.get_download_size(),
                                    Path(pkg.get_location()).name, checksum.get_checksum(),
                                    list(pkg.get_remote_locations()), checksum.get_type_str().lower()))
        return packages

    def resolve4(self, targets):
        try:
            import dnf
            import hawkey
        except ImportError as exc:
            raise TransferError("DNF Python API unavailable; install python3-dnf with the native package manager and retry") from exc
        self.api = base = dnf.Base()
        base.conf.read()
        base.conf.cachedir = str(self.metadata)
        base.conf.max_parallel_downloads = 1
        base.conf.timeout = 15
        base.conf.retries = 1
        base.read_all_repos()
        for pattern in self.disabled:
            for repo in base.repos.get_matching(pattern):
                repo.disable()
        base.fill_sack(load_system_repo=True)
        for target in targets:
            if self.operation == "upgrade":
                base.upgrade(target)
            else:
                base.install(target, strict=True)
        base.resolve()
        packages = []
        for pkg in base.transaction.install_set:
            algorithm, digest = pkg.chksum
            self.native_paths[Path(pkg.location).name] = Path(pkg.localPkg())
            urls = [pkg.remote_location()]
            urls += [s.rstrip("/") + "/" + pkg.location for s in pkg.repo.baseurl]
            packages.append(Package(pkg.name, pkg.evr, pkg.reponame, pkg.downloadsize,
                                    Path(pkg.location).name, bytes(digest).hex(), list(dict.fromkeys(urls)),
                                    hawkey.chksum_name(algorithm)))
        return packages

    def seed(self, queue):
        # DNF's own caches are searched without modifying them. Every candidate is hashed.
        queue.extra_space = sum(p.size or 0 for p in queue.packages
                                if p.filename in self.native_paths and not queue.valid(p, self.native_paths[p.filename]))
        roots = [Path("/var/cache/libdnf5"), Path("/var/cache/dnf"), self.cache]
        for pkg in queue.packages:
            target = self.cache / pkg.filename
            if queue.valid(pkg, target):
                continue
            for root in roots:
                match = next((p for p in root.glob("**/" + pkg.filename) if queue.valid(pkg, p)), None)
                if match:
                    queue.copy_verified(pkg, match, target)
                    break

    def verify(self, queue, targets):
        for pkg in queue.packages:
            # rpm checks both embedded digests and signatures against the system keyring.
            output = command(["rpmkeys", "--checksig", str(queue.cache / pkg.filename)])
            if "signatures OK" not in output:
                raise TransferError(f"Invalid package signature: {pkg.name}; {output}")

    def install(self, queue, targets):
        # Feed the host's native cache layout, then execute the original targets.
        # This preserves install reasons, repository GPG policy and native solving.
        # cacheonly forbids fetching an additional dependency after the queue.
        for pkg in queue.packages:
            target = self.native_paths[pkg.filename]
            if queue.valid(pkg, target):
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            queue.copy_verified(pkg, queue.cache / pkg.filename, target)
        return install_command(["sudo", "dnf", *self.repo_options, "--cacheonly",
                                "--setopt=cachedir=" + str(self.metadata), "--setopt=keepcache=True",
                                "--setopt=max_parallel_downloads=1", self.operation, *targets], queue)


def identity(packages):
    return sorted((p.name, p.version, p.repository, p.filename, p.checksum, p.signature) for p in packages)


def run_transaction(backend, queue, targets):
    queue.emit({"reset": True, "stage": "CHECKING", "total": len(queue.packages)})
    for pkg in queue.packages:
        queue.state(pkg, "CHECKING")
    try:
        backend.seed(queue)
    except (OSError, TransferError) as exc:
        # Cache import is an optimization. Per-package downloads perform their own
        # permission/space checks and continue to report the remaining queue.
        queue.error = redact(exc)[:1024]
    if not queue.run():
        return 1
    queue.stage = "VERIFYING"
    queue.outcomes["verification"] = "RUNNING"
    queue.notify()
    try:
        if identity(backend.resolve(targets)) != identity(queue.packages):
            raise TransferError("Dependency conflict: package metadata or installed system changed; review the transaction again")
        if queue.packages:
            backend.verify(queue, targets)
        queue.outcomes["verification"] = "SUCCESS"
    except Exception as exc:
        queue.error = redact(exc)[:2048]
        queue.outcomes["verification"] = "FAILED"
        queue.stage = "BLOCKED"
        for pkg in queue.packages:
            if pkg.filename in str(exc) or re.search(rf"(?<![\w.+-]){re.escape(pkg.name)}(?![\w.+-])", str(exc)):
                pkg.error = reason(exc)
                pkg.detail = redact(exc)
                queue.state(pkg, "FAILED")
        queue.notify()
        return 1
    queue.stage = "READY"
    queue.notify()
    queue.stage = "INSTALLING"
    queue.outcomes["installation"] = "RUNNING"
    for package in queue.packages:
        queue.state(package, "INSTALLING")
    queue.notify()
    try:
        code = backend.install(queue, targets) if queue.packages else 0
    except (TransferError, OSError) as exc:
        code = 1
        queue.error = str(exc)
    if code:
        queue.outcomes["installation"] = "FAILED"
    else:
        queue.outcomes["installation"] = "SUCCESS_WITH_WARNINGS" if queue.native_errors else "SUCCESS"
    queue.stage = "INSTALLED" if code == 0 else "BLOCKED"
    if code:
        queue.error = queue.error or "Native transaction failed or was declined; review the package manager journal."
        for package in queue.packages:
            queue.state(package, "VERIFIED")
    else:
        for pkg in queue.packages:
            queue.state(pkg, "INSTALLED")
    queue.notify()
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backend", choices=["pacman", "dnf"])
    parser.add_argument("--upgrade", action="store_true")
    parser.add_argument("--operation", choices=["install", "upgrade"], default="install")
    parser.add_argument("--repo-option", action="append", default=[])
    parser.add_argument("--download-mode", choices=DOWNLOAD_MODES,
                        default=os.getenv("SERP_DOWNLOAD_MODE", "balanced"))
    parser.add_argument("--attempts", type=int, default=int(os.getenv("SERP_DOWNLOAD_ATTEMPTS", "3")))
    parser.add_argument("--warning", type=float, default=float(os.getenv("SERP_DOWNLOAD_WARNING", "30")))
    parser.add_argument("--timeout", type=float, default=float(os.getenv("SERP_DOWNLOAD_TIMEOUT", "60")))
    parser.add_argument("targets", nargs="*")
    args = parser.parse_intermixed_args()
    settings = Settings(args.warning, args.timeout, args.attempts, mode=args.download_mode)
    cache = Path(os.getenv("XDG_CACHE_HOME") or Path.home() / ".cache").resolve() / "serpantinum-installer/packages" / args.backend
    queue = Queue([], cache, settings)
    queue.emit({"reset": True, "stage": "RESOLVING", "total": 0})
    try:
        import fcntl
        cache.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (cache / ".lock").open("a") as lock, tempfile.TemporaryDirectory(prefix="serpantinum-pm-") as work:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise TransferError("Another Serpantinum package operation is using this cache") from exc
            for pattern in (".download-*", ".signature-*"):
                for orphan in cache.glob(pattern):
                    if orphan.is_dir() and not orphan.is_symlink():
                        shutil.rmtree(orphan)

            if args.backend == "pacman":
                backend = Pacman(cache, work, args.upgrade, parallel=DOWNLOAD_MODES[settings.mode])
            else:
                backend = Dnf(cache, work, repo_options=args.repo_option)
                backend.operation = args.operation
            if args.upgrade:
                # Only reached from the user's explicit full-upgrade option. Refresh
                # then resolve/install ALL upgrades, never a per-target partial upgrade.
                if args.backend != "pacman":
                    raise ValueError("Full upgrade option is pacman-only")
                if subprocess.call(["sudo", "pacman", "--config", str(backend.config), "-Sy"]):
                    raise TransferError("Repository metadata refresh failed")
            queue.packages = backend.resolve(args.targets)
            for pkg in queue.packages:
                if not pkg.filename or Path(pkg.filename).name != pkg.filename or pkg.filename in {".", ".."}:
                    raise ValueError("Unsafe repository filename")
            if len({p.filename for p in queue.packages}) != len(queue.packages):
                raise TransferError("Repository archive filenames collide in the transaction cache")
            return run_transaction(backend, queue, args.targets)
    except KeyboardInterrupt:
        queue.stage, queue.error = "CANCELLED", "Cancelled by user"
        for phase, status in queue.outcomes.items():
            if status == "RUNNING":
                queue.outcomes[phase] = "CANCELLED"
        return 130
    except Exception as exc:
        queue.stage, queue.error = "BLOCKED", redact(exc)[:2048]
        for phase, status in queue.outcomes.items():
            if status == "RUNNING":
                queue.outcomes[phase] = "FAILED"
        return 1
    finally:
        queue.notify()
        report = queue.report()
        report.pop("packages")  # packages were streamed individually; keep PTY frames bounded
        print("@@report\t" + json.dumps(report), flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
