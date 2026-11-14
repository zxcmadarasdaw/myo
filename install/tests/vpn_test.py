"""VPN subscription client (src/scripts/system/serp_vpn.py), offline.

    python3 install/tests/vpn_test.py

All fixtures are invented (example.com hosts, made-up UUIDs and keys); nothing
goes to the network. A subscription "download" is served by a local HTTP server
on 127.0.0.1. sing-box is replaced by a small fake (`check`, `version`, and on
Linux `run` with a minimal Clash API), so config generation, the "replace only
after a successful check" rule, connect/select/ping/disconnect and the user
messages are tested without sing-box. When a real sing-box is installed, the
generated configs are additionally run through the real `sing-box check`.
"""
import base64
import http.server
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "src/scripts/system/serp_vpn.py"
POSIX = os.name == "posix"

spec = importlib.util.spec_from_file_location("serp_vpn", SCRIPT)
vpn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vpn)

try:
    import yaml  # noqa: F401
    HAVE_YAML = True
except ImportError:
    HAVE_YAML = False

# ---- fixtures (all invented) -----------------------------------------------------------

UUID1 = "11111111-2222-4333-8444-555555555555"
UUID2 = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"

VLESS_REALITY = (f"vless://{UUID1}@de1.example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality"
                 "&sni=www.example.org&fp=chrome&pbk=FAKEPUBLICKEYFAKEPUBLICKEYFAKEPUBLICKEY123&sid=0a1b2c&type=tcp"
                 "#%F0%9F%87%A9%F0%9F%87%AA%20Germany%201")
VLESS_WS = (f"vless://{UUID1}@nl.example.com:8443?security=tls&type=ws&host=cdn.example.com"
            "&path=%2Fws%3Fed%3D2048&sni=cdn.example.com#Нидерланды%20WS")
VMESS_JSON = {"v": "2", "ps": "🇺🇸 US West", "add": "us.example.com", "port": "443", "id": UUID2, "aid": "0",
              "scy": "auto", "net": "ws", "type": "none", "host": "us.example.com", "path": "/vm", "tls": "tls",
              "sni": "us.example.com"}
VMESS = "vmess://" + base64.b64encode(json.dumps(VMESS_JSON).encode()).decode()
TROJAN = "trojan://secret-pass@jp.example.com:443?security=tls&type=grpc&serviceName=tr-grpc&sni=jp.example.com#Tokyo%20gRPC"
SS = "ss://" + base64.urlsafe_b64encode(b"chacha20-ietf-poly1305:ss-pass").decode().rstrip("=") + "@fi.example.com:8388#Finland%20SS"
SS_LEGACY = "ss://" + base64.b64encode(b"aes-256-gcm:pw@se.example.com:8389").decode() + "#SE-legacy"
HY2 = "hysteria2://hy-pass@sg.example.com:8443/?sni=sg.example.com&obfs=salamander&obfs-password=ob#Singapore%20HY2"
HY2_SHORT = "hy2://pw2@203.0.113.7:9443?insecure=1#Server%20NO%20limit"
TUIC = f"tuic://{UUID2}:tuic-pass@kz.example.com:443?congestion_control=bbr&alpn=h3&sni=kz.example.com#Алматы%20TUIC"
XHTTP = f"vless://{UUID1}@x.example.com:443?security=tls&type=xhttp&path=%2Fx#XHTTP%20node"

LINKS = [VLESS_REALITY, VLESS_WS, VMESS, TROJAN, SS, SS_LEGACY, HY2, HY2_SHORT, TUIC]
LINK_LIST = "\n".join(LINKS) + "\n"
B64_LIST = base64.b64encode(LINK_LIST.encode()).decode()

CLASH = textwrap.dedent(f"""\
    port: 7890
    mode: rule
    proxies:
      - name: "🇬🇧 London VMess"
        type: vmess
        server: gb.example.com
        port: 443
        uuid: {UUID2}
        alterId: 0
        cipher: auto
        tls: true
        servername: gb.example.com
        network: ws
        ws-opts:
          path: /vm
          headers:
            Host: gb.example.com
      - name: "PL Reality"
        type: vless
        server: pl.example.com
        port: 443
        uuid: {UUID1}
        flow: xtls-rprx-vision
        tls: true
        servername: www.example.org
        client-fingerprint: chrome
        reality-opts:
          public-key: FAKEPUBLICKEYFAKEPUBLICKEYFAKEPUBLICKEY123
          short-id: "0a1b"
      - name: "Trojan Paris"
        type: trojan
        server: fr.example.com
        port: 443
        password: tpw
        sni: fr.example.com
      - name: SS Warsaw
        type: ss
        server: 198.51.100.4
        port: 8388
        cipher: aes-128-gcm
        password: sspw
      - name: HY2 Stockholm
        type: hysteria2
        server: se.example.com
        port: 443
        password: hpw
      - name: Snell box
        type: snell
        server: sn.example.com
        port: 1
    proxy-groups:
      - name: auto
        type: url-test
        proxies: ["PL Reality"]
    """)

SINGBOX_SUB = {
    "outbounds": [
        {"type": "selector", "tag": "select", "outbounds": ["🇨🇦 Toronto", "Turkey VLESS"]},
        {"type": "vless", "tag": "🇨🇦 Toronto", "server": "ca.example.com", "server_port": 443, "uuid": UUID1,
         "tls": {"enabled": True, "server_name": "ca.example.com"}},
        {"type": "shadowsocks", "tag": "Turkey VLESS", "server": "tr.example.com", "server_port": 8388,
         "method": "aes-256-gcm", "password": "pw"},
        {"type": "wtf", "tag": "odd", "server": "x.example.com", "server_port": 1},
        {"type": "direct", "tag": "direct"},
    ]
}

# ---- fake sing-box ---------------------------------------------------------------------

FAKE_SINGBOX = r'''
import json, os, sys, http.server, threading, signal

args = sys.argv[1:]
if args[:1] == ["version"]:
    print("sing-box version 1.12.0-fake")
    sys.exit(0)
cfg_path = args[args.index("-c") + 1]
with open(cfg_path, encoding="utf-8") as f:
    cfg = json.load(f)
problems = []
for ib in cfg.get("inbounds", []):
    if ib.get("type") == "tun":
        problems.append("tun inbound")
    if ib.get("listen") != "127.0.0.1":
        problems.append("inbound not on 127.0.0.1")
ctl = cfg.get("experimental", {}).get("clash_api", {}).get("external_controller", "")
if not ctl.startswith("127.0.0.1:"):
    problems.append("clash api not on 127.0.0.1")
tags = [o.get("tag") for o in cfg.get("outbounds", [])]
if len(tags) != len(set(tags)):
    problems.append("duplicate outbound tag")
for o in cfg.get("outbounds", []):
    if o.get("type") == "selector":
        if [t for t in o.get("outbounds", []) if t not in tags]:
            problems.append("selector refers to missing outbound")
    if "server" in o and not isinstance(o.get("server_port"), int):
        problems.append("server_port is not an integer")
if os.environ.get("FAKE_SINGBOX_FAIL"):
    problems.append("forced failure")
if args[0] == "check":
    if problems:
        print("FATAL[0000] decode config at " + cfg_path + ": " + "; ".join(problems), file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
if args[0] != "run":
    sys.exit(64)
secret = cfg["experimental"]["clash_api"].get("secret", "")
port = int(ctl.split(":")[1])
selector = next(o for o in cfg["outbounds"] if o.get("type") == "selector")
state = {"now": selector.get("default") or selector["outbounds"][0]}

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def authed(self):
        if self.headers.get("Authorization") != "Bearer " + secret:
            self.reply(401, {"message": "Unauthorized"})
            return False
        return True
    def do_GET(self):
        if not self.authed():
            return
        if self.path == "/version":
            return self.reply(200, {"version": "fake"})
        if self.path == "/proxies/proxy":
            return self.reply(200, {"now": state["now"], "all": selector["outbounds"]})
        if self.path.startswith("/group/proxy/delay"):
            return self.reply(200, {t: 100 + i * 10 for i, t in enumerate(selector["outbounds"]) if i != 1})
        self.reply(404, {})
    def do_PUT(self):
        if not self.authed():
            return
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        if self.path == "/proxies/proxy" and body.get("name") in selector["outbounds"]:
            state["now"] = body["name"]
            self.send_response(204)
            self.end_headers()
            return
        self.reply(400, {})

srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), H)
signal.signal(signal.SIGTERM, lambda *a: threading.Thread(target=srv.shutdown).start())
srv.serve_forever()
'''


def make_fake_singbox(directory):
    script = Path(directory) / "fake_singbox.py"
    script.write_text(FAKE_SINGBOX, encoding="utf-8")
    if POSIX:
        # named sing-box so /proc/PID/cmdline contains "sing-box" like the real binary
        exe = Path(directory) / "sing-box"
        exe.write_text(f"#!/bin/sh\nexec '{sys.executable}' '{script}' \"$@\" sing-box\n", encoding="utf-8")
        exe.chmod(0o755)
    else:
        exe = Path(directory) / "sing-box.cmd"
        # cmd.exe reads .cmd files in the OEM code page (paths may contain non-ASCII user names)
        exe.write_text(f'@"{sys.executable}" "{script}" %*\n', encoding="oem")
    return str(exe)


def free_port():
    import socket
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class SubServer:
    """Local HTTP server that plays the subscription provider."""

    def __init__(self):
        self.body = b""
        self.code = 200
        self.headers = {}
        self.seen_ua = []
        outer = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                outer.seen_ua.append(self.headers.get("User-Agent", ""))
                self.send_response(outer.code)
                for k, v in outer.headers.items():
                    self.send_header(k, v)
                self.send_header("Content-Length", str(len(outer.body)))
                self.end_headers()
                self.wfile.write(outer.body)

        self.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        self.port = self.srv.server_address[1]
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()

    def url(self, token):
        return f"http://127.0.0.1:{self.port}/sub/{token}"

    def close(self):
        self.srv.shutdown()
        self.srv.server_close()


class Env:
    """Temporary config/state dirs and a fake (or missing) sing-box for one test."""

    def __init__(self, singbox="fake"):
        self.tmp = tempfile.mkdtemp(prefix="serp-vpn-test-")
        self.cfg = os.path.join(self.tmp, "config", "serpantinum", "vpn")
        self.state = os.path.join(self.tmp, "state", "serpantinum", "vpn")
        self.saved = {k: os.environ.get(k) for k in ("SERP_VPN_CONFIG_DIR", "SERP_VPN_STATE_DIR", "SERP_VPN_SINGBOX",
                                                     "SERP_VPN_LANG", "FAKE_SINGBOX_FAIL", "SERP_VPN_SYSTEMCTL",
                                                     "SERP_VPN_PKEXEC", "SERP_VPN_HELPER", "SERP_VPN_UNIT_FILE",
                                                     "SERP_VPN_NMCLI", "SERP_VPN_JOURNALCTL", "SERP_VPN_RESOLVECTL")}
        # never touch a real serpantinum-vpn service, pkexec or nmcli from the tests
        for k in ("SERP_VPN_SYSTEMCTL", "SERP_VPN_PKEXEC", "SERP_VPN_NMCLI", "SERP_VPN_JOURNALCTL", "SERP_VPN_RESOLVECTL"):
            os.environ[k] = ""
        os.environ["SERP_VPN_HELPER"] = os.path.join(self.tmp, "no-helper")
        os.environ["SERP_VPN_UNIT_FILE"] = os.path.join(self.tmp, "no-unit")
        os.environ["SERP_VPN_CONFIG_DIR"] = self.cfg
        os.environ["SERP_VPN_STATE_DIR"] = self.state
        os.environ["SERP_VPN_LANG"] = "en"
        os.environ.pop("FAKE_SINGBOX_FAIL", None)
        os.environ["SERP_VPN_SINGBOX"] = make_fake_singbox(self.tmp) if singbox == "fake" else ""
        ports = {"proxyPort": free_port(), "apiPort": free_port(), "probePort": free_port()}
        vpn.save_settings(dict(vpn.DEFAULT_SETTINGS, **ports, secret="test-secret"))

    def close(self):
        try:
            vpn.disconnect()
        except Exception:
            pass
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        shutil.rmtree(self.tmp, ignore_errors=True)

    def all_text(self):
        out = []
        for base in (self.cfg, self.state):
            for dirpath, _, files in os.walk(base):
                for f in files:
                    if f != "source":
                        out.append(Path(dirpath, f).read_text(encoding="utf-8", errors="replace"))
        return "\n".join(out)


def by_name(result):
    return {s["name"]: s for s in result["servers"]}


# ---- parser ----------------------------------------------------------------------------


class SingleLinks(unittest.TestCase):
    def test_vless_reality(self):
        s = vpn.parse_link(VLESS_REALITY)
        self.assertEqual((s["protocol"], s["address"], s["port"], s["country"]), ("vless", "de1.example.com", 443, "DE"))
        p = s["params"]
        self.assertEqual(p["uuid"], UUID1)
        self.assertEqual(p["flow"], "xtls-rprx-vision")
        self.assertEqual(p["tls"]["server_name"], "www.example.org")
        self.assertEqual(p["tls"]["reality"], {"enabled": True, "public_key": "FAKEPUBLICKEYFAKEPUBLICKEYFAKEPUBLICKEY123",
                                               "short_id": "0a1b2c"})
        self.assertEqual(p["tls"]["utls"]["fingerprint"], "chrome")
        self.assertNotIn("transport", p)

    def test_vless_ws_early_data(self):
        s = vpn.parse_link(VLESS_WS)
        t = s["params"]["transport"]
        self.assertEqual((t["type"], t["path"], t["max_early_data"]), ("ws", "/ws", 2048))
        self.assertEqual(t["headers"], {"Host": "cdn.example.com"})
        self.assertEqual(s["country"], "NL")          # Russian country name

    def test_vmess(self):
        s = vpn.parse_link(VMESS)
        self.assertEqual((s["protocol"], s["address"], s["port"], s["name"], s["country"]),
                         ("vmess", "us.example.com", 443, "🇺🇸 US West", "US"))
        self.assertEqual(s["params"]["transport"], {"type": "ws", "path": "/vm", "headers": {"Host": "us.example.com"}})
        self.assertTrue(s["params"]["tls"]["enabled"])

    def test_trojan_grpc(self):
        s = vpn.parse_link(TROJAN)
        self.assertEqual(s["params"]["password"], "secret-pass")
        self.assertEqual(s["params"]["transport"], {"type": "grpc", "service_name": "tr-grpc"})
        self.assertEqual(s["country"], "JP")          # city keyword

    def test_shadowsocks_sip002_and_legacy(self):
        s = vpn.parse_link(SS)
        self.assertEqual((s["protocol"], s["params"]["method"], s["params"]["password"], s["port"]),
                         ("shadowsocks", "chacha20-ietf-poly1305", "ss-pass", 8388))
        legacy = vpn.parse_link(SS_LEGACY)
        self.assertEqual((legacy["address"], legacy["port"], legacy["params"]["password"], legacy["country"]),
                         ("se.example.com", 8389, "pw", "SE"))

    def test_hysteria2(self):
        s = vpn.parse_link(HY2)
        self.assertEqual(s["params"]["obfs"], {"type": "salamander", "password": "ob"})
        self.assertEqual(s["params"]["tls"]["server_name"], "sg.example.com")
        short = vpn.parse_link(HY2_SHORT)
        self.assertEqual(short["protocol"], "hysteria2")
        self.assertTrue(short["params"]["tls"]["insecure"])
        self.assertNotIn("server_name", short["params"]["tls"])   # IP address: no SNI
        self.assertEqual(short["country"], "")                      # "NO" inside a name is not Norway

    def test_tuic(self):
        s = vpn.parse_link(TUIC)
        self.assertEqual((s["params"]["uuid"], s["params"]["password"], s["country"]), (UUID2, "tuic-pass", "KZ"))

    def test_unsupported_transport_is_explained(self):
        with self.assertRaises(vpn.Unsupported) as ctx:
            vpn.parse_link(XHTTP)
        self.assertIn("xhttp", str(ctx.exception))

    def test_ipv6(self):
        s = vpn.parse_link("trojan://pw@[2001:db8::1]:443#v6")
        self.assertEqual(s["address"], "2001:db8::1")
        self.assertNotIn("server_name", s["params"]["tls"])


class Subscriptions(unittest.TestCase):
    def test_plain_link_list(self):
        r = vpn.parse_subscription(LINK_LIST)
        self.assertEqual(r["format"], "links")
        self.assertEqual(len(r["servers"]), len(LINKS))
        self.assertEqual(r["errors"], [])

    def test_base64_list(self):
        wrapped = "\n".join(B64_LIST[i:i + 76] for i in range(0, len(B64_LIST), 76))
        urlsafe = base64.urlsafe_b64encode(LINK_LIST.encode()).decode().rstrip("=")
        for blob in (B64_LIST, urlsafe, wrapped):
            r = vpn.parse_subscription(blob)
            self.assertEqual(r["format"], "base64-links")
            self.assertEqual(len(r["servers"]), len(LINKS))

    def test_single_link_as_subscription(self):
        self.assertEqual(len(vpn.parse_subscription(VLESS_REALITY)["servers"]), 1)

    def test_bad_lines_are_reported_not_fatal(self):
        r = vpn.parse_subscription(LINK_LIST + XHTTP + "\nnot a link\nvless://broken\nfoo://x@y:1\n")
        self.assertEqual(len(r["servers"]), len(LINKS))
        errors = " ".join(e["error"] for e in r["errors"])
        self.assertIn("xhttp", errors)
        self.assertIn("foo://", errors)
        self.assertEqual(len(r["errors"]), 4)
        self.assertEqual(r["errors"][0]["name"], "XHTTP node")

    def test_singbox_json(self):
        r = vpn.parse_subscription(json.dumps(SINGBOX_SUB))
        self.assertEqual(r["format"], "sing-box")
        names = by_name(r)
        self.assertEqual(set(names), {"🇨🇦 Toronto", "Turkey VLESS"})
        self.assertEqual(names["🇨🇦 Toronto"]["country"], "CA")
        self.assertEqual(names["Turkey VLESS"]["country"], "TR")
        self.assertEqual(names["🇨🇦 Toronto"]["params"]["tls"]["server_name"], "ca.example.com")
        self.assertEqual(len(r["errors"]), 1)

    @unittest.skipUnless(HAVE_YAML, "PyYAML not installed")
    def test_clash_yaml(self):
        r = vpn.parse_subscription(CLASH)
        self.assertEqual(r["format"], "clash")
        names = by_name(r)
        self.assertEqual(len(names), 5)
        self.assertEqual(names["🇬🇧 London VMess"]["country"], "GB")
        self.assertEqual(names["🇬🇧 London VMess"]["params"]["transport"]["headers"], {"Host": "gb.example.com"})
        self.assertEqual(names["PL Reality"]["params"]["tls"]["reality"]["short_id"], "0a1b")
        self.assertEqual(names["PL Reality"]["country"], "PL")
        self.assertEqual(names["Trojan Paris"]["country"], "FR")
        self.assertEqual(names["SS Warsaw"]["protocol"], "shadowsocks")
        self.assertEqual(names["HY2 Stockholm"]["country"], "SE")
        self.assertEqual([e["name"] for e in r["errors"]], ["Snell box"])

    @unittest.skipUnless(HAVE_YAML, "PyYAML not installed")
    def test_clash_in_base64(self):
        self.assertEqual(vpn.parse_subscription(base64.b64encode(CLASH.encode()).decode())["format"], "base64-clash")

    def test_duplicate_names_get_unique_tags(self):
        r = vpn.parse_subscription("\n".join([SS, SS, SS]))
        self.assertEqual([s["tag"] for s in r["servers"]], ["Finland SS", "Finland SS #2", "Finland SS #3"])


class BrokenInput(unittest.TestCase):
    def code(self, text):
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.parse_subscription(text)
        self.assertTrue(ctx.exception.as_dict()["message"])
        return ctx.exception.code

    def test_codes(self):
        self.assertEqual(self.code(""), "empty")
        self.assertEqual(self.code("   \n﻿ "), "empty")
        self.assertEqual(self.code("<!DOCTYPE html><html><body>Login</body></html>"), "html")
        self.assertEqual(self.code("hello world, nothing here"), "unknown_format")
        self.assertEqual(self.code("bm90IGEgc3Vic2NyaXB0aW9u"), "unknown_format")      # base64 of plain text
        self.assertEqual(self.code("@@@@####"), "unknown_format")
        self.assertEqual(self.code('{"outbounds": [ {"type": '), "bad_json")
        self.assertEqual(self.code('{"log": {}}'), "bad_json")
        self.assertEqual(self.code(XHTTP), "no_servers")
        self.assertEqual(self.code("vless://\nvmess://AAAA\nss://###"), "no_servers")
        self.assertEqual(self.code(base64.b64encode(b"\xff\xfe\x00garbage").decode()), "unknown_format")

    @unittest.skipUnless(HAVE_YAML, "PyYAML not installed")
    def test_bad_yaml(self):
        self.assertEqual(self.code("proxies:\n  - name: a\n   type: [broken"), "bad_yaml")
        self.assertEqual(self.code("proxies: 5\n"), "bad_yaml")

    def test_no_servers_explains_why(self):
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.parse_subscription(XHTTP)
        self.assertIn("xhttp", ctx.exception.as_dict()["message"])

    def test_random_garbage_never_crashes(self):
        import random
        rnd = random.Random(7)
        alphabet = "abcXYZ019+/=:@?#&%{}[]\n -_" + LINK_LIST[:200]
        for _ in range(400):
            text = "".join(rnd.choice(alphabet) for _ in range(rnd.randint(0, 120)))
            for candidate in (text, "vless://" + text, "vmess://" + text, "ss://" + text, "trojan://" + text,
                              "hysteria2://" + text, "tuic://" + text):
                try:
                    vpn.parse_subscription(candidate)
                except vpn.VpnError:
                    pass

    def test_happ_and_import_links(self):
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.unwrap_source("happ://crypt3/abcdef")
        self.assertEqual(ctx.exception.code, "happ_encrypted")
        self.assertEqual(vpn.unwrap_source("hiddify://import/https://sub.example.com/x#Name"), "https://sub.example.com/x")
        self.assertEqual(vpn.unwrap_source("sing-box://import-remote-profile?url=https%3A%2F%2Fsub.example.com%2Fy#n"),
                         "https://sub.example.com/y")
        self.assertTrue(vpn.is_url("https://sub.example.com/abc"))
        self.assertFalse(vpn.is_url(LINK_LIST))


class Countries(unittest.TestCase):
    def test_detection(self):
        cases = {
            "🇩🇪 Frankfurt 1": "DE", "🇬🇧": "GB", "Germany-2": "DE", "Германия | VIP": "DE", "NL Amsterdam": "NL",
            "Нидерланды": "NL", "US-West": "US", "USA 3": "US", "Tokyo": "JP", "Лондон": "GB", "UK fast": "GB",
            "IN-Mumbai": "IN", "Mumbai": "IN", "IT-1": "IT", "Server NO limit": "", "Fast server": "",
            "Best VPN 1": "", "Финляндия 🔥": "FI", "South Korea": "KR", "Kazakhstan": "KZ", "Алматы": "KZ",
            "Türkiye": "TR", "ОАЭ": "AE", "Dubai": "AE", "Russia": "RU", "Россия": "RU", "": "",
        }
        for name, want in cases.items():
            self.assertEqual(vpn.detect_country(name), want, name)

    def test_names_and_flags(self):
        os.environ["SERP_VPN_LANG"] = "ru"
        try:
            self.assertEqual(vpn.country_name("DE"), "Германия")
        finally:
            os.environ["SERP_VPN_LANG"] = "en"
        self.assertEqual(vpn.country_name("DE"), "Germany")
        self.assertEqual(vpn.flag("de"), "🇩🇪")
        self.assertEqual(vpn.flag(""), "")


# ---- config ----------------------------------------------------------------------------


class Config(unittest.TestCase):
    def setUp(self):
        self.servers = vpn.parse_subscription(LINK_LIST)["servers"]
        self.settings = dict(vpn.DEFAULT_SETTINGS, secret="s3cr3t")

    def test_proxy_config(self):
        cfg = vpn.build_config(self.servers, self.settings)
        self.assertEqual(cfg["inbounds"], [{"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 2080}])
        self.assertEqual(cfg["experimental"]["clash_api"], {"external_controller": "127.0.0.1:9097", "secret": "s3cr3t"})
        self.assertEqual(cfg["route"], {"final": "proxy"})
        sel = cfg["outbounds"][0]
        self.assertEqual((sel["type"], sel["tag"], sel["default"]), ("selector", "proxy", self.servers[0]["tag"]))
        self.assertEqual(sel["outbounds"], [s["tag"] for s in self.servers])
        self.assertEqual(cfg["outbounds"][-1], {"type": "direct", "tag": "direct"})
        self.assertEqual(len(cfg["outbounds"]), len(self.servers) + 2)
        tags = [o["tag"] for o in cfg["outbounds"]]
        self.assertEqual(len(tags), len(set(tags)))
        for o in cfg["outbounds"][1:-1]:
            self.assertIsInstance(o["server_port"], int)
        text = json.dumps(cfg)
        self.assertNotIn('"tun"', text)
        self.assertNotIn("0.0.0.0", text)
        self.assertNotIn("auto_route", text)

    def test_selected_server_is_default(self):
        tag = self.servers[3]["tag"]
        self.assertEqual(vpn.build_config(self.servers, dict(self.settings, selected=tag))["outbounds"][0]["default"], tag)
        self.assertEqual(vpn.build_config(self.servers, dict(self.settings, selected="gone"))["outbounds"][0]["default"],
                         self.servers[0]["tag"])

    def test_probe_config_has_no_inbounds(self):
        cfg = vpn.build_config(self.servers, self.settings, mode="probe")
        self.assertEqual(cfg["inbounds"], [])
        self.assertEqual(cfg["experimental"]["clash_api"]["external_controller"], "127.0.0.1:9098")

    def test_fake_check_accepts_all_fixtures(self):
        env = Env()
        try:
            fixtures = [LINK_LIST, json.dumps(SINGBOX_SUB)] + ([CLASH] if HAVE_YAML else [])
            for text in fixtures:
                servers = vpn.parse_subscription(text)["servers"]
                ok, detail = vpn.singbox_check(vpn.build_config(servers, self.settings))
                self.assertTrue(ok, detail)
        finally:
            env.close()

    @unittest.skipUnless(shutil.which("sing-box"), "sing-box not installed: real `sing-box check` skipped")
    def test_real_singbox_check(self):
        saved = os.environ.pop("SERP_VPN_SINGBOX", None)
        try:
            fixtures = [LINK_LIST, json.dumps(SINGBOX_SUB)] + ([CLASH] if HAVE_YAML else [])
            for text in fixtures:
                servers = vpn.parse_subscription(text)["servers"]
                for mode in ("proxy", "probe"):
                    ok, detail = vpn.singbox_check(vpn.build_config(servers, self.settings, mode=mode))
                    self.assertTrue(ok, f"{mode}: {detail}")
        finally:
            if saved is not None:
                os.environ["SERP_VPN_SINGBOX"] = saved


# ---- storage and updates ---------------------------------------------------------------


class Storage(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.sub = SubServer()

    def tearDown(self):
        self.sub.close()
        self.env.close()

    def test_local_text_source(self):
        r = vpn.set_source(LINK_LIST)
        self.assertTrue(r["ok"])
        self.assertEqual(r["servers"], len(LINKS))
        st = vpn.status()
        self.assertEqual(st["state"], "disconnected")
        self.assertEqual(st["count"], len(LINKS))
        self.assertEqual(st["currentServer"]["country"], "DE")
        self.assertNotIn("params", st["currentServer"])

    @unittest.skipUnless(POSIX, "file modes are POSIX only")
    def test_modes(self):
        vpn.set_source(LINK_LIST)
        for d in (self.env.cfg, self.env.state):
            self.assertEqual(stat.S_IMODE(os.stat(d).st_mode), 0o700, d)
            for f in os.listdir(d):
                self.assertEqual(stat.S_IMODE(os.stat(os.path.join(d, f)).st_mode), 0o600, f)

    def test_url_source_and_link_never_leaks(self):
        token = "PRIVATE-TOKEN-7f3a9c"
        self.sub.body = B64_LIST.encode()
        self.sub.headers = {"Subscription-Userinfo": "upload=1; download=2; total=1000; expire=1900000000",
                            "Profile-Title": "base64:" + base64.b64encode("Мой VPN".encode()).decode()}
        r = vpn.set_source(self.sub.url(token))
        self.assertEqual(r["servers"], len(LINKS))
        self.assertEqual(r["info"]["title"], "Мой VPN")
        self.assertEqual(r["info"]["total"], 1000)
        self.assertEqual(self.sub.seen_ua[-1], "v2rayN/7.0")
        self.assertIn(token, Path(self.env.cfg, "source").read_text(encoding="utf-8"))
        self.assertNotIn(token, self.env.all_text())
        self.assertNotIn(token, json.dumps(vpn.status()))
        self.sub.code = 404
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.update()
        self.assertEqual(ctx.exception.code, "fetch_http")
        self.assertNotIn(token, json.dumps(ctx.exception.as_dict()))
        self.assertNotIn(token, self.env.all_text())

    def test_failed_update_keeps_last_working_config(self):
        self.sub.body = LINK_LIST.encode()
        vpn.set_source(self.sub.url("t"))
        cfg_before = Path(self.env.state, "config.json").read_text(encoding="utf-8")
        servers_before = Path(self.env.state, "servers.json").read_text(encoding="utf-8")
        for body, code, want in ((b"", 200, "empty"), (b"<html><body>blocked</body></html>", 200, "html"),
                                 (b"x", 500, "fetch_http"), (XHTTP.encode(), 200, "no_servers")):
            self.sub.body, self.sub.code = body, code
            with self.assertRaises(vpn.VpnError) as ctx:
                vpn.update()
            self.assertEqual(ctx.exception.code, want)
            self.assertEqual(Path(self.env.state, "config.json").read_text(encoding="utf-8"), cfg_before)
            self.assertEqual(Path(self.env.state, "servers.json").read_text(encoding="utf-8"), servers_before)
            last = json.loads(Path(self.env.state, "last_update.json").read_text(encoding="utf-8"))
            self.assertFalse(last["ok"])
            self.assertTrue(last["keptOld"])
            self.assertIn("previous working config is kept", last["message"])
        # sing-box check fails -> nothing replaced either
        self.sub.body, self.sub.code = (VMESS + "\n").encode(), 200
        os.environ["FAKE_SINGBOX_FAIL"] = "1"
        try:
            with self.assertRaises(vpn.VpnError) as ctx:
                vpn.update()
        finally:
            os.environ.pop("FAKE_SINGBOX_FAIL")
        self.assertEqual(ctx.exception.code, "check_failed")
        self.assertIn("forced failure", ctx.exception.as_dict()["message"])
        self.assertEqual(Path(self.env.state, "config.json").read_text(encoding="utf-8"), cfg_before)
        st = vpn.status()
        self.assertEqual(st["state"], "disconnected")
        self.assertIn("rejected", st["warning"])
        # a good update replaces it
        self.assertEqual(vpn.update()["servers"], 1)
        self.assertNotEqual(Path(self.env.state, "config.json").read_text(encoding="utf-8"), cfg_before)

    def test_auto_update_interval(self):
        self.assertEqual(vpn.update(auto=True)["skipped"], "no_source")
        self.sub.body = LINK_LIST.encode()
        vpn.set_source(self.sub.url("t"))
        hits = len(self.sub.seen_ua)
        self.assertEqual(vpn.update(auto=True)["skipped"], "fresh")
        self.assertEqual(len(self.sub.seen_ua), hits)
        last = Path(self.env.state, "last_update.json")
        data = json.loads(last.read_text(encoding="utf-8"))
        data["time"] -= 13 * 3600
        last.write_text(json.dumps(data), encoding="utf-8")
        self.assertTrue(vpn.update(auto=True)["ok"])
        self.assertEqual(len(self.sub.seen_ua), hits + 1)

    def test_clear(self):
        vpn.set_source(LINK_LIST)
        self.assertEqual(vpn.clear()["state"], "none")
        self.assertFalse(os.path.exists(os.path.join(self.env.cfg, "source")))
        self.assertFalse(os.path.exists(os.path.join(self.env.state, "config.json")))


class FreshUser(unittest.TestCase):
    def test_status_and_auto_update_create_nothing(self):
        tmp = tempfile.mkdtemp(prefix="serp-vpn-fresh-")
        cfg, st = os.path.join(tmp, "cfg"), os.path.join(tmp, "state")
        saved = {k: os.environ.get(k) for k in ("SERP_VPN_CONFIG_DIR", "SERP_VPN_STATE_DIR")}
        os.environ.update(SERP_VPN_CONFIG_DIR=cfg, SERP_VPN_STATE_DIR=st)
        try:
            self.assertEqual(vpn.status()["state"], "none")
            self.assertEqual(vpn.update(auto=True)["skipped"], "no_source")
            self.assertFalse(os.path.exists(cfg))
            self.assertFalse(os.path.exists(st))
        finally:
            for k, v in saved.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
            shutil.rmtree(tmp, ignore_errors=True)


class MissingSingbox(unittest.TestCase):
    def setUp(self):
        self.env = Env(singbox=None)

    def tearDown(self):
        self.env.close()

    def test_messages(self):
        self.assertEqual(vpn.status()["state"], "none")
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.set_source(LINK_LIST)
        self.assertEqual(ctx.exception.code, "no_singbox")
        self.assertIn("dnf install sing-box", ctx.exception.as_dict()["message"])
        self.assertFalse(os.path.exists(os.path.join(self.env.state, "config.json")))
        st = vpn.status()
        self.assertEqual(st["state"], "missing")
        self.assertIn("dnf install sing-box", st["error"])
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.connect()
        self.assertEqual(ctx.exception.code, "no_config")
        r = vpn.test(LINK_LIST)
        self.assertEqual(r["check"], "no_singbox")
        self.assertEqual(len(r["servers"]), len(LINKS))

    def test_russian_messages(self):
        os.environ["SERP_VPN_LANG"] = "ru_RU.UTF-8"
        self.assertIn("не установлен", vpn.msg("no_singbox"))
        self.assertIn("Подписка пустая", vpn.msg("empty"))


class Cli(unittest.TestCase):
    def setUp(self):
        self.env = Env()

    def tearDown(self):
        self.env.close()

    def run_cli(self, *args, stdin="", lang="en"):
        env = dict(os.environ, SERP_VPN_LANG=lang, PYTHONIOENCODING="utf-8")
        return subprocess.run([sys.executable, str(SCRIPT), *args], input=stdin, capture_output=True,
                              text=True, encoding="utf-8", env=env, timeout=60)

    def test_test_command_is_dry(self):
        before = sorted(os.listdir(self.env.cfg))
        p = self.run_cli("test", "-", stdin=B64_LIST)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("Format: base64-links", p.stdout)
        self.assertIn(f"Servers: {len(LINKS)}", p.stdout)
        self.assertIn("sing-box check: OK", p.stdout)
        self.assertIn("Germany", p.stdout)
        self.assertIn("Nothing was saved or started.", p.stdout)
        self.assertEqual(sorted(os.listdir(self.env.cfg)), before)
        self.assertFalse(os.path.isdir(self.env.state) and os.listdir(self.env.state))

    def test_test_command_json_and_errors(self):
        p = self.run_cli("test", "-", "--json", stdin=LINK_LIST + XHTTP)
        data = json.loads(p.stdout)
        self.assertTrue(data["ok"])
        self.assertEqual(len(data["skipped"]), 1)
        p = self.run_cli("test", "-", stdin="<html><body>x</body></html>", lang="ru_RU.UTF-8")
        self.assertEqual(p.returncode, 1)
        self.assertIn("веб-страница", p.stderr)
        self.assertNotIn("Traceback", p.stderr)

    def test_status_and_set_source(self):
        self.assertIn("State: No subscription", self.run_cli("status").stdout)
        p = self.run_cli("set-source", "--json", stdin=LINK_LIST)
        self.assertTrue(json.loads(p.stdout)["ok"], p.stdout + p.stderr)
        self.assertEqual(json.loads(self.run_cli("status", "--json").stdout)["state"], "disconnected")
        p = self.run_cli("list", "--json")
        servers = json.loads(p.stdout)["servers"]
        self.assertEqual(len(servers), len(LINKS))
        self.assertNotIn("params", servers[0])                 # no credentials in the list
        self.assertNotIn(UUID1, p.stdout)
        p = self.run_cli("select", "nope", "--json")
        self.assertEqual(json.loads(p.stdout)["error"]["code"], "unknown_server")

    def test_connect_without_subscription(self):
        p = self.run_cli("connect")
        self.assertEqual(p.returncode, 1)
        self.assertIn("No subscription", p.stderr)
        self.assertNotIn("Traceback", p.stderr)


@unittest.skipUnless(POSIX, "process control (connect/ping) is tested on Linux")
class Lifecycle(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        vpn.set_source(LINK_LIST)

    def tearDown(self):
        self.env.close()

    def test_connect_select_ping_disconnect(self):
        servers = json.loads(Path(self.env.state, "servers.json").read_text(encoding="utf-8"))
        st = vpn.connect()
        self.assertEqual(st["state"], "connected", st)
        self.assertTrue(st["proxy"].startswith("127.0.0.1:"))
        pid = vpn.running_pid()
        self.assertGreater(pid, 0)
        st = vpn.select(servers[2]["tag"])
        self.assertEqual(st["current"], servers[2]["tag"])
        cfg = json.loads(Path(self.env.state, "config.json").read_text(encoding="utf-8"))
        self.assertEqual(cfg["outbounds"][0]["default"], servers[2]["tag"])
        delays = vpn.ping()["delays"]
        self.assertEqual(delays[servers[0]["tag"]], 100)
        self.assertEqual(delays[servers[1]["tag"]], 0)       # failed test -> 0
        self.assertEqual(vpn.status()["delays"], delays)
        st = vpn.disconnect()
        self.assertEqual(st["state"], "disconnected")
        self.assertFalse(vpn._pid_alive(pid))

    def test_ping_without_connection_uses_short_lived_probe(self):
        delays = vpn.ping()["delays"]
        self.assertEqual(len(delays), len(LINKS))
        self.assertFalse(vpn.is_running())
        self.assertTrue(vpn._port_free(vpn.load_settings()["probePort"]))   # probe is gone

    def test_port_busy(self):
        import socket
        port = vpn.load_settings()["proxyPort"]
        with socket.socket() as s:
            s.bind(("127.0.0.1", port))
            s.listen()
            with self.assertRaises(vpn.VpnError) as ctx:
                vpn.connect()
        self.assertEqual(ctx.exception.code, "port_busy")


class SourceRules(unittest.TestCase):
    def test_backend_rules(self):
        src = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("0.0.0.0", src)
        self.assertNotIn('"type": "tun"', src)          # the TUN inbound is built only by the root helper
        self.assertNotIn("sudo ", src.replace("sudo dnf", ""))
        self.assertNotIn("icmp", src.lower())
        self.assertNotIn('["ping"', src)
        self.assertIn("ProxyHandler({})", src)            # Clash API never goes through a proxy

    def test_cli_wrapper_passes_link_on_stdin(self):
        wrapper = (ROOT / "bin/serpantinum").read_text(encoding="utf-8")
        start = wrapper.index('if [[ "$1" == "vpn" ]]')
        block = wrapper[start:wrapper.index("\nfi\n", start)]
        self.assertIn("serp_vpn.py", block)
        self.assertIn("test -", block)                    # the link goes on stdin to python

    def test_qml_passes_link_on_stdin(self):
        qml = (ROOT / "src/quickshell/singletons/system/VpnService.qml").read_text(encoding="utf-8")
        self.assertIn('"set-source"', qml)
        self.assertIn("stdinEnabled", qml)
        self.assertIn(".write(", qml)
        self.assertNotIn("console.log", qml)


if __name__ == "__main__":
    unittest.main(verbosity=1)
