#!/usr/bin/env python3
"""Read-only system upgrade planning and reviewed package-manager transactions."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

from download_queue import (
    DOWNLOAD_MODES, Pacman, Queue, Settings, TransferError, identity, install_command,
    reason, redact, run_transaction,
)


MIB = 1024 ** 2
SIZE = re.compile(r"([\d.]+)\s*([KMGT]?)(?:i?B)?\b", re.I)
ENV = dict(os.environ, LC_ALL="C", COLUMNS="300", NO_COLOR="1")


def capture(args, *, allowed=(0,), timeout=120, env=ENV):
    result = subprocess.run(args, env=env, stdin=subprocess.DEVNULL, capture_output=True,
                            text=True, errors="replace", timeout=timeout)
    if result.returncode not in allowed:
        raise TransferError(redact(result.stderr.strip() or result.stdout.strip() or
                                   f"{args[0]} exited with status {result.returncode}"))
    return result


def output(*args):
    return capture(args).stdout.strip()


def release():
    info = {}
    for line in Path("/etc/os-release").read_text().splitlines():
        key, sep, value = line.partition("=")
        if sep and re.fullmatch(r"[A-Z_]+", key):
            fields = shlex.split(value)
            info[key] = " ".join(fields)
    return info


def live_session():
    cmdline = Path("/proc/cmdline").read_text()
    return (any(Path(path).is_dir() for path in ("/run/archiso", "/run/initramfs/live", "/run/live/medium",
                                                 "/run/miso", "/run/ventoy")) or
            bool(re.search(r"(?:^| )(?:rd\.live\.image(?:=\S*)?(?=\s|$)|root=live:|archisobasedir=|"
                           r"archisolabel=|misobasedir=|cow_spacesize=|boot=live)", cmdline)) or
            output("findmnt", "-n", "-o", "FSTYPE", "--target", "/") == "overlay")


def reboot_status(pm):
    if any(Path(name).is_file() for name in ("/run/reboot-required", "/run/needs-reboot")):
        return "required"
    if pm == "dnf":
        args = ["dnf", "needs-restarting", "-r"]
        result = capture(args, allowed=(0, 1, 2), timeout=20)
        if result.returncode == 1 and "reboot is required" in result.stdout.lower():
            return "required"
        if result.returncode == 0:
            return "clear"
    if pm in {"pacman", "void"}:
        modules = Path("/usr/lib/modules")
        if (modules / os.uname().release / "modules.dep").is_file():
            return "kernel_present"
        if any(modules.glob("*/modules.dep")):
            return "kernel_changed"
    return "unknown"


def configured_reboot(pm):
    try:
        return reboot_status(pm)
    except (OSError, TransferError, subprocess.TimeoutExpired):
        return "unknown"


def additional(pm):
    actions = {}
    if pm == "pacman":
        helper = next((tool for tool in ("paru", "yay") if shutil.which(tool)), None)
        if helper:
            actions["aur"] = [helper, "-Sua"]
    if shutil.which("flatpak"):
        for scope in ("user", "system"):
            actions[f"flatpak-{scope}"] = ["flatpak", "update", f"--{scope}"]
    return actions


def snapshot_config():
    if not shutil.which("snapper") or output("findmnt", "-n", "-o", "FSTYPE", "--target", "/") != "btrfs":
        return None
    configs = capture(["snapper", "list-configs"], allowed=(0, 1), timeout=10)
    match = re.search(r"^\s*([\w.-]+)\s*\|\s*/[ \t]*$", configs.stdout, re.M)
    if match:
        return match[1]
    if Path("/etc/snapper/configs/root").is_file() and Path("/.snapshots").is_dir():
        return "root"
    return None


def nearest(path):
    path = Path(path).resolve()
    while not path.exists():
        path = path.parent
    return path


def disk_rows(cache, download=0, install=0, kernel=False, metadata=0):
    volumes = {}
    for path, required in ((cache, download + 32 * MIB), ("/usr", install + 128 * MIB),
                           ("/var", 32 * MIB + metadata)):
        location = nearest(path)
        device = location.stat().st_dev
        row = volumes.setdefault(device, dict(paths=[], free=shutil.disk_usage(location).free, required=0))
        if str(path) not in row["paths"]:
            row["paths"].append(str(path))
        row["required"] += required
    if kernel:
        for path in ("/boot", "/efi", "/boot/efi"):
            if Path(path).is_mount():
                device = Path(path).stat().st_dev
                if device not in volumes:
                    volumes[device] = dict(paths=[path], free=shutil.disk_usage(path).free, required=64 * MIB)
    return list(volumes.values())


def ensure_space(rows):
    for row in rows:
        if row["required"] > row["free"]:
            raise TransferError(f"Insufficient disk space on {', '.join(row['paths'])}")


def pacman_db():
    return Path(output("pacman-conf", "DBPath"))


def pacman_versions():
    return dict(line.split(maxsplit=1) for line in output("pacman", "-Q").splitlines())


def lock_check(db):
    if (db / "db.lck").exists():
        raise TransferError(f"Package manager database is locked at {db / 'db.lck'}. "
                            "Wait for the owning process to finish; leave the lock in place.")


def refresh_pacman(db, temporary, repositories):
    sync = temporary / "sync"
    check = shutil.which("checkupdates") and shutil.which("fakeroot")
    failures = []
    if check:
        tool_db = temporary.with_name("checkupdates")
        try:
            result = capture(["checkupdates", "--nocolor"], allowed=(0, 1, 2), timeout=90,
                             env=dict(ENV, CHECKUPDATES_DB=str(tool_db)))
            if result.returncode in {0, 2} and all((tool_db / "sync" / f"{repo}.db").is_file()
                                                   for repo in repositories):
                tool_db.rename(temporary)
                return failures
            failures.append(redact(result.stderr.strip()) or "checkupdates did not refresh every repository.")
        except (TransferError, subprocess.TimeoutExpired) as exc:
            failures.append(redact(exc))
    temporary.mkdir(exist_ok=True)
    if not (temporary / "local").is_symlink():
        (temporary / "local").symlink_to(db / "local", target_is_directory=True)
    sync.mkdir(exist_ok=True)
    for repo in repositories:
        repo_args = ["pacman-conf", "--repo", repo]
        usage = output(*repo_args, "Usage").split()
        if usage and not {"All", "Sync"}.intersection(usage):
            for suffix in (".db", ".db.sig"):
                source = db / "sync" / (repo + suffix)
                if source.is_file():
                    shutil.copyfile(source, sync / source.name)
            if not (sync / f"{repo}.db").is_file():
                raise TransferError(f"{repo} has Sync disabled and no local repository database")
            continue
        destination = sync / f"{repo}.db"
        signature = destination.with_suffix(".db.sig")
        for mirror in output(*repo_args, "Server").splitlines()[:5]:
            parsed = urlsplit(mirror.rstrip("/") + f"/{repo}.db")
            url = parsed.geturl()
            args = ["curl", "-q", "--fail", "--silent", "--show-error", "--location", "--proto",
                    "=https,http,ftp,file", "--proto-redir", "=https,http,ftp",
                    "--connect-timeout", "6", "--max-time", "20"]
            result = subprocess.run([*args, "--max-filesize", str(256 * MIB), "--output",
                                     str(destination), "--", url], env=ENV, capture_output=True, text=True)
            if result.returncode == 0:
                signature.unlink(missing_ok=True)
                detached = parsed._replace(path=parsed.path + ".sig").geturl()
                signed = subprocess.run([*args, "--max-filesize", "65536", "--output", str(signature),
                                         "--", detached], env=ENV, capture_output=True, text=True)
                if signed.returncode == 0 or "404" in signed.stderr or signed.returncode == 37:
                    break
                result = signed
            failures.append(f"{repo} · {parsed.hostname or 'local'} · {reason(result.stderr, result.returncode)}")
            destination.unlink(missing_ok=True)
            signature.unlink(missing_ok=True)
        else:
            raise TransferError(f"Repository {repo} could not be refreshed. " + "; ".join(failures[-12:]))
    return failures


def size_value(value):
    match = SIZE.search(value)
    if not match:
        return None
    exponent = {"": 0, "K": 1, "M": 2, "G": 3, "T": 4}[match[2].upper()]
    return round(float(match[1]) * 1024 ** exponent)


def pacman_sizes(backend, packages, versions):
    if not packages:
        return 0, 0
    targets = [f"{pkg.repository}/{pkg.name}" for pkg in packages]
    info = output("pacman", "--config", str(backend.config), *backend.db_args, "-Si", "--", *targets)
    sizes = re.findall(r"^Installed Size\s*:\s*(.+)$", info, re.M)
    parsed = [size_value(row) for row in sizes]
    if len(parsed) != len(packages) or any(size is None for size in parsed):
        raise TransferError("Pacman could not estimate the installed size of the full transaction")
    installed = Path(backend.db_args[1]) / "local"
    previous = 0
    for pkg in packages:
        if pkg.name in versions:
            desc = (installed / f"{pkg.name}-{versions[pkg.name]}" / "desc").read_text()
            match = re.search(r"^%SIZE%\n(\d+)", desc, re.M)
            if match:
                previous += int(match[1])
    return sum(parsed), sum(parsed) - previous


def cache_path(pm):
    return Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache").resolve() / "serpantinum-installer/packages" / pm


def cache_requirements(backend, packages):
    queue = Queue(packages, backend.cache, Settings())
    required = download = 0
    for package in packages:
        if queue.valid(package, backend.cache / package.filename):
            continue
        required += package.size
        try:
            if any(queue.valid(package, Path(cache) / package.filename) for cache in backend.system_caches):
                continue
        except OSError:
            pass  # An unreadable system cache is only an optional seed.
        download += package.size
    return required, download


def pacman_plan(backend, db, versions):
    packages = backend.resolve([])
    if any(p.size is None or not re.fullmatch(r"[0-9a-fA-F]{64}", p.checksum) or
           p.filename in {"", ".", ".."} or Path(p.filename).name != p.filename for p in packages):
        raise TransferError("Pacman returned incomplete or unsafe archive metadata")
    if len({p.filename for p in packages}) != len(packages):
        raise TransferError("Repository archive filenames collide in the transaction cache")
    unpack, change = pacman_sizes(backend, packages, versions)
    cache_required, pending = cache_requirements(backend, packages)
    metadata_size = sum(f.stat().st_size for f in (db / "sync").glob("*.db*"))
    storage = disk_rows(backend.cache, cache_required, unpack,
                        any(p.name.startswith(("linux", "kernel")) for p in packages), metadata_size * 2)
    rows = [dict(name=p.name, old=versions.get(p.name), version=p.version, repo=p.repository, size=p.size)
            for p in packages]
    return packages, dict(packages=rows, download=pending, archive=sum(p.size for p in packages),
                          change=change, disks=storage)


def pacman_fingerprint(packages, versions, config):
    encoded = json.dumps([identity(packages), versions, config], sort_keys=True).encode()
    return hashlib.sha256(encoded).hexdigest()


def check_pacman(work):
    db = pacman_db()
    temporary = work / "database"
    repositories = output("pacman-conf", "--repo-list").splitlines()
    if not repositories or not all(re.fullmatch(r"[\w.+-]+", repo, re.ASCII) for repo in repositories):
        raise TransferError("No valid pacman repositories are configured")
    ensure_space(disk_rows(work))
    failures = refresh_pacman(db, temporary, repositories)
    with tempfile.TemporaryDirectory(dir=work) as config_work:
        backend = Pacman(cache_path("pacman"), config_work, upgrade=True, dbpath=temporary)
        # libalpm opens every repository database here, enforcing the native DB policy.
        listed = capture(["pacman", "--config", str(backend.config), *backend.db_args, "-Sl"])
        if re.search(r"^error:", listed.stderr, re.M):
            raise TransferError(listed.stderr)
        versions = pacman_versions()
        packages, plan = pacman_plan(backend, temporary, versions)
        plan.update(repos=repositories, mirrors=failures,
                    fingerprint=pacman_fingerprint(packages, versions, output("pacman-conf")))
        return plan


class SystemPacman(Pacman):
    def __init__(self, cache, work, dbpath, system_db, plan, versions):
        super().__init__(cache, work, upgrade=True, dbpath=dbpath)
        self.metadata = dbpath / "sync"
        self.system_db = system_db
        self.plan = plan
        self.versions = versions

    def install(self, queue, targets):
        lock_check(self.system_db)
        ensure_space(pacman_plan(self, self.metadata.parent, self.versions)[1]["disks"])
        if pacman_fingerprint(self.resolve([]), pacman_versions(), output("pacman-conf")) != self.plan["fingerprint"]:
            raise TransferError("Installed packages or repository configuration changed; check updates again")
        # Pacman owns the system DB lock, metadata refresh, signatures, dependency
        # resolution and commit in a single native -Syu invocation. Only the
        # reviewed metadata and the verified archive cache are reachable.
        with tempfile.TemporaryDirectory(prefix="serpantinum-repos-", dir="/var/tmp") as folder:
            mirror = Path(folder)
            mirror.chmod(0o755)
            for source in self.metadata.iterdir():
                if source.is_file():
                    shutil.copyfile(source, mirror / source.name)
                    (mirror / source.name).chmod(0o644)
            content = self.config.read_text()
            content = re.sub(r"(?m)^[ \t]*(?:Server|CacheServer)[ \t]*=.*\n?", "", content)
            if not re.search(r"(?m)^CheckSpace\s*$", content):
                content = content.replace("[options]", "[options]\nCheckSpace", 1)
            content = re.sub(r"(?m)^\[(?!options\])[^\n]+\]$",
                             lambda match: f"{match[0]}\nServer = {mirror.as_uri()}", content)
            config = self.config.with_name("system-upgrade.conf")
            config.write_text(content)
            args = ["sudo", "pacman", "--config", str(config), "--cachedir", str(mirror),
                    "--cachedir", str(self.staged), "-Syyu"]
            try:
                install_command(args, queue)
            finally:
                # libalpm's download sandbox may leave an empty directory
                # owned by DownloadUser, even when every archive was cached.
                for directory in mirror.glob("download-*"):
                    try:
                        directory.rmdir()
                    except OSError as exc:
                        print(f"Could not remove {directory}: {exc}", file=sys.stderr)
            installed = pacman_versions()
            missing = [p.name for p in queue.packages if installed.get(p.name) != p.version]
            if missing:
                raise TransferError("The reviewed transaction was declined or could not be verified: " +
                                    ", ".join(missing[:20]))
        return 0


def dnf_flags(work, mode):
    return ["--setopt=timeout=12", "--setopt=retries=2", "--setopt=*.skip_if_unavailable=False",
            f"--setopt=cachedir={work / 'dnf-cache'}",
            f"--setopt=max_parallel_downloads={DOWNLOAD_MODES[mode]}"]


def check_dnf(work, mode):
    flags = dnf_flags(work, mode)
    result = capture(["dnf", *flags, "--refresh", "--assumeno", "upgrade"], allowed=(0, 1, 100))
    source = result.stdout + "\n" + result.stderr
    report = redact(source.strip())
    summary = re.search(r"(?m)^Transaction Summary\b", source)
    if re.search(r"(?im)^(?:error:|failed to (?:download|load))", source):
        raise TransferError(report)
    if summary:
        packages = []
        action = ""
        for line in source[:summary.start()].splitlines():
            if re.match(r"^\S.*:\s*$", line):
                action = line.rstrip(":").strip()
            fields = line.split()
            if len(fields) >= 5 and fields[1] in {
                "x86_64", "noarch", "i686", "aarch64", "ppc64le", "s390x", "riscv64", "armv7hl"
            }:
                packages.append(dict(name=fields[0], arch=fields[1], version=fields[2],
                                     repo=fields[3], action=action))
        if not packages:
            raise TransferError("DNF returned an unreadable transaction summary")
        size = re.search(r"(?im)(?:^Total download size|Need to download)\s*:?\s*(.+)$", source)
        change = re.search(r"(?im)^After this operation, ([\d.]+\s*[KMGT]?i?B)(?: extra)? will be (used|freed)", source)
        installed = re.search(r"(?im)\(install ([\d.]+\s*[KMGT]?i?B)", source)
        download = size_value(size[1]) if size else None
        net = size_value(change[1]) * (-1 if change[2] == "freed" else 1) if change else None
        unpack = size_value(installed[1]) if installed else max(net or 0, download or 0)
    elif result.returncode == 0 and re.search(r"Nothing to do|No packages marked for upgrade", source, re.I):
        packages, download, net, unpack = [], 0, 0, 0
    else:
        raise TransferError(report or f"DNF exited with status {result.returncode}")
    security = None
    try:
        security_result = capture(["dnf", *flags, "-C", "check-update", "--security"], allowed=(0, 100), timeout=30)
        security = security_result.returncode == 100
    except (TransferError, subprocess.TimeoutExpired):
        pass
    mirrors = [redact(line[4:]) for line in source.splitlines() if line.startswith(">>> Curl error")]
    return dict(packages=packages, download=download, change=net, native=report, security=security, mirrors=mirrors,
                disks=disk_rows("/var/cache/libdnf5" if shutil.which("dnf5") else "/var/cache/dnf",
                                download or 0, unpack or 0, any(p["name"].startswith("kernel") for p in packages)))


def check_void():
    result = capture(["xbps-install", "-Mun"])
    if re.search(r"(?im)^(?:error:|failed to)", result.stderr):
        raise TransferError(result.stderr)
    packages = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) == 6 and fields[1] in {"install", "update", "remove", "configure", "reinstall", "hold"}:
            packages.append(dict(name=fields[0], version="", action=fields[1], repo=redact(fields[3]),
                                 unpack=size_value(fields[4]), size=size_value(fields[5])))
    if result.stdout.strip() and not packages:
        raise TransferError(redact(result.stdout))
    download = sum(p["size"] or 0 for p in packages)
    return dict(packages=packages, download=download, change=None if packages else 0,
                native=redact(result.stdout + result.stderr),
                disks=disk_rows("/var/cache/xbps", download, sum(p["unpack"] or 0 for p in packages)))


def check(pm, work, mode):
    info = release()
    plan = dict(os=info.get("NAME", info.get("ID", "")), version=info.get("VERSION_ID") or info.get("BUILD_ID"),
                pm=pm, live=live_session(), reboot=configured_reboot(pm), security=None, repos=[],
                actions=list(additional(pm)), snapshot=False, disks=disk_rows(cache_path(pm)))
    try:
        if pm == "pacman":
            plan.update(check_pacman(work))
        elif pm == "dnf":
            plan.update(check_dnf(work, mode))
        else:
            plan.update(check_void())
    except (TransferError, OSError, ValueError, subprocess.TimeoutExpired) as exc:
        plan["error"] = redact(exc)[:20000]
    if not plan["live"]:
        try:
            plan["snapshot"] = bool(snapshot_config())
        except (TransferError, OSError, subprocess.TimeoutExpired):
            pass
    (work / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
    return 0


def activity(stage, name):
    print(f"@@activity\t{stage}\t{name}", flush=True)


def operation_lock():
    from manager import installer_state_dir

    path = installer_state_dir().parent / ".serpantinum-install.lock"
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    return path


def upgrade(pm, work, mode, snapshot):
    import fcntl

    if live_session():
        raise TransferError("Full upgrades are disabled in Live sessions")
    plan = json.loads((work / "plan.json").read_text(encoding="utf-8"))
    if plan["pm"] != pm or plan.get("error") or not plan.get("packages"):
        raise TransferError("Check and review system updates before installing")
    with operation_lock().open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise TransferError("Another Serpantinum installation or update is running") from exc
        if pm == "pacman":
            cache = cache_path(pm)
            cache.mkdir(mode=0o700, parents=True, exist_ok=True)
            with tempfile.TemporaryDirectory(dir=work) as folder:
                return upgrade_pacman(work, folder, mode, cache, plan, snapshot)
        activity("Preparing", "Repository transaction")
        fresh = check_dnf(work, mode) if pm == "dnf" else check_void()
        if fresh["packages"] != plan["packages"]:
            raise TransferError("The transaction changed; check updates and review the new plan")
        if fresh["download"] is None:
            raise TransferError("The package manager could not estimate the required download space")
        ensure_space(fresh["disks"])
        make_snapshot(snapshot)
        activity("Installing", "System packages")
        if pm == "dnf":
            args = ["sudo", "dnf", "--setopt=assumeyes=False", "--setopt=*.skip_if_unavailable=False",
                    "--setopt=keepcache=True", f"--setopt=max_parallel_downloads={DOWNLOAD_MODES[mode]}",
                    "--refresh", "upgrade"]
        else:
            args = ["sudo", "xbps-install", "-Su"]
        subprocess.run(args, check=True)
        activity("Verifying", "System packages")
        remaining = check_dnf(work, mode) if pm == "dnf" else check_void()
        keys = {(p["name"], p["version"], p.get("arch")) for p in plan["packages"]}
        pending = {(p["name"], p["version"], p.get("arch")) for p in remaining["packages"]}
        if keys & pending:
            raise TransferError("Some reviewed packages are still pending. Review the native journal.")
        return 0


def make_snapshot(requested):
    if requested:
        config = snapshot_config()
        if not config:
            raise TransferError("The configured Snapper root snapshot is unavailable")
        activity("Configuring", "Snapper Btrfs snapshot")
        subprocess.run(["sudo", "snapper", "-c", config, "create", "--type", "single",
                        "--description", "Before Serpantinum system update", "--print-number"], check=True)


def upgrade_pacman(work, folder, mode, cache, plan, snapshot):
    activity("Preparing", "Pacman transaction")
    db = pacman_db()
    lock_check(db)
    versions = pacman_versions()
    temporary = work / "database"
    backend = SystemPacman(cache, folder, temporary, db, plan, versions)
    packages, preview = pacman_plan(backend, temporary, versions)
    if pacman_fingerprint(packages, versions, output("pacman-conf")) != plan["fingerprint"]:
        raise TransferError("Installed packages or repository configuration changed; check updates again")
    ensure_space(preview["disks"])
    make_snapshot(snapshot)
    queue = Queue(packages, cache, Settings(mode=mode))
    try:
        return run_transaction(backend, queue, [])
    finally:
        report = queue.report()
        report.pop("packages")
        print("@@report\t" + json.dumps(report), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["check", "upgrade", "additional", "reboot"])
    parser.add_argument("pm", choices=["pacman", "dnf", "void"])
    parser.add_argument("work", type=Path)
    parser.add_argument("--mode", choices=DOWNLOAD_MODES, default="balanced")
    parser.add_argument("--snapshot", action="store_true")
    parser.add_argument("--source", default="")
    args = parser.parse_args()
    try:
        if args.operation == "check":
            return check(args.pm, args.work, args.mode)
        if args.operation == "upgrade":
            return upgrade(args.pm, args.work, args.mode, args.snapshot)
        if live_session():
            raise TransferError("This action is disabled in Live sessions")
        if args.operation == "additional":
            command = additional(args.pm).get(args.source)
            if command is None:
                raise TransferError("This additional package source is unavailable")
            if args.source == "aur":
                plan = json.loads((args.work / "plan.json").read_text(encoding="utf-8"))
                if plan.get("error") or plan.get("packages") != []:
                    raise TransferError("Check that the repository packages are current before updating AUR")
            command = ["flock", "-n", str(operation_lock()), *command]
        else:
            command = (["systemctl", "reboot"] if Path("/run/systemd/system").is_dir()
                       else ["sudo", "reboot"])
        activity("Installing" if args.operation == "additional" else "Configuring", command[0])
        return subprocess.call(command)
    except (OSError, ValueError, TransferError, subprocess.SubprocessError) as exc:
        print(redact(exc), file=sys.stderr, flush=True)
        if args.operation == "check":
            (args.work / "plan.json").write_text(json.dumps({"error": redact(exc)}), encoding="utf-8")
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
