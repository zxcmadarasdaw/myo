"""VPN Control Studio backend: subscriptions, sing-box download/choice, exit IP check. Offline.

    python3 install/tests/vpn_studio_backend_test.py

Reuses the fixtures of vpn_test.py (temporary dirs, fake sing-box, local subscription
server). The sing-box "GitHub" is a local HTTP server that serves a release JSON and a
tar.gz; it can drop the connection half-way (the client must resume with Range), ignore
Range, serve a wrong checksum or an archive with hostile member names. Nothing goes to
the network.
"""
import hashlib
import http.server
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tarfile
import threading
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

spec = importlib.util.spec_from_file_location("vpn_test", HERE / "vpn_test.py")
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
vpn = base.vpn
sb = vpn._singbox_module()
POSIX = os.name == "posix"


def serve(sub, body, code=200):
    sub.code = code
    sub.body = body.encode() if isinstance(body, str) else body


class Subscriptions(unittest.TestCase):
    def setUp(self):
        self.env = base.Env()
        self.sub = base.SubServer()

    def tearDown(self):
        self.sub.close()
        self.env.close()

    def test_add_list_rename_use_remove(self):
        serve(self.sub, base.B64_LIST)
        a = vpn.sub_add(self.sub.url("TOKEN-A"), "Home")
        self.assertTrue(a["ok"])
        self.assertEqual(len(a["items"]), 1)
        self.assertEqual(a["items"][0]["name"], "Home")
        self.assertTrue(a["items"][0]["active"])
        self.assertEqual(a["servers"], len(base.LINKS))

        serve(self.sub, base.VLESS_REALITY + "\n")
        b = vpn.sub_add(self.sub.url("TOKEN-B"))
        self.assertEqual([it["active"] for it in b["items"]], [False, True])     # the new one is active
        self.assertEqual(b["items"][1]["host"], "127.0.0.1")                     # host only, never the link
        self.assertEqual(len(vpn._servers()), 1)
        listed = json.dumps(vpn.subs_list())
        self.assertNotIn("TOKEN-A", listed)
        self.assertNotIn("TOKEN-B", listed)
        self.assertNotIn("TOKEN", json.dumps(vpn.status()))
        self.assertNotIn("TOKEN", self.env.all_text())
        self.assertEqual(vpn.status()["subscription"], b["items"][1]["name"])

        r = vpn.sub_rename(b["added"], "  Work   VPN ")
        self.assertEqual(r["items"][1]["name"], "Work VPN")
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.sub_rename(b["added"], "\x07")
        self.assertEqual(ctx.exception.code, "sub_bad_name")

        serve(self.sub, base.B64_LIST)
        u = vpn.sub_use(a["added"])
        self.assertTrue(u["items"][0]["active"])
        self.assertEqual(len(vpn._servers()), len(base.LINKS))
        self.assertIn("TOKEN-A", Path(self.env.cfg, "source").read_text(encoding="utf-8"))
        lu = u["items"][0]["lastUpdate"]
        self.assertTrue(lu["ok"] and lu["servers"] == len(base.LINKS) and lu["time"] > 0, lu)

        serve(self.sub, base.VLESS_REALITY + "\n")
        rm = vpn.sub_remove(a["added"])                                   # the active one
        self.assertEqual([it["id"] for it in rm["items"]], [b["added"]])
        self.assertTrue(rm["items"][0]["active"])
        self.assertEqual(len(vpn._servers()), 1)                          # the next one was loaded
        self.assertIn("TOKEN-B", Path(self.env.cfg, "source").read_text(encoding="utf-8"))
        self.assertFalse(Path(self.env.cfg, "subs", a["added"]).exists())

        vpn.sub_remove(b["added"])
        st = vpn.status()
        self.assertEqual(st["state"], "none")
        self.assertFalse(st["hasConfig"])
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.sub_use("deadbeef")
        self.assertEqual(ctx.exception.code, "sub_unknown")
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.sub_use("../../x")                                          # never a path
        self.assertEqual(ctx.exception.code, "sub_unknown")

    def test_failed_add_keeps_nothing_and_the_old_one_works(self):
        serve(self.sub, base.B64_LIST)
        a = vpn.sub_add(self.sub.url("GOOD"), "Good")
        cfg_before = Path(self.env.state, "config.json").read_text(encoding="utf-8")
        last_before = Path(self.env.state, "last_update.json").read_text(encoding="utf-8")
        serve(self.sub, "<html><body>login</body></html>")
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.sub_add(self.sub.url("BAD"), "Bad")
        self.assertEqual(ctx.exception.code, "html")
        d = vpn.subs_list()
        self.assertEqual([it["id"] for it in d["items"]], [a["added"]])
        self.assertTrue(d["items"][0]["active"])
        self.assertEqual(len(os.listdir(Path(self.env.cfg, "subs"))), 1)
        self.assertIn("GOOD", Path(self.env.cfg, "source").read_text(encoding="utf-8"))
        self.assertEqual(Path(self.env.state, "config.json").read_text(encoding="utf-8"), cfg_before)
        self.assertEqual(Path(self.env.state, "last_update.json").read_text(encoding="utf-8"), last_before)
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.sub_add("happ://crypt/abc")
        self.assertEqual(ctx.exception.code, "happ_encrypted")
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.sub_add("   ")
        self.assertEqual(ctx.exception.code, "empty")

    def test_failed_switch_rolls_back(self):
        serve(self.sub, base.B64_LIST)
        a = vpn.sub_add(self.sub.url("A"), "A")
        serve(self.sub, base.VLESS_REALITY + "\n")
        b = vpn.sub_add(self.sub.url("B"), "B")
        self.sub.code = 503
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.sub_use(a["added"])
        self.assertEqual(ctx.exception.code, "fetch_http")
        d = vpn.subs_list()
        self.assertEqual(d["active"], b["added"])                          # still B
        self.assertEqual(len(vpn._servers()), 1)
        self.assertIn("/B", Path(self.env.cfg, "source").read_text(encoding="utf-8"))

    def test_legacy_single_link_is_migrated(self):
        vpn.write_private(os.path.join(self.env.cfg, "source"), base.LINK_LIST)
        self.assertEqual(vpn.status()["subscription"], "")                 # status creates nothing
        self.assertFalse(Path(self.env.cfg, "subscriptions.json").exists())
        d = vpn.subs_list()
        self.assertEqual(len(d["items"]), 1)
        self.assertEqual(d["items"][0]["kind"], "links")
        self.assertEqual(d["items"][0]["count"], len(base.LINKS))
        self.assertTrue(d["items"][0]["name"])

    @unittest.skipUnless(POSIX, "file modes")
    def test_link_files_are_private(self):
        serve(self.sub, base.B64_LIST)
        a = vpn.sub_add(self.sub.url("X"))
        for p in (Path(self.env.cfg, "subs", a["added"]), Path(self.env.cfg, "subscriptions.json")):
            self.assertEqual(stat.S_IMODE(os.stat(p).st_mode), 0o600, p)

    def test_clear_forgets_all(self):
        serve(self.sub, base.B64_LIST)
        vpn.sub_add(self.sub.url("A"))
        vpn.sub_add(self.sub.url("B"))
        vpn.clear()
        self.assertFalse(Path(self.env.cfg, "subs").exists())
        self.assertEqual(vpn.subs_list()["items"], [])

    def test_cli_sub_add_reads_the_link_from_stdin(self):
        serve(self.sub, base.B64_LIST)
        p = subprocess.run([sys.executable, str(base.SCRIPT), "sub-add", "--name=Cli name", "--json"],
                           input=self.sub.url("CLI-TOKEN") + "\n", capture_output=True, text=True, encoding="utf-8",
                           env=os.environ.copy(), timeout=60)
        data = json.loads(p.stdout.strip().splitlines()[-1])
        self.assertTrue(data["ok"], p.stdout + p.stderr)
        self.assertEqual(data["items"][0]["name"], "Cli name")
        self.assertNotIn("CLI-TOKEN", p.stdout + p.stderr)


# ---- fake GitHub for sing-box ----------------------------------------------------------------

FAKE_BIN = "#!/bin/sh\necho 'sing-box version 1.12.9'\necho ''\necho 'Environment: go1.24.6 linux/amd64'\n"


def make_tar(members):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for name, data in members:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o755
            tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


class FakeGithub:
    def __init__(self):
        self.version = "1.12.9"
        self.archive = make_tar([("sing-box-1.12.9-linux-amd64/LICENSE", b"GPL"),
                                 ("sing-box-1.12.9-linux-amd64/sing-box", FAKE_BIN.encode())])
        self.digest = "sha256:" + hashlib.sha256(self.archive).hexdigest()
        self.api_code = 200
        self.drop_after = 0          # >0: the first archive request is cut after this many bytes
        self.ignore_range = False
        self.requests = []
        outer = self

        class H(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def do_GET(self):
                outer.requests.append((self.path, self.headers.get("Range", "")))
                if self.path.startswith("/api"):
                    if outer.api_code != 200:
                        self.send_response(outer.api_code)
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return
                    name = f"sing-box-{outer.version}-linux-amd64.tar.gz"
                    body = json.dumps({"tag_name": "v" + outer.version, "assets": [
                        {"name": "sing-box-1.12.9-linux-arm64.tar.gz", "size": 1,
                         "browser_download_url": outer.url("/dl/other"), "digest": "sha256:" + "0" * 64},
                        {"name": name, "size": len(outer.archive), "browser_download_url": outer.url("/dl/" + name),
                         "digest": outer.digest}]}).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                    return
                if not self.path.startswith("/dl/"):
                    self.send_response(404)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                data = outer.archive
                rng = self.headers.get("Range", "")
                start = 0
                if rng.startswith("bytes=") and not outer.ignore_range:
                    start = int(rng[6:].split("-")[0])
                    self.send_response(206)
                    self.send_header("Content-Range", f"bytes {start}-{len(data) - 1}/{len(data)}")
                else:
                    self.send_response(200)
                part = data[start:]
                self.send_header("Content-Length", str(len(part)))
                self.end_headers()
                if outer.drop_after and start == 0:
                    self.wfile.write(part[:outer.drop_after])
                    self.wfile.flush()
                    outer.drop_after = 0
                    self.close_connection = True
                    self.connection.shutdown(2)
                    return
                self.wfile.write(part)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def url(self, path):
        return f"http://127.0.0.1:{self.server.server_address[1]}{path}"

    def close(self):
        self.server.shutdown()
        self.server.server_close()


class SingboxInstall(unittest.TestCase):
    def setUp(self):
        self.env = base.Env()
        self.gh = FakeGithub()
        self.bindir = os.path.join(self.env.tmp, "bin")
        self.saved = {k: os.environ.get(k) for k in ("SERP_VPN_BIN_DIR", "SERP_VPN_SINGBOX_API", "SERP_VPN_SINGBOX_PAGE")}
        os.environ["SERP_VPN_BIN_DIR"] = self.bindir
        os.environ["SERP_VPN_SINGBOX_API"] = self.gh.url("/api/latest")
        os.environ["SERP_VPN_SINGBOX_PAGE"] = self.gh.url("/nowhere")
        self.events = []
        self.orig_sleep = sb.time.sleep
        sb.time.sleep = lambda s: None
        self.orig_probe = sb.probe
        if not POSIX:                     # the fake binary is a shell script: accept it on Windows
            sb.probe = lambda path, timeout=10: {"ok": os.path.isfile(path), "version": "1.12.9", "error": ""}

    def tearDown(self):
        sb.time.sleep = self.orig_sleep
        sb.probe = self.orig_probe
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.gh.close()
        self.env.close()

    def install(self):
        return sb.install(self.events.append, arch="amd64")

    def test_install_verifies_and_reports_progress(self):
        r = self.install()
        self.assertTrue(r["ok"])
        self.assertTrue(r["verified"])
        self.assertEqual(r["version"], "1.12.9")
        self.assertEqual(r["path"], os.path.join(self.bindir, "sing-box"))
        self.assertEqual(Path(r["path"]).read_text(), FAKE_BIN)
        stages = [e["stage"] for e in self.events if e["event"] == "stage"]
        self.assertEqual(stages, ["release", "download", "verify", "extract", "test"])
        prog = [e for e in self.events if e["event"] == "progress"]
        self.assertTrue(prog and prog[-1]["done"] == prog[-1]["total"] == len(self.gh.archive), prog[-1:])
        self.assertEqual(sorted(os.listdir(self.bindir)), ["sing-box"])      # no temp files left
        if POSIX:
            self.assertEqual(stat.S_IMODE(os.stat(r["path"]).st_mode), 0o755)

    def test_resume_after_a_dropped_connection(self):
        self.gh.drop_after = len(self.gh.archive) // 2
        r = self.install()
        self.assertTrue(r["ok"])
        ranges = [rg for path, rg in self.gh.requests if path.startswith("/dl/")]
        self.assertEqual(ranges[0], "")
        self.assertTrue(ranges[1].startswith("bytes=") and ranges[1] != "bytes=0-", ranges)
        self.assertTrue(any(e["event"] == "retry" for e in self.events))

    def test_server_ignoring_range_starts_over(self):
        self.gh.drop_after = 10
        self.gh.ignore_range = True
        self.assertTrue(self.install()["ok"])

    def test_checksum_mismatch_installs_nothing(self):
        self.gh.digest = "sha256:" + "a" * 64
        with self.assertRaises(sb.SingboxError) as ctx:
            self.install()
        self.assertEqual(ctx.exception.code, "sb_checksum")
        self.assertFalse(os.path.exists(os.path.join(self.bindir, "sing-box")))
        self.assertEqual(os.listdir(self.bindir), [])

    def test_only_the_binary_is_taken_from_the_archive(self):
        self.gh.archive = make_tar([("../../evil", b"x"), ("/etc/passwd-test", b"x"),
                                    ("sing-box-1.12.9-linux-amd64/sing-box", FAKE_BIN.encode())])
        self.gh.digest = "sha256:" + hashlib.sha256(self.gh.archive).hexdigest()
        self.assertTrue(self.install()["ok"])
        self.assertFalse(os.path.exists(os.path.join(self.env.tmp, "evil")))
        self.assertEqual(sorted(os.listdir(self.bindir)), ["sing-box"])

    def test_archive_without_binary(self):
        self.gh.archive = make_tar([("README", b"x")])
        self.gh.digest = "sha256:" + hashlib.sha256(self.gh.archive).hexdigest()
        with self.assertRaises(sb.SingboxError) as ctx:
            self.install()
        self.assertEqual(ctx.exception.code, "sb_bad_archive")

    def test_api_down_and_no_page_reports_the_reason(self):
        self.gh.api_code = 500
        with self.assertRaises(sb.SingboxError) as ctx:
            self.install()
        self.assertEqual(ctx.exception.code, "sb_http")

    def test_offline_is_a_clear_error(self):
        import socket
        import urllib.error
        closed = base.free_port()                       # nothing listens there: connection refused
        os.environ["SERP_VPN_SINGBOX_API"] = f"http://127.0.0.1:{closed}/api"
        os.environ["SERP_VPN_SINGBOX_PAGE"] = f"http://127.0.0.1:{closed}/page"
        saved = {k: os.environ.pop(k, None) for k in ("http_proxy", "HTTP_PROXY", "https_proxy", "HTTPS_PROXY")}
        os.environ["no_proxy"] = "127.0.0.1"
        try:
            with self.assertRaises(sb.SingboxError) as ctx:
                self.install()
        finally:
            os.environ.pop("no_proxy", None)
            for k, v in saved.items():
                if v is not None:
                    os.environ[k] = v
        self.assertEqual(ctx.exception.code, "sb_unreachable")
        # a failed DNS lookup (no network at all) and a stall have their own messages
        self.assertEqual(sb._net_error(urllib.error.URLError(socket.gaierror(-2, "Name or service not known"))).code,
                         "sb_offline")
        self.assertEqual(sb._net_error(urllib.error.URLError(socket.timeout("timed out"))).code, "sb_timeout")
        self.assertTrue(vpn.msg("sb_offline").startswith("No internet connection"))

    def test_architectures(self):
        self.assertEqual(sb.arch_name("x86_64"), "amd64")
        self.assertEqual(sb.arch_name("aarch64"), "arm64")
        self.assertEqual(sb.arch_name("sparc"), "")
        orig = sb.arch_name
        sb.arch_name = lambda machine=None: ""
        try:
            with self.assertRaises(sb.SingboxError) as ctx:
                sb.install(self.events.append)
            self.assertEqual(ctx.exception.code, "sb_arch")
        finally:
            sb.arch_name = orig

    @unittest.skipUnless(POSIX, "the CLI runs the real probe; the fake binary is a shell script")
    def test_cli_install_streams_json_lines_and_saves_the_choice(self):
        p = subprocess.run([sys.executable, str(base.SCRIPT), "singbox-install", "--json"], capture_output=True,
                           text=True, env=dict(os.environ), timeout=120)
        lines = [json.loads(line) for line in p.stdout.strip().splitlines()]
        self.assertTrue(lines[-1]["ok"], p.stdout + p.stderr)
        self.assertTrue(any(e.get("event") == "progress" for e in lines[:-1]))
        self.assertEqual(vpn.load_settings()["singboxPath"], os.path.join(self.bindir, "sing-box"))


class SingboxChoice(unittest.TestCase):
    def setUp(self):
        self.env = base.Env()
        self.fake = os.environ["SERP_VPN_SINGBOX"]
        os.environ.pop("SERP_VPN_SINGBOX")                 # use the real lookup rules
        self.saved_path = os.environ.get("PATH", "")
        os.environ["PATH"] = os.path.join(self.env.tmp, "empty-path")
        self.saved_bin = os.environ.get("SERP_VPN_BIN_DIR")
        os.environ["SERP_VPN_BIN_DIR"] = os.path.join(self.env.tmp, "managed")

    def tearDown(self):
        os.environ["PATH"] = self.saved_path
        os.environ["SERP_VPN_SINGBOX"] = self.fake
        if self.saved_bin is None:
            os.environ.pop("SERP_VPN_BIN_DIR", None)
        else:
            os.environ["SERP_VPN_BIN_DIR"] = self.saved_bin
        self.env.close()

    def test_nothing_found_means_missing(self):
        self.assertEqual(vpn.singbox_location(), ("", ""))
        info = vpn.singbox_info()
        self.assertFalse(info["works"])
        self.assertEqual(info["path"], "")

    def test_choose_a_file(self):
        info = vpn.singbox_use(self.fake)
        self.assertTrue(info["works"], info)
        self.assertEqual(info["source"], "chosen")
        self.assertEqual(info["path"], os.path.realpath(self.fake))
        self.assertEqual(vpn.singbox_location()[1], "chosen")
        info = vpn.singbox_use("")                       # back to automatic
        self.assertEqual(info["path"], "")

    def test_a_file_that_is_not_singbox_is_refused(self):
        bogus = os.path.join(self.env.tmp, "not-singbox.cmd" if not POSIX else "not-singbox")
        Path(bogus).write_text("@echo hello\n" if not POSIX else "#!/bin/sh\necho hello\n")
        os.chmod(bogus, 0o755)
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.singbox_use(bogus)
        self.assertEqual(ctx.exception.code, "sb_bad_path")
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.singbox_use(os.path.join(self.env.tmp, "nope"))
        self.assertEqual(ctx.exception.code, "sb_bad_path")
        self.assertEqual(vpn.load_settings()["singboxPath"], "")

    def test_managed_binary_is_the_last_fallback(self):
        managed = vpn.managed_singbox()
        os.makedirs(os.path.dirname(managed))
        Path(managed).write_text("#!/bin/sh\n")
        os.chmod(managed, 0o755)
        self.assertEqual(vpn.singbox_location(), (managed, "managed"))


class ExitIp(unittest.TestCase):
    def setUp(self):
        self.env = base.Env()
        self.answer = {"ip": "203.0.113.50", "country": "de", "city": "Frankfurt"}
        outer = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                body = json.dumps(outer.answer).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        os.environ["SERP_VPN_IP_SERVICES"] = f"http://127.0.0.1:{self.server.server_address[1]}/json"
        self.orig = vpn.tun_state

    def tearDown(self):
        vpn.tun_state = self.orig
        os.environ.pop("SERP_VPN_IP_SERVICES", None)
        self.server.shutdown()
        self.server.server_close()
        self.env.close()

    def test_refuses_when_not_connected(self):
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.ipcheck()
        self.assertEqual(ctx.exception.code, "not_connected")

    def test_reads_ip_and_country_through_the_tunnel(self):
        vpn.tun_state = lambda: "active"
        r = vpn.ipcheck()
        self.assertEqual((r["ip"], r["country"], r["via"]), ("203.0.113.50", "DE", "tun"))
        self.assertTrue(r["flag"])
        self.assertTrue(Path(self.env.state, "ipcheck.json").exists())

    def test_garbage_answer_is_an_error_not_a_fake_ip(self):
        vpn.tun_state = lambda: "active"
        self.answer = {"ip": "not an ip", "country": "Germany!"}
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.ipcheck()
        self.assertEqual(ctx.exception.code, "ip_failed")


class Messages(unittest.TestCase):
    def test_every_new_code_has_both_languages(self):
        for code in ("sub_unknown", "sub_bad_name", "not_connected", "ip_failed", "sb_offline", "sb_timeout", "sb_tls",
                     "sb_unreachable", "sb_http", "sb_no_release", "sb_no_asset", "sb_arch", "sb_too_large",
                     "sb_incomplete", "sb_checksum", "sb_bad_archive", "sb_not_working", "sb_bad_path"):
            en, ru = vpn.MESSAGES[code]
            self.assertTrue(en and ru and en != ru, code)

    def test_backend_rules_still_hold(self):
        for f in ("serp_vpn.py", "serp_vpn_singbox.py"):
            src = (ROOT / "src/scripts/system" / f).read_text(encoding="utf-8")
            self.assertNotIn("shell=True", src, f)
            self.assertNotIn("0.0.0.0", src, f)
            self.assertNotIn("sudo ", src.replace("sudo dnf", ""), f)
            self.assertNotIn("extractall", src, f)


if __name__ == "__main__":
    unittest.main(verbosity=1)
