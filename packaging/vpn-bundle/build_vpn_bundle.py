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
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
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


def get_asset(lock, arch, cache, verify_api):
    asset = lock["assets"][arch]
    cached = cache / asset["name"]
    if not (cached.is_file() and sha256(cached) == asset["sha256"]):
        url = DOWNLOAD.format(version=lock["version"], name=asset["name"])
        print(f"download {url}")
        partial = cached.with_suffix(".part")
        fetch(url, partial)
        partial.replace(cached)
    size, digest = cached.stat().st_size, sha256(cached)
    if size != asset["size"] or digest != asset["sha256"]:
        cached.unlink(missing_ok=True)
        raise SystemExit(f"{asset['name']}: size/sha256 {size}/{digest} differ from the lock; nothing was built")
    if verify_api:
        published = api_digests(lock["version"]).get(asset["name"], "")
        if published != asset["sha256"]:
            raise SystemExit(f"{asset['name']}: GitHub publishes {published or 'no digest'}, the lock says {asset['sha256']}")
    print(f"ok  {asset['name']}  {digest}")
    return cached, asset


def build_bundle(lock, arches, out, cache, verify_api):
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    files = []
    for arch in arches:
        source, asset = get_asset(lock, arch, cache, verify_api)
        shutil.copyfile(source, out / asset["name"])
        files.append({"arch": arch, "file": asset["name"], "size": asset["size"], "sha256": asset["sha256"]})
    manifest = {"format": 1, "component": "sing-box", "version": lock["version"], "source": lock["source"],
                "builtAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "files": files}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (out / "SHA256SUMS").write_text("".join(f"{f['sha256']}  {f['file']}\n" for f in files), encoding="utf-8")
    shutil.copyfile(HERE / "README.txt", out / "README.txt")
    shutil.copyfile(HERE / "install-vpn-bundle.sh", out / "install-vpn-bundle.sh")
    os.chmod(out / "install-vpn-bundle.sh", 0o755)
    print(f"bundle: {out}")
    return manifest


def build_release(out_bundle, dist):
    """Serpantinum at HEAD (git archive, so only committed files) + vpn-bundle/, one tarball."""
    version = (ROOT / "version.txt").read_text(encoding="utf-8").strip()
    target = dist / f"serpantinum-{version}-offline.tar.gz"
    tree = subprocess.run(["git", "-C", str(ROOT), "archive", "--format=tar", "--prefix=serpantinum/", "HEAD"],
                          capture_output=True, check=True).stdout
    with tarfile.open(target, "w:gz") as release:
        with tarfile.open(fileobj=io.BytesIO(tree)) as source:
            for member in source.getmembers():
                release.addfile(member, source.extractfile(member) if member.isfile() else None)
        release.add(out_bundle, arcname="serpantinum/vpn-bundle")
    (dist / (target.name + ".sha256")).write_text(f"{sha256(target)}  {target.name}\n", encoding="utf-8")
    print(f"release: {target}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--arch", default="amd64", help="amd64, arm64 or all (default amd64: Fedora x86_64)")
    parser.add_argument("--out", type=Path, default=ROOT / "dist/vpn-bundle")
    parser.add_argument("--cache", type=Path, default=ROOT / "dist/.cache")
    parser.add_argument("--verify-api", action="store_true", help="also compare with the digest GitHub publishes")
    parser.add_argument("--release", action="store_true", help="also build the offline Serpantinum tarball")
    args = parser.parse_args()
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    arches = sorted(lock["assets"]) if args.arch == "all" else [args.arch]
    unknown = [a for a in arches if a not in lock["assets"]]
    if unknown:
        raise SystemExit(f"no pinned asset for {unknown}; known: {sorted(lock['assets'])}")
    args.cache.mkdir(parents=True, exist_ok=True)
    build_bundle(lock, arches, args.out, args.cache, args.verify_api)
    if args.release:
        build_release(args.out, args.out.parent)
    return 0


if __name__ == "__main__":
    sys.exit(main())
