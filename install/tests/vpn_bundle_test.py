"""Offline VPN bundle: lock as trust anchor, no network, clear errors, build script checks."""
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src/scripts/system"))
import serp_vpn_singbox as sb  # noqa: E402

VERSION = "9.8.7"
NAME = f"sing-box-{VERSION}-linux-amd64.tar.gz"


def archive_bytes(payload=b"#!/bin/sh\necho sing-box version 9.8.7\n"):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as tar:
        info = tarfile.TarInfo(f"sing-box-{VERSION}-linux-amd64/sing-box")
        info.size = len(payload)
        tar.addfile(info, io.BytesIO(payload))
    return buffer.getvalue()


class BundleTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.data = archive_bytes()
        self.sha = hashlib.sha256(self.data).hexdigest()
        self.lock = base / "lock.json"
        self.lock.write_text(json.dumps({"component": "sing-box", "version": VERSION, "source": "x",
                                         "assets": {"amd64": {"name": NAME, "size": len(self.data),
                                                              "sha256": self.sha}}}), encoding="utf-8")
        self.bundle = base / "vpn-bundle"
        self.bundle.mkdir()
        (self.bundle / NAME).write_bytes(self.data)
        self.write_manifest()
        self.bin_dir = base / "bin"
        patches = [mock.patch.object(sb, "LOCK_PATH", str(self.lock)),
                   mock.patch.dict(os.environ, {"SERP_VPN_BIN_DIR": str(self.bin_dir),
                                                "SERP_VPN_BUNDLE": str(self.bundle),
                                                "XDG_DATA_HOME": str(base / "data")}),
                   mock.patch.object(sb, "probe", lambda path, timeout=10: {"ok": True, "version": VERSION, "error": ""}),
                   # any network use fails the test
                   mock.patch.object(sb, "_get", side_effect=AssertionError("network used")),
                   mock.patch.object(sb, "bundle_dirs", lambda: [str(self.bundle)])]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def tearDown(self):
        self.tmp.cleanup()

    def write_manifest(self, **changes):
        manifest = {"format": 1, "component": "sing-box", "version": VERSION,
                    "files": [{"arch": "amd64", "file": NAME, "size": len(self.data), "sha256": self.sha}]}
        manifest.update(changes)
        (self.bundle / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    def code(self, call):
        with self.assertRaises(sb.SingboxError) as caught:
            call()
        return caught.exception.code

    def test_installs_offline_with_stages_and_without_network(self):
        events = []
        result = sb.install_from_bundle(events.append, arch="amd64")
        self.assertEqual((result["source"], result["version"], result["verified"]), ("bundle", VERSION, True))
        self.assertEqual([e["stage"] for e in events], ["bundle", "verify", "extract", "test"])
        self.assertTrue(Path(result["path"]).is_file())
        self.assertEqual(Path(result["path"]).read_bytes()[:9], b"#!/bin/sh")

    def test_tampered_archive_is_refused_even_with_a_matching_manifest(self):
        bad = archive_bytes(b"#!/bin/sh\necho evil\n")
        (self.bundle / NAME).write_bytes(bad[:len(self.data)].ljust(len(self.data), b"\0"))
        self.write_manifest(files=[{"arch": "amd64", "file": NAME, "size": len(self.data),
                                    "sha256": hashlib.sha256(bad).hexdigest()}])
        self.assertEqual(self.code(lambda: sb.install_from_bundle(lambda e: None, arch="amd64")), "sb_bundle_arch")
        self.write_manifest()                    # manifest honest, archive still wrong
        self.assertEqual(self.code(lambda: sb.install_from_bundle(lambda e: None, arch="amd64")), "sb_checksum")
        self.assertFalse(Path(sb.managed_path()).exists(), "nothing installed")

    def test_clear_errors(self):
        self.write_manifest(version="1.0.0")
        self.assertEqual(self.code(lambda: sb.read_bundle(str(self.bundle), "amd64")), "sb_bundle_version")
        self.write_manifest()
        self.assertEqual(self.code(lambda: sb.read_bundle(str(self.bundle), "arm64")), "sb_bundle_arch")
        (self.bundle / NAME).write_bytes(self.data[:-1])
        self.assertEqual(self.code(lambda: sb.read_bundle(str(self.bundle), "amd64")), "sb_bundle_bad")
        (self.bundle / "manifest.json").unlink()
        self.assertEqual(self.code(lambda: sb.install_from_bundle(lambda e: None, arch="amd64")), "sb_bundle_missing")
        (self.bundle / "manifest.json").write_text("{", encoding="utf-8")
        self.assertEqual(self.code(lambda: sb.read_bundle(str(self.bundle), "amd64")), "sb_bundle_bad")

    def test_find_bundle_reports_why_a_place_was_skipped(self):
        self.write_manifest(version="1.0.0")
        bundle, reasons = sb.find_bundle("amd64")
        self.assertIsNone(bundle)
        self.assertIn("sb_bundle_version", reasons[0])

    def test_system_install_requires_root(self):
        if not hasattr(os, "geteuid"):
            self.skipTest("POSIX only")
        if os.geteuid() == 0:
            self.skipTest("running as root")
        self.assertEqual(self.code(lambda: sb.install_system_from_bundle(str(self.bundle), "amd64")), "sb_bundle_root")

    def test_system_stdin_uses_pinned_bytes_and_preserves_working_binary_on_error(self):
        target = self.bundle / "system" / "sing-box"
        with mock.patch.object(sb.os, "geteuid", return_value=0, create=True):
            result = sb.install_system_from_stream(io.BytesIO(self.data), arch="amd64", target=str(target))
            self.assertEqual(result["sha256"], self.sha)
            binary = target.read_bytes()
            for payload, code in ((self.data[:-1], "sb_bundle_bad"), (self.data + b"x", "sb_bundle_bad"),
                                  (b"x" * len(self.data), "sb_checksum")):
                self.assertEqual(self.code(lambda: sb.install_system_from_stream(io.BytesIO(payload), "amd64", str(target))), code)
                self.assertEqual(target.read_bytes(), binary)
            self.assertEqual(list(target.parent.iterdir()), [target])

    def test_shipped_lock_is_valid_and_pins_fedora_x86_64(self):
        lock = sb.load_lock(str(ROOT / "src/scripts/system/serp_vpn_singbox.lock.json"))
        self.assertIn("amd64", lock["assets"])
        self.assertTrue(lock["source"].startswith("https://github.com/SagerNet/sing-box/releases/tag/v"))
        self.assertEqual(lock["assets"]["amd64"]["name"], f"sing-box-{lock['version']}-linux-amd64.tar.gz")


class ServiceTest(unittest.TestCase):
    """serp_vpn.singbox_install picks the bundle first and never falls back to the network with --offline."""

    def setUp(self):
        import serp_vpn
        self.vpn = serp_vpn
        self.calls = []
        fake = mock.Mock()
        fake.SingboxError = sb.SingboxError
        fake.install = lambda emit: self.calls.append("online") or {"path": "/x/sing-box"}
        fake.install_from_bundle = lambda emit, folder=None: self.calls.append(("bundle", folder)) or {"path": "/x/sing-box"}
        self.fake = fake
        for target, value in (("_singbox_module", lambda: fake), ("vpn_running", lambda: False),
                              ("load_settings", lambda: {}), ("save_settings", lambda s: None)):
            p = mock.patch.object(serp_vpn, target, value)
            p.start()
            self.addCleanup(p.stop)

    def test_auto_uses_a_found_bundle(self):
        self.fake.find_bundle = lambda: ({"dir": "/b"}, [])
        self.vpn.singbox_install(False)
        self.assertEqual(self.calls, [("bundle", None)])

    def test_auto_downloads_only_without_a_bundle(self):
        self.fake.find_bundle = lambda: (None, [])
        self.vpn.singbox_install(False)
        self.assertEqual(self.calls, ["online"])

    def test_offline_never_downloads(self):
        self.fake.find_bundle = lambda: (None, [])
        self.vpn.singbox_install(False, "bundle")
        self.assertEqual(self.calls, [("bundle", None)])
        self.vpn.singbox_install(False, "auto", "/chosen")
        self.assertEqual(self.calls[-1], ("bundle", "/chosen"))

    def test_incompatible_bundle_is_reported_without_network_fallback(self):
        self.fake.find_bundle = lambda: (None, ["sb_bundle_version"])
        self.vpn.singbox_install(False)
        self.assertEqual(self.calls, [("bundle", None)])

    def test_tun_install_reuses_ready_system_and_otherwise_uses_offline_helper(self):
        ready = {"binaryReady": True, "path": "/usr/bin/sing-box", "version": VERSION, "packages": [], "error": ""}
        result = {"ok": True, "path": "/usr/local/bin/sing-box", "version": VERSION}
        with mock.patch.object(self.vpn, "setup_status", return_value=ready), \
             mock.patch.object(self.vpn, "tun_state", return_value="inactive"), \
             mock.patch.object(self.vpn, "install_offline_system_engine", return_value=result) as install, \
             mock.patch.object(self.vpn, "load_settings_readonly", return_value={}):
            self.assertTrue(self.vpn.singbox_install(False, "bundle", system=True)["reused"])
            install.assert_not_called()
            ready["binaryReady"] = False
            self.assertEqual(self.vpn.singbox_install(False, "bundle", "/usb", system=True), result)
            self.assertEqual(install.call_args.args[0], "/usb")
            ready["packages"] = ["nftables"]
            with self.assertRaises(self.vpn.VpnError) as error:
                self.vpn.singbox_install(False, "bundle", "/usb", system=True)
            self.assertEqual(error.exception.code, "sb_bundle_deps")
        self.assertEqual(self.calls, [])

    def test_offline_system_helper_receives_archive_as_unprivileged_stdin(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "asset.tar.gz"
            path.write_bytes(b"fixture")
            self.fake.require_bundle.return_value = {"archive": str(path)}
            self.fake.open_archive = sb.open_archive

            def helper(args, _emit, **options):
                self.assertEqual(args, ["pkexec", "--disable-internal-agent", self.vpn.PACKAGE_HELPER, "offline-engine"])
                self.assertEqual(options["stdin"].read(), b"fixture")
                return 0, '{"event":"started"}\n{"ok":true,"path":"/usr/local/bin/sing-box"}\n'

            with mock.patch.object(self.vpn, "_executable", return_value=True), \
                 mock.patch.object(self.vpn, "_tool", return_value="pkexec"), \
                 mock.patch.object(self.vpn, "_run_packages", side_effect=helper):
                result = self.vpn.install_offline_system_engine("/usb", lambda event: None)
        self.assertTrue(result["verified"])
        self.assertEqual(result["source"], "bundle")

    def test_messages_exist_in_both_languages(self):
        for code in ("sb_bundle_missing", "sb_bundle_bad", "sb_bundle_version", "sb_bundle_arch",
                     "sb_bundle_lock", "sb_bundle_root"):
            en, ru = self.vpn.MESSAGES[code]
            self.assertTrue(en and ru, code)


class BuildScriptTest(unittest.TestCase):
    def test_a_download_that_differs_from_the_lock_builds_nothing(self):
        sys.path.insert(0, str(ROOT / "packaging/vpn-bundle"))
        import build_vpn_bundle as build
        with tempfile.TemporaryDirectory() as tmp:
            cache, out = Path(tmp) / "cache", Path(tmp) / "out"
            cache.mkdir()
            lock = {"version": VERSION, "source": "x", "assets": {"amd64": {
                "name": NAME, "size": 10, "sha256": "0" * 64}}}
            with mock.patch.object(build, "fetch", lambda url, dest: Path(dest).write_bytes(b"x" * 10)):
                with self.assertRaises(SystemExit):
                    build.build_bundle(lock, ["amd64"], out, cache, False)
            self.assertFalse((cache / NAME).exists(), "a bad download is not kept in the cache")
            self.assertFalse((out / "manifest.json").exists())

    def test_downloads_only_from_the_official_release_url(self):
        sys.path.insert(0, str(ROOT / "packaging/vpn-bundle"))
        import build_vpn_bundle as build
        self.assertTrue(build.DOWNLOAD.startswith("https://github.com/SagerNet/sing-box/releases/download/"))

    def test_offline_build_writes_linux_package_lists_and_checksums(self):
        sys.path.insert(0, str(ROOT / "packaging/vpn-bundle"))
        import build_vpn_bundle as build
        with tempfile.TemporaryDirectory() as tmp:
            cache, out = Path(tmp) / "cache", Path(tmp) / "out"
            (cache / "fedora45").mkdir(parents=True)

            def cached(parent, name, data):
                (parent / name).write_bytes(data)
                return {"name": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}

            engine = cached(cache, NAME, archive_bytes())
            rpm = cached(cache / "fedora45", "iproute-test.rpm", b"fixture")
            lock = {"version": VERSION, "source": "test", "assets": {"amd64": engine}}
            fedora = {"source": "https://test.invalid/", "rpms": [{**rpm, "package": "iproute"}]}
            with mock.patch.object(build, "fetch", side_effect=AssertionError("network used")):
                build.build_bundle(lock, ["amd64"], out, cache, False, fedora, offline=True)
            self.assertEqual((out / "rpms/packages.tsv").read_bytes(), b"iproute\tiproute-test.rpm\n")
            self.assertNotIn(b"\r", (out / "SHA256SUMS").read_bytes())


if __name__ == "__main__":
    unittest.main()
