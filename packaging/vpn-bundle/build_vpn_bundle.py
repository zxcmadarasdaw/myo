#!/usr/bin/env python3
"""Build the offline VPN bundle of a Serpantinum release (developer machine, network allowed).

    python3 packaging/vpn-bundle/build_vpn_bundle.py                 # dist/vpn-bundle, amd64
    python3 packaging/vpn-bundle/build_vpn_bundle.py --arch all      # amd64 + arm64
    python3 packaging/vpn-bundle/build_vpn_bundle.py --release       # + dist/serpantinum-<v>-offline.tar.gz

What it does, and nothing else:
  1. reads the pinned version and SHA-256 from src/scripts/system/serp_vpn_singbox.lock.json;
  2. downloads the official archive only from github.com/SagerNet/sing-box/releases (HTTPS,
     no mirror), or reuses a cached copy with the same hash;
  3. refuses any file whose size or SHA-256 differs from the lock (and, with --verify-api,
     from the digest GitHub publishes for the asset);
  4. writes vpn-bundle/: the archive unchanged, manifest.json, SHA256SUMS, README.txt and
     install-vpn-bundle.sh.

The archive is never unpacked here and never committed to Git: dist/ is ignored. Release
artifacts (the offline tarball) are uploaded to the GitHub release page instead.
To move to a new sing-box version, update the lock file (version, size, sha256 from the
release page / API) in a reviewed commit, then rebuild.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "src/scripts/system/serp_vpn_singbox.lock.json"
DOWNLOAD = "https://github.com/SagerNet/sing-box/releases/download/v{version}/{name}"
API = "https://api.github.com/repos/SagerNet/sing-box/releases/tags/v{version}"
HERE = Path(__file__).resolve().parent


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def fetch(url, dest, timeout=60):
    request = urllib.request.Request(url, headers={"User-Agent": "serpantinum-release-build"})
    with urllib.request.urlopen(request, timeout=timeout) as response, open(dest, "wb") as out:
        if not response.geturl().startswith("https://"):
            raise SystemExit(f"refused non-HTTPS redirect: {response.geturl()}")
        shutil.copyfileobj(response, out, 1 << 20)


def api_digests(version):
    request = urllib.request.Request(API.format(version=version), headers={
        "User-Agent": "serpantinum-release-build", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = json.load(response)
    return {a["name"]: str(a.get("digest") or "").removeprefix("sha256:") for a in data.get("assets", [])}


def cached_asset(asset, url, cache, offline):
    cached = cache / asset["name"]
    if cached.is_file() and cached.stat().st_size == asset["size"] and sha256(cached) == asset["sha256"]:
        return cached
    if offline:
        raise SystemExit(f"verified cache entry required: {cached}")
    fd, filename = tempfile.mkstemp(prefix=".download-", suffix=".part", dir=cache)
    os.close(fd)
    partial = Path(filename)
    try:
        print(f"download {url}")
        fetch(url, partial)
        if partial.stat().st_size != asset["size"] or sha256(partial) != asset["sha256"]:
            raise SystemExit(f"{asset['name']}: size or SHA-256 differs from the lock")
        partial.replace(cached)
    finally:
        partial.unlink(missing_ok=True)
    return cached


def get_asset(lock, arch, cache, verify_api, offline=False):
    asset = lock["assets"][arch]
    if verify_api:
        published = api_digests(lock["version"]).get(asset["name"], "")
        if published != asset["sha256"]:
            raise SystemExit(f"{asset['name']}: GitHub publishes {published or 'no digest'}, the lock says {asset['sha256']}")
    url = DOWNLOAD.format(version=lock["version"], name=asset["name"])
    cached = cached_asset(asset, url, cache, offline)
    print(f"ok  {asset['name']}  {asset['sha256']}")
    return cached, asset


def write_templates(out):
    sys.path.insert(0, str(LOCK.parent))
    import serp_vpn
    import serp_vpn_root

    settings = {**serp_vpn.DEFAULT_SETTINGS, "secret": "local-check-only"}
    server = {"protocol": "socks", "tag": "local-test", "address": "127.0.0.1", "port": 1}
    proxy = serp_vpn.build_config([server], settings)
    tun = serp_vpn_root.build(serp_vpn.tun_payload(proxy, settings))
    for mode, config in (("proxy", proxy), ("tun", tun)):
        (out / f"{mode}.check.json").write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8", newline="\n")


def write_bundle(lock, arches, out, cache, verify_api, fedora, offline):
    out.mkdir(parents=True)
    files = []
    for arch in arches:
        source, asset = get_asset(lock, arch, cache, verify_api, offline)
        shutil.copyfile(source, out / asset["name"])
        files.append({"arch": arch, "file": asset["name"], "size": asset["size"], "sha256": asset["sha256"]})
    manifest = {"format": 1, "component": "sing-box", "version": lock["version"], "source": lock["source"],
                "builtAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "files": files}
    if fedora:
        rpm_dir, rpm_cache = out / "rpms", cache / "fedora45"
        rpm_dir.mkdir()
        rpm_cache.mkdir(exist_ok=True)
        for asset in fedora["rpms"]:
            name = asset["name"]
            path = cached_asset(asset, f"{fedora['source']}{name[0]}/{name}", rpm_cache, offline)
            shutil.copyfile(path, rpm_dir / name)
        (rpm_dir / "packages.tsv").write_text("".join(f"{a['package']}\t{a['name']}\n" for a in fedora["rpms"]),
                                             encoding="utf-8", newline="\n")
        manifest["fedora"] = {"release": 45, "arch": "x86_64", **fedora}
    write_templates(out)
    shutil.copyfile(HERE / "README.txt", out / "README.txt")
    shutil.copyfile(HERE / "install-vpn-bundle.sh", out / "install-vpn-bundle.sh")
    os.chmod(out / "install-vpn-bundle.sh", 0o755)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    checksums = "".join(f"{sha256(path)}  {path.relative_to(out).as_posix()}\n" for path in sorted(out.rglob("*")) if path.is_file())
    (out / "SHA256SUMS").write_text(checksums, encoding="utf-8", newline="\n")
    return manifest


def build_bundle(lock, arches, out, cache, verify_api, fedora=None, offline=False):
    if out.is_symlink() or (out.exists() and not (out / "manifest.json").is_file()):
        raise SystemExit(f"bundle output is not a managed bundle directory: {out}")
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".vpn-bundle-", dir=out.parent) as temp:
        stage, backup = Path(temp) / "stage", Path(temp) / "previous"
        manifest = write_bundle(lock, arches, stage, cache, verify_api, fedora, offline)
        if out.exists():
            out.rename(backup)
        try:
            stage.rename(out)
        except OSError:
            if backup.exists():
                backup.rename(out)
            raise
    print(f"bundle: {out}")
    return manifest


def build_release(out_bundle, dist, revision="HEAD"):
    """A Git snapshot plus the offline bundle in one tarball."""
    version = (ROOT / "version.txt").read_text(encoding="utf-8").strip()
    target = dist / f"serpantinum-{version}-offline.tar.gz"
    with tempfile.TemporaryDirectory(prefix=".vpn-release-", dir=dist) as temp:
        archive, output = Path(temp) / "source.tar", Path(temp) / target.name
        with archive.open("wb") as stream:
            subprocess.run(["git", "-C", str(ROOT), "archive", "--format=tar", "--prefix=serpantinum/", revision],
                           stdout=stream, check=True)
        with tarfile.open(output, "w:gz") as release, tarfile.open(archive) as source:
            for member in source:
                release.addfile(member, source.extractfile(member) if member.isfile() else None)
            release.add(out_bundle, arcname="serpantinum/vpn-bundle")
        output.replace(target)
    (dist / (target.name + ".sha256")).write_text(f"{sha256(target)}  {target.name}\n", encoding="utf-8", newline="\n")
    print(f"release: {target}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--arch", default="amd64", help="amd64, arm64 or all (default amd64: Fedora x86_64)")
    parser.add_argument("--out", type=Path, default=ROOT / "dist/vpn-bundle")
    parser.add_argument("--cache", type=Path, default=ROOT / "dist/.cache")
    parser.add_argument("--verify-api", action="store_true", help="also compare with the digest GitHub publishes")
    parser.add_argument("--release", action="store_true", help="also build the offline Serpantinum tarball")
    parser.add_argument("--revision", default="HEAD", help="Git commit or tree for --release")
    parser.add_argument("--offline-build", action="store_true", help="build only from previously verified cache entries")
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    arches = sorted(lock["assets"]) if args.arch == "all" else [args.arch]
    unknown = [a for a in arches if a not in lock["assets"]]
    if unknown:
        raise SystemExit(f"no pinned asset for {unknown}; known: {sorted(lock['assets'])}")
    args.cache.mkdir(parents=True, exist_ok=True)
    if args.offline_build and args.verify_api:
        parser.error("--offline-build and --verify-api are mutually exclusive")
    fedora = json.loads((HERE / "fedora45-rpms.lock.json").read_text(encoding="utf-8")) if "amd64" in arches else None
    build_bundle(lock, arches, args.out, args.cache, args.verify_api, fedora, args.offline_build)
    if args.release:
        build_release(args.out, args.out.parent, args.revision)
    return 0


if __name__ == "__main__":
    sys.exit(main())
