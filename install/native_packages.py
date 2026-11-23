#!/usr/bin/env python3
"""Run the distribution's interactive desktop-package transaction."""

import argparse
from collections import deque
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

from download_queue import DOWNLOAD_MODES, TransferError, command, install_command, redact


NETWORK = re.compile(r"failed to download|failed to retrieve|curl error|HTTP (?:error )?[45]\d\d|"
                     r"timeout|timed out|TLS|SSL_ERROR|external downloader|no mirrors", re.I)
TRUST = re.compile(r"signature|NOKEY|NOTTRUSTED|(?:GPG|OpenPGP) (?:key|check)|keyring|"
                   r"digest|checksum|corrupt(?:ed)? package", re.I)


def native_command(args, work, parallel):
    if args.backend == "dnf":
        # Preserve the repository's metadata policy and enforce RPM signatures
        # on both repository and local packages. DNF handles key enrollment.
        gpg = "pkg_gpgcheck" if shutil.which("dnf5") else "gpgcheck"
        options = ["--setopt=assumeyes=False", "--setopt=keepcache=True",
                   f"--setopt={gpg}=True", f"--setopt=*.{gpg}=True", "--setopt=localpkg_gpgcheck=True",
                   "--setopt=install_weak_deps=False", f"--setopt=max_parallel_downloads={parallel}"]
        if gpg == "pkg_gpgcheck":
            options.append(f"--setopt=max_downloads_per_mirror={parallel}")
        return ["sudo", "dnf", *args.repo_option, *options, *(["--refresh"] if args.refresh else []),
                args.operation, "--", *args.targets]

    config = Path(work) / "pacman.conf"
    content = command(["pacman-conf"])
    if "[options]" not in content:
        raise TransferError("Cannot read effective pacman options")
    # Preserve libalpm's sandbox, signature policy, mirrors and cache.
    # Use libalpm's downloader for this transaction.
    content = re.sub(r"(?m)^[ \t]*(?:ParallelDownloads|XferCommand)[ \t]*=.*$", "", content)
    options = f"[options]\nParallelDownloads = {parallel}"
    if not re.search(r"(?m)^CheckSpace[ \t]*$", content):
        options += "\nCheckSpace"
    config.write_text(content.replace("[options]", options, 1), encoding="utf-8")
    caches = command(["pacman-conf", "CacheDir"]).splitlines()
    old = cache_root() / "pacman"
    if caches and old.is_dir():
        caches.append(str(old))
    cache_options = [arg for cache in caches for arg in ("--cachedir", cache)]
    return ["sudo", "pacman", "--config", str(config), *cache_options,
            "-Syu" if args.upgrade else "-S", "--needed", "--", *args.targets]


def cache_root():
    return Path(os.getenv("XDG_CACHE_HOME") or Path.home() / ".cache") / "serpantinum-installer/packages"


def profile(backend, mode):
    path = cache_root() / f"{backend}-native-parallelism"
    parallel = DOWNLOAD_MODES[mode]
    if mode == "adaptive":
        try:
            parallel = max(1, min(8, int(path.read_text())))
        except (OSError, ValueError):
            pass
    return parallel, path


def update_profile(path, parallel, success, network_failure):
    adjusted = min(8, parallel + 1) if success else max(1, parallel // 2) if network_failure else parallel
    try:
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            try:
                stream.write(str(adjusted))
                stream.close()
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)
    except OSError:
        pass  # Native caches and transactions do not depend on this preference.


def emit(kind, report):
    print(f"@@{kind}\t" + json.dumps(report), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("backend", choices=["pacman", "dnf"])
    parser.add_argument("--upgrade", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--operation", choices=["install", "upgrade"], default="install")
    parser.add_argument("--repo-option", action="append", default=[])
    parser.add_argument("--download-mode", choices=DOWNLOAD_MODES, default=os.getenv("SERP_DOWNLOAD_MODE", "balanced"))
    parser.add_argument("targets", nargs="*")
    args = parser.parse_intermixed_args()
    if any(not re.fullmatch(r"--disablerepo=[\w.*?+:-]+", item) for item in args.repo_option):
        parser.error("only repository exclusions are supported")
    parallel, preference = profile(args.backend, args.download_mode)
    transaction = argparse.Namespace(native_errors=[])
    report = dict(native=True, backend=args.backend, mode=args.download_mode, limit=parallel,
                  stage="NATIVE", download="NATIVE", verification="NATIVE", installation="RUNNING",
                  total=None, downloaded=None, native_errors=transaction.native_errors,
                  targets=args.targets, native_cache=("/var/cache/libdnf5 or /var/cache/dnf"
                                                     if args.backend == "dnf" else "pacman CacheDir"))
    emit("queue", dict(report, reset=True))
    status = 1
    try:
        with tempfile.TemporaryDirectory(prefix="serpantinum-native-") as work:
            status = install_command(native_command(args, work, parallel), transaction)
        report["stage"] = "INSTALLED"
        report["installation"] = "SUCCESS_WITH_WARNINGS" if transaction.native_errors else "SUCCESS"
    except KeyboardInterrupt:
        status = 130
        report.update(stage="CANCELLED", installation="CANCELLED")
    except (TransferError, OSError) as exc:
        detail = redact(exc)
        report.update(stage="BLOCKED", installation="FAILED", error=detail)
        if TRUST.search(detail):
            report["verification"] = "FAILED"
        elif NETWORK.search(detail):
            report["download"] = "FAILED"
        print(detail, flush=True)
    finally:
        if args.download_mode == "adaptive" and status != 130:
            update_profile(preference, parallel, status == 0, report["download"] == "FAILED")
        emit("queue", report)
        emit("report", report)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
