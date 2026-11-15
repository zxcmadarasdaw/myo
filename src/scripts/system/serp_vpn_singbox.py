"""sing-box binary management for the Serpantinum VPN client (no root).

Used by serp_vpn.py (`singbox-info`, `singbox-install`, `singbox-use`). Nothing here
needs root and nothing is run through a shell.

Install = the official release from GitHub (SagerNet/sing-box), for this machine's
architecture, into ~/.local/share/serpantinum/vpn/bin/sing-box:

  1. the release and its published digest are found through the GitHub API;
  2. the archive is downloaded with progress lines on stdout, a stall timeout, up to
     four attempts that resume with an HTTP Range request, and SIGTERM to cancel;
  3. its SHA-256 must match the published digest before anything can run;
  4. only the `sing-box` file is read out of the tar (no paths from the archive are
     used), written with mode 755, and accepted only when `sing-box version` runs and
     reports a version. Then it replaces the previous managed binary atomically.

This binary serves the proxy mode. The TUN mode's root service only runs a sing-box
from /usr/bin or /usr/local/bin (installed by dnf), on purpose: a root service never
runs a file a user process could have written.
"""
import hashlib
import http.client
import json
import os
import platform
import re
import shutil
import socket
import ssl
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

RELEASE_API = "https://api.github.com/repos/SagerNet/sing-box/releases/latest"
DOWNLOAD_BASE = "https://github.com/SagerNet/sing-box/releases/download"
USER_AGENT = "serpantinum-vpn"
CONNECT_TIMEOUT = 20          # seconds to get an answer
STALL_TIMEOUT = 30            # seconds without a single byte -> retry (resume)
ATTEMPTS = 4
DOWNLOAD_DEADLINE = 15 * 60   # s for the whole download, all attempts
MAX_ARCHIVE = 120 * 1024 * 1024
MAX_BINARY = 256 * 1024 * 1024
ARCH = {
    "x86_64": "amd64", "amd64": "amd64",
    "aarch64": "arm64", "arm64": "arm64",
    "armv7l": "armv7", "armv7": "armv7",
    "armv6l": "armv6",
    "i386": "386", "i686": "386",
    "riscv64": "riscv64", "s390x": "s390x", "ppc64le": "ppc64le",
    "loongarch64": "loong64",
}
SYSTEM_DIRS = ("/usr/bin", "/usr/local/bin")


class SingboxError(Exception):
    """code is a key of serp_vpn.MESSAGES; detail is safe to show."""

    def __init__(self, code, detail=""):
        super().__init__(code)
        self.code = code
        self.detail = detail


def _xdg(var, fallback):
    v = os.environ.get(var, "")
    return v if v else os.path.join(os.path.expanduser("~"), fallback)


def managed_dir():
    return os.environ.get("SERP_VPN_BIN_DIR") or os.path.join(_xdg("XDG_DATA_HOME", ".local/share"),
                                                              "serpantinum", "vpn", "bin")


def managed_path():
    return os.path.join(managed_dir(), "sing-box")


def arch_name(machine=None):
    m = (machine or platform.machine() or "").lower()
    return ARCH.get(m, "")


def is_executable(path):
    return bool(path) and os.path.isfile(path) and os.access(path, os.X_OK)


def probe(path, timeout=10):
    """{"ok", "version", "error"}: runs `PATH version`; a file is accepted only when it says it is sing-box."""
    if not path or not os.path.isabs(path):
        return {"ok": False, "version": "", "error": "not_absolute"}
    if not os.path.isfile(path):
        return {"ok": False, "version": "", "error": "not_found"}
    if not os.access(path, os.X_OK):
        return {"ok": False, "version": "", "error": "not_executable"}
    try:
        p = subprocess.run([path, "version"], capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL, errors="replace")
    except subprocess.TimeoutExpired:
        return {"ok": False, "version": "", "error": "timeout"}
    except OSError as e:
        return {"ok": False, "version": "", "error": e.strerror or type(e).__name__}
    m = re.search(r"sing-box version\s+(\S+)", p.stdout or "")
    if p.returncode != 0 or not m:
        return {"ok": False, "version": "", "error": "not_singbox"}
    return {"ok": True, "version": m.group(1), "error": ""}


def candidates():
    """sing-box files found on this system (not run): PATH, the system dirs, ~/.local/bin, the managed one."""
    seen = []
    dirs = [d for d in os.environ.get("PATH", "").split(os.pathsep) if d]
    dirs += list(SYSTEM_DIRS) + [os.path.join(os.path.expanduser("~"), ".local", "bin"), managed_dir()]
    for d in dirs:
        p = os.path.join(d, "sing-box")
        if is_executable(p):
            r = os.path.realpath(p)
            if r not in seen:
                seen.append(r)
    return seen


# ---- release lookup ----------------------------------------------------------------------


def _opener():
    # the user's own HTTPS_PROXY/https_proxy is honoured (urllib reads it from the environment)
    return urllib.request.build_opener(HttpsRedirect())


class HttpsRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if req.type == "https" and urllib.parse.urlsplit(newurl).scheme != "https":
            raise SingboxError("sb_tls", "HTTPS redirect required")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _get(url, timeout=CONNECT_TIMEOUT, headers=None):
    h = {"User-Agent": USER_AGENT, "Accept": "*/*"}
    h.update(headers or {})
    return _opener().open(urllib.request.Request(url, headers=h), timeout=timeout)


def _net_error(e):
    """Network exception -> SingboxError with a short reason a user can act on."""
    if isinstance(e, SingboxError):
        return e
    if isinstance(e, urllib.error.HTTPError):
        return SingboxError("sb_http", e.code)
    reason = getattr(e, "reason", e)
    if isinstance(reason, (socket.timeout, TimeoutError)) or isinstance(e, (socket.timeout, TimeoutError)):
        return SingboxError("sb_timeout")
    if isinstance(reason, ssl.SSLError) or isinstance(e, ssl.SSLError):
        return SingboxError("sb_tls", getattr(reason, "reason", None) or type(reason).__name__)
    if isinstance(reason, socket.gaierror):
        return SingboxError("sb_offline")
    if isinstance(reason, ConnectionRefusedError):
        return SingboxError("sb_unreachable", "refused")
    if isinstance(reason, OSError):
        return SingboxError("sb_unreachable", reason.strerror or type(reason).__name__)
    if isinstance(reason, str):
        return SingboxError("sb_unreachable", reason[:120])
    return SingboxError("sb_unreachable", type(reason).__name__)


def asset_name(version, arch):
    return f"sing-box-{version}-linux-{arch}.tar.gz"


def release_info(arch, api_url=None):
    """{"version", "name", "url", "size", "sha256", "source"} of the latest stable release."""
    override = api_url or os.environ.get("SERP_VPN_SINGBOX_API")
    try:
        with _get(override or RELEASE_API, headers={"Accept": "application/vnd.github+json"}) as r:
            data = json.loads(r.read(4 * 1024 * 1024).decode("utf-8"))
        tag = str(data.get("tag_name") or "")
        version = tag[1:] if tag.startswith("v") else tag
        if not re.fullmatch(r"\d+\.\d+\.\d+", version):
            raise SingboxError("sb_no_release", tag or "?")
        name = asset_name(version, arch)
        for a in data.get("assets") or []:
            if a.get("name") == name:
                digest = str(a.get("digest") or "")
                sha = digest[7:].lower() if digest.lower().startswith("sha256:") else ""
                if not re.fullmatch(r"[0-9a-f]{64}", sha):
                    raise SingboxError("sb_no_digest", name)
                url = str(a.get("browser_download_url") or "")
                if not override and url != f"{DOWNLOAD_BASE}/v{version}/{name}":
                    raise SingboxError("sb_no_asset", name)
                return {"version": version, "name": name, "url": url, "size": int(a.get("size") or 0),
                        "sha256": sha, "source": "api"}
        raise SingboxError("sb_no_asset", name)
    except (ValueError, TypeError, AttributeError):
        raise SingboxError("sb_no_release", "JSON") from None
    except (OSError, http.client.HTTPException) as e:
        raise _net_error(e) from None


# ---- download ----------------------------------------------------------------------------


def _human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024.0
    return str(n)


def _set_stall_timeout(response):
    """A read that waits longer than STALL_TIMEOUT raises socket.timeout (then: retry with Range)."""
    for path in (("fp", "raw", "_sock"), ("fp", "fp", "raw", "_sock")):
        obj = response
        try:
            for name in path:
                obj = getattr(obj, name)
            obj.settimeout(STALL_TIMEOUT)
            return
        except (AttributeError, OSError):
            continue


def download(url, dest, expected_size, emit, attempts=ATTEMPTS, sleep=time.sleep):
    """Downloads url to dest (resuming on retries). Calls emit(dict) with progress. Returns bytes written."""
    done = 0
    last_error = None
    started = time.monotonic()
    for attempt in range(1, attempts + 1):
        headers = {}
        if done > 0:
            headers["Range"] = f"bytes={done}-"
        try:
            with _get(url, headers=headers) as r:
                status = getattr(r, "status", 200)
                total = expected_size
                if done > 0 and status != 206:          # the server ignored Range: start over
                    done = 0
                length = r.headers.get("Content-Length")
                if status == 206:
                    match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", r.headers.get("Content-Range", ""))
                    if (not match or int(match[1]) != done or int(match[2]) + 1 != int(match[3])
                            or (expected_size and int(match[3]) != expected_size)):
                        done = 0
                        raise SingboxError("sb_incomplete", "Content-Range")
                    total = int(match[3])
                elif not total and length and length.isdigit():
                    total = int(length)
                if total > MAX_ARCHIVE:
                    raise SingboxError("sb_too_large", _human(total))
                _set_stall_timeout(r)
                last_emit = 0.0
                window = []                                  # (time, bytes) of the last 3 s, for the speed
                with open(dest, "ab" if done > 0 else "wb") as f:
                    while True:
                        chunk = r.read1(64 * 1024)
                        if not chunk:
                            break
                        f.write(chunk)
                        done += len(chunk)
                        if done > MAX_ARCHIVE:
                            raise SingboxError("sb_too_large", _human(done))
                        if time.monotonic() - started > DOWNLOAD_DEADLINE:
                            raise SingboxError("sb_slow", _human(done))
                        now = time.monotonic()
                        window.append((now, done))
                        while len(window) > 1 and now - window[0][0] > 3.0:
                            window.pop(0)
                        if now - last_emit >= 0.25:
                            span = now - window[0][0]
                            speed = (done - window[0][1]) / span if span > 0 else 0
                            emit({"event": "progress", "done": done, "total": total, "speed": int(speed),
                                  "attempt": attempt})
                            last_emit = now
            if total and done != total:
                detail = f"{_human(done)} / {_human(total)}"
                if done > total:
                    done = 0
                raise SingboxError("sb_incomplete", detail)
            emit({"event": "progress", "done": done, "total": total or done, "speed": 0, "attempt": attempt,
                  "seconds": round(time.monotonic() - started, 1)})
            return done
        except SingboxError as e:
            if e.code in ("sb_too_large", "sb_tls", "sb_slow"):
                raise
            last_error = e
        except (OSError, http.client.HTTPException) as e:
            last_error = _net_error(e)
            if isinstance(e, urllib.error.HTTPError):
                if e.code in (401, 403, 404, 410):
                    raise last_error
                if e.code == 416:                       # range past the end: start over
                    done = 0
        if attempt < attempts and time.monotonic() - started > DOWNLOAD_DEADLINE:
            raise SingboxError("sb_slow", _human(done))
        if attempt < attempts:
            wait = 2 ** attempt
            emit({"event": "retry", "attempt": attempt + 1, "of": attempts, "wait": wait,
                  "code": last_error.code, "detail": str(last_error.detail)})
            sleep(wait)
    raise last_error or SingboxError("sb_unreachable")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def extract_binary(archive, out_path):
    """Writes only the archive's `sing-box` regular file to out_path (mode 755)."""
    try:
        with tarfile.open(archive, "r:gz") as tar:
            member = None
            for m in tar:
                if m.isfile() and os.path.basename(m.name) == "sing-box":
                    member = m
                    break
            if member is None:
                raise SingboxError("sb_bad_archive", "no sing-box file")
            if member.size <= 0 or member.size > MAX_BINARY:
                raise SingboxError("sb_bad_archive", "size")
            src = tar.extractfile(member)
            if src is None:
                raise SingboxError("sb_bad_archive", "unreadable")
            with src, open(out_path, "wb") as dst:
                shutil.copyfileobj(src, dst, 1024 * 1024)
    except SingboxError:
        raise
    except (tarfile.TarError, EOFError, OSError) as e:
        raise SingboxError("sb_bad_archive", type(e).__name__)
    os.chmod(out_path, 0o755)


def install(emit, arch=None, api_url=None, validate=None):
    """Install atomically after the version and optional profile checks pass."""
    arch = arch or arch_name()
    if not arch:
        raise SingboxError("sb_arch", platform.machine() or "?")
    emit({"event": "stage", "stage": "release"})
    rel = release_info(arch, api_url=api_url)
    emit({"event": "stage", "stage": "download", "version": rel["version"], "name": rel["name"],
          "total": rel["size"], "checksum": bool(rel["sha256"])})
    target_dir = managed_dir()
    os.makedirs(target_dir, mode=0o700, exist_ok=True)
    work = tempfile.mkdtemp(prefix=".install-", dir=target_dir)
    try:
        archive = os.path.join(work, rel["name"])
        download(rel["url"], archive, rel["size"], emit)
        emit({"event": "stage", "stage": "verify"})
        digest = sha256_file(archive)
        if digest != rel["sha256"]:
            raise SingboxError("sb_checksum", digest[:12] + "… ≠ " + rel["sha256"][:12] + "…")
        emit({"event": "stage", "stage": "extract"})
        tmp_bin = os.path.join(work, "sing-box")
        extract_binary(archive, tmp_bin)
        emit({"event": "stage", "stage": "test"})
        checked = probe(tmp_bin)
        if not checked["ok"] or checked["version"] != rel["version"]:
            raise SingboxError("sb_not_working", checked["error"] or "version mismatch")
        if validate is not None:
            validate(tmp_bin)
        final = managed_path()
        os.replace(tmp_bin, final)
        return {"ok": True, "path": final, "version": checked["version"], "release": rel["version"],
                "sha256": digest, "verified": bool(rel["sha256"]), "source": rel["source"]}
    finally:
        shutil.rmtree(work, ignore_errors=True)


# ---- offline bundle -------------------------------------------------------------------------
#
# A release of Serpantinum can carry `vpn-bundle/`: the official sing-box archive, a
# manifest.json and SHA256SUMS (built by packaging/vpn-bundle/build_vpn_bundle.py). Installing
# from it needs no network. The trust anchor is serp_vpn_singbox.lock.json next to this file:
# the archive must have exactly the version, size and SHA-256 pinned there, whatever the
# bundle's own manifest says.

LOCK_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "serp_vpn_singbox.lock.json")
BUNDLE_DIRNAME = "vpn-bundle"
SYSTEM_TARGET = "/usr/local/bin/sing-box"


def load_lock(path=None):
    try:
        with open(path or LOCK_PATH, encoding="utf-8") as f:
            lock = json.load(f)
        if not re.fullmatch(r"\d+\.\d+\.\d+", str(lock["version"])):
            raise ValueError("version")
        for asset in lock["assets"].values():
            if not re.fullmatch(r"[0-9a-f]{64}", asset["sha256"]) or int(asset["size"]) <= 0:
                raise ValueError("asset")
        return lock
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        raise SingboxError("sb_bundle_lock") from None


def bundle_dirs():
    """Where a bundle is looked for, in order: $SERP_VPN_BUNDLE, the installed copy, the source tree."""
    here = os.path.dirname(os.path.abspath(__file__))
    dirs = [os.environ.get("SERP_VPN_BUNDLE", ""),
            os.path.join(_xdg("XDG_DATA_HOME", ".local/share"), "serpantinum", BUNDLE_DIRNAME),
            os.path.normpath(os.path.join(here, "..", "..", "..", BUNDLE_DIRNAME)),
            os.path.join("/usr/share/serpantinum", BUNDLE_DIRNAME)]
    seen = []
    for d in dirs:
        if d and os.path.abspath(d) not in seen:
            seen.append(os.path.abspath(d))
    return seen


def read_bundle(folder, arch=None, lock=None):
    """{"dir", "version", "archive", "size", "sha256"} when folder holds a bundle that matches the
    lock for this architecture. Cheap: does not hash the archive (install does)."""
    arch = arch or arch_name()
    lock = lock or load_lock()
    asset = lock["assets"].get(arch)
    if not asset:
        raise SingboxError("sb_bundle_arch", arch or "?")
    manifest_path = os.path.join(folder, "manifest.json")
    try:
        with open(manifest_path, encoding="utf-8") as f:
            manifest = json.load(f)
        files = {item["arch"]: item for item in manifest["files"]}
    except FileNotFoundError:
        raise SingboxError("sb_bundle_missing", folder) from None
    except (OSError, ValueError, KeyError, TypeError):
        raise SingboxError("sb_bundle_bad", "manifest.json") from None
    item = files.get(arch)
    if manifest.get("component") != "sing-box" or manifest.get("version") != lock["version"]:
        raise SingboxError("sb_bundle_version", str(manifest.get("version", "?")) + " ≠ " + lock["version"])
    if not item or item.get("file") != asset["name"] or item.get("sha256") != asset["sha256"]:
        raise SingboxError("sb_bundle_arch", arch)
    archive = os.path.join(folder, asset["name"])
    if os.path.islink(archive) or not os.path.isfile(archive):
        raise SingboxError("sb_bundle_bad", asset["name"])
    if os.path.getsize(archive) != int(asset["size"]):
        raise SingboxError("sb_bundle_bad", "size")
    return {"dir": os.path.abspath(folder), "version": lock["version"], "archive": archive,
            "size": int(asset["size"]), "sha256": asset["sha256"]}


def find_bundle(arch=None):
    """(bundle or None, reasons): the first usable bundle and why the other places were skipped."""
    reasons = []
    try:
        lock = load_lock()
    except SingboxError as e:
        return None, [e.code]
    for folder in bundle_dirs():
        if not os.path.isdir(folder):
            continue
        try:
            return read_bundle(folder, arch, lock), reasons
        except SingboxError as e:
            reasons.append(f"{folder}: {e.code} {e.detail}".strip())
    return None, reasons


def _verified_binary(bundle, work, emit):
    emit({"event": "stage", "stage": "verify"})
    digest = sha256_file(bundle["archive"])
    if digest != bundle["sha256"]:
        raise SingboxError("sb_checksum", digest[:12] + "… ≠ " + bundle["sha256"][:12] + "…")
    emit({"event": "stage", "stage": "extract"})
    tmp_bin = os.path.join(work, "sing-box")
    extract_binary(bundle["archive"], tmp_bin)
    emit({"event": "stage", "stage": "test"})
    checked = probe(tmp_bin)
    if not checked["ok"] or checked["version"] != bundle["version"]:
        raise SingboxError("sb_not_working", checked["error"] or "version mismatch")
    return tmp_bin, digest


def install_from_bundle(emit, folder=None, arch=None, validate=None):
    """Offline install into the managed path (proxy mode). No network is used."""
    arch = arch or arch_name()
    if not arch:
        raise SingboxError("sb_arch", platform.machine() or "?")
    emit({"event": "stage", "stage": "bundle"})
    if folder:
        bundle = read_bundle(folder, arch)
    else:
        bundle, reasons = find_bundle(arch)
        if bundle is None:
            # A bundle that exists but is wrong: report its own reason, not "missing".
            present = next((d for d in bundle_dirs() if os.path.isfile(os.path.join(d, "manifest.json"))), None)
            if present:
                read_bundle(present, arch)
            raise SingboxError("sb_bundle_missing", "; ".join(reasons))
    target_dir = managed_dir()
    os.makedirs(target_dir, mode=0o700, exist_ok=True)
    work = tempfile.mkdtemp(prefix=".install-", dir=target_dir)
    try:
        tmp_bin, digest = _verified_binary(bundle, work, emit)
        if validate is not None:
            validate(tmp_bin)
        final = managed_path()
        os.replace(tmp_bin, final)
        return {"ok": True, "path": final, "version": bundle["version"], "release": bundle["version"],
                "sha256": digest, "verified": True, "source": "bundle", "bundle": bundle["dir"]}
    finally:
        shutil.rmtree(work, ignore_errors=True)


def install_system_from_bundle(folder, arch=None, target=SYSTEM_TARGET):
    """Root only (the installer runs it as root): the same checks, then /usr/local/bin/sing-box
    owned by root, which is what the TUN service accepts. Never writes outside `target`."""
    if hasattr(os, "geteuid") and os.geteuid() != 0:
        raise SingboxError("sb_bundle_root")
    bundle = read_bundle(folder, arch)
    work = tempfile.mkdtemp(prefix="serpantinum-singbox-")
    try:
        tmp_bin, digest = _verified_binary(bundle, work, lambda _event: None)
        staged = target + ".new"
        shutil.copyfile(tmp_bin, staged)
        os.chmod(staged, 0o755)
        if hasattr(os, "chown"):
            os.chown(staged, 0, 0)
        os.replace(staged, target)
        return {"ok": True, "path": target, "version": bundle["version"], "sha256": digest}
    finally:
        shutil.rmtree(work, ignore_errors=True)


def system_path(path):
    """True when the file is in a directory the TUN root service accepts."""
    return bool(path) and os.path.dirname(os.path.realpath(path)) in SYSTEM_DIRS


if __name__ == "__main__":
    # `install-system --bundle DIR`: used by the installer as root (TUN mode needs a root-owned
    # sing-box). Without arguments: prints the architecture, the files found and the bundle.
    if sys.argv[1:2] == ["install-system"]:
        folder = next((a[len("--bundle="):] for a in sys.argv[2:] if a.startswith("--bundle=")), "")
        try:
            if not folder:
                raise SingboxError("sb_bundle_missing", "--bundle=DIR")
            print(json.dumps(install_system_from_bundle(folder)))
            sys.exit(0)
        except SingboxError as e:
            print(json.dumps({"ok": False, "error": {"code": e.code, "detail": str(e.detail)}}))
            sys.exit(1)
    found, why = find_bundle()
    print(json.dumps({"arch": arch_name(), "managed": managed_path(), "candidates": candidates(),
                      "bundle": found, "bundleSkipped": why}, indent=2))
    sys.exit(0)
