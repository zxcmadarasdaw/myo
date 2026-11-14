"""VPN stage 2 (TUN through the serpantinum-vpn system service), offline and without root.

    python3 install/tests/vpn_tun_test.py

Covers:
  - the root helper (src/scripts/system/serp_vpn_root.py): the TUN config template, what
    it refuses, `apply` writing only after `sing-box check`, file modes, the cleanup parser;
  - the client side in serp_vpn.py: the payload for the helper (servers only, never the
    link), connect / disconnect / hung service / force-off / clear through a fake pkexec
    and a fake systemctl (the fake "service" runs a fake sing-box with a Clash API);
  - the DNS and other-VPN parsers on fixtures;
  - the systemd unit, the polkit action and the polkit rule, and the installer module.
Nothing here needs root, sing-box, systemd or the network; no real service is touched.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vpn_test as base          # noqa: E402  (fixtures, Env, the client module as base.vpn)

vpn = base.vpn
ROOT = base.ROOT
HELPER = ROOT / "src/scripts/system/serp_vpn_root.py"
SYS = ROOT / "install/system/vpn"
POSIX = os.name == "posix"

# ---- fakes -------------------------------------------------------------------------------

FAKE_SINGBOX_TUN = base.FAKE_SINGBOX.replace(
    '    if ib.get("type") == "tun":\n        problems.append("tun inbound")\n'
    '    if ib.get("listen") != "127.0.0.1":\n        problems.append("inbound not on 127.0.0.1")\n',
    '    if ib.get("type") == "tun":\n'
    '        if not (ib.get("auto_route") and ib.get("strict_route") and ib.get("interface_name") == "serp-tun0"):\n'
    '            problems.append("bad tun inbound")\n'
    '    elif ib.get("listen") != "127.0.0.1":\n        problems.append("inbound not on 127.0.0.1")\n'
).replace('    print("sing-box version 1.12.0-fake")',
          '    print("sing-box version " + os.environ.get("FAKE_SINGBOX_VERSION", "1.12.0") + "-fake")')
assert "bad tun inbound" in FAKE_SINGBOX_TUN and "FAKE_SINGBOX_VERSION" in FAKE_SINGBOX_TUN

FAKE_SYSTEMCTL = r'''
import os, signal, subprocess, sys
d = os.environ["FAKE_SYS_DIR"]
args = sys.argv[1:]
with open(os.path.join(d, "systemctl.log"), "a", encoding="utf-8") as f:
    f.write(" ".join(args) + "\n")
st, pidf = os.path.join(d, "state"), os.path.join(d, "pid")
def get():
    return open(st).read().strip() if os.path.exists(st) else "inactive"
def put(s):
    open(st, "w").write(s)
def kill_it():
    if os.path.exists(pidf):
        try:
            os.kill(int(open(pidf).read()), signal.SIGTERM)
        except OSError:
            pass
        os.unlink(pidf)
verb, unit = args[0], args[-1]
if unit != "serpantinum-vpn.service":
    print("inactive")
    sys.exit(3)
if os.environ.get("FAKE_SYS_DENY") and verb in ("start", "restart", "stop"):
    print("Failed to %s serpantinum-vpn.service: Access denied" % verb, file=sys.stderr)
    sys.exit(4)
if verb == "is-active":
    print(get())
    sys.exit(0 if get() == "active" else 3)
if verb in ("start", "restart"):
    kill_it()
    if os.environ.get("FAKE_SYS_FAIL"):
        put("failed")
        print("Job for serpantinum-vpn.service failed.", file=sys.stderr)
        sys.exit(1)
    kw = {"start_new_session": True} if os.name == "posix" else \
         {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS}
    p = subprocess.Popen([sys.executable, os.environ["FAKE_SINGBOX_PY"], "run", "-c",
                          os.path.join(os.environ["SERP_VPN_ROOT_DIR_TEST"], "config.json")],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, **kw)
    open(pidf, "w").write(str(p.pid))
    put("active")
    sys.exit(0)
if verb == "stop":
    if os.environ.get("FAKE_SYS_HANG") and get() == "active":
        put("deactivating")              # stop "times out": sing-box keeps running
        sys.exit(1)
    kill_it()
    put("inactive")
    sys.exit(0)
if verb == "kill":
    kill_it()
    put("inactive")
    sys.exit(0)
if verb == "reset-failed":
    if get() == "failed":
        put("inactive")
    sys.exit(0)
sys.exit(0)
'''

FAKE_PKEXEC = r'''
import os, subprocess, sys
d = os.environ["FAKE_SYS_DIR"]
with open(os.path.join(d, "pkexec.log"), "a", encoding="utf-8") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
if os.environ.get("FAKE_PKEXEC_DENY"):
    print("Error executing command as another user: Not authorized", file=sys.stderr)
    sys.exit(127)
sys.exit(subprocess.run([sys.executable, sys.argv[1]] + sys.argv[2:]).returncode)
'''


def make_exe(directory, name, source):
    """A runnable fake: `name` (POSIX shell wrapper) or `name.cmd` (Windows)."""
    script = Path(directory) / (name.replace("-", "_") + ".py")
    script.write_text(source, encoding="utf-8")
    if POSIX:
        exe = Path(directory) / name
        exe.write_text(f"#!/bin/sh\nexec '{sys.executable}' '{script}' \"$@\"\n", encoding="utf-8")
        exe.chmod(0o755)
    else:
        exe = Path(directory) / (name + ".cmd")
        exe.write_text(f'@"{sys.executable}" "{script}" %*\n', encoding="oem")
    return str(exe), str(script)


def servers_config(settings=None):
    parsed = vpn.parse_subscription(base.LINK_LIST)
    settings = settings or dict(vpn.DEFAULT_SETTINGS, secret="abcdefghijklmnop1234")
    return vpn.build_config(parsed["servers"], settings), settings


def run_helper(action, payload, env_extra=None):
    env = dict(os.environ, **(env_extra or {}))
    data = payload if isinstance(payload, str) else json.dumps(payload)
    p = subprocess.run([sys.executable, str(HELPER), action], input=data, capture_output=True, text=True,
                       env=env, timeout=60)
    return p.returncode, (json.loads(p.stdout) if p.stdout.strip() else {}), p.stderr


class RootEnv:
    """A fake /etc/serpantinum-vpn, fake sing-box/systemctl/pkexec, plus a stage 1 Env."""

    KEYS = ("SERP_VPN_ROOT_DIR_TEST", "SERP_VPN_ROOT_TOOLS", "FAKE_SYS_DIR", "FAKE_SINGBOX_PY",
            "FAKE_SYS_DENY", "FAKE_SYS_FAIL", "FAKE_SYS_HANG", "FAKE_PKEXEC_DENY", "FAKE_SINGBOX_VERSION")

    def __init__(self):
        self.env = base.Env()
        self.saved = {k: os.environ.get(k) for k in self.KEYS}
        for k in self.KEYS:
            os.environ.pop(k, None)
        self.tmp = tempfile.mkdtemp(prefix="serp-vpn-root-")
        self.etc = os.path.join(self.tmp, "etc")
        self.tools = os.path.join(self.tmp, "tools")
        self.sys = os.path.join(self.tmp, "sys")
        for d in (self.tools, self.sys):
            os.makedirs(d)
        _, singbox_py = make_exe(self.tools, "sing-box", FAKE_SINGBOX_TUN)
        systemctl, _ = make_exe(self.sys, "systemctl", FAKE_SYSTEMCTL)
        pkexec, _ = make_exe(self.sys, "pkexec", FAKE_PKEXEC)
        os.environ.update(SERP_VPN_ROOT_DIR_TEST=self.etc, SERP_VPN_ROOT_TOOLS=self.tools,
                          FAKE_SYS_DIR=self.sys, FAKE_SINGBOX_PY=singbox_py,
                          SERP_VPN_SYSTEMCTL=systemctl, SERP_VPN_PKEXEC=pkexec,
                          SERP_VPN_HELPER=str(HELPER), SERP_VPN_UNIT_FILE=str(SYS / "serpantinum-vpn.service"))

    def calls(self, name):
        p = os.path.join(self.sys, name + ".log")
        return Path(p).read_text(encoding="utf-8").splitlines() if os.path.exists(p) else []

    def close(self):
        for k in ("FAKE_SYS_HANG", "FAKE_SYS_DENY", "FAKE_SYS_FAIL", "FAKE_PKEXEC_DENY"):
            os.environ.pop(k, None)
        try:
            vpn.force_off()
        except Exception:
            pass
        self.env.close()
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        shutil.rmtree(self.tmp, ignore_errors=True)


# ---- root helper ---------------------------------------------------------------------------


class HelperTemplate(unittest.TestCase):
    def setUp(self):
        cfg, settings = servers_config()
        self.payload = vpn.tun_payload(cfg, settings)

    def test_tun_config_shape(self):
        rc, out, err = run_helper("check-input", self.payload)
        self.assertEqual(rc, 0, err)
        cfg = out["config"]
        tun = next(i for i in cfg["inbounds"] if i["type"] == "tun")
        self.assertTrue(tun["auto_route"] and tun["strict_route"])
        self.assertEqual(tun["interface_name"], "serp-tun0")
        mixed = next(i for i in cfg["inbounds"] if i["type"] == "mixed")
        self.assertEqual(mixed["listen"], "127.0.0.1")
        self.assertEqual(cfg["experimental"]["clash_api"]["external_controller"], "127.0.0.1:9097")
        self.assertEqual(cfg["experimental"]["clash_api"]["secret"], "abcdefghijklmnop1234")
        self.assertIn({"protocol": "dns", "action": "hijack-dns"}, cfg["route"]["rules"])
        self.assertEqual(cfg["route"]["final"], "proxy")
        self.assertTrue(cfg["route"]["auto_detect_interface"])     # no routing loop to the servers
        self.assertEqual(cfg["dns"]["final"], "remote")
        dns = {s["tag"]: s for s in cfg["dns"]["servers"]}
        self.assertEqual(dns["remote"]["detour"], "proxy")                  # normal names: over the VPN
        self.assertNotIn("detour", dns[cfg["route"]["default_domain_resolver"]])   # server names: direct
        self.assertNotEqual(dns[cfg["route"]["default_domain_resolver"]]["type"], "local")   # no resolved loop
        sel = cfg["outbounds"][0]
        self.assertEqual(sel["type"], "selector")
        self.assertEqual(len(sel["outbounds"]), len(base.LINKS))
        self.assertEqual(out["skipped"], [])

    def test_payload_has_servers_not_link(self):
        text = json.dumps(self.payload)
        self.assertNotIn("vless://", text)
        self.assertNotIn("http://127.0.0.1", text)
        self.assertEqual({o["type"] for o in self.payload["outbounds"]} & {"selector", "direct"}, set())

    def test_refuses_file_keys_chaining_and_unknown_types(self):
        obs = self.payload["outbounds"]
        bad = [dict(obs[0], tag="a", tls={"enabled": True, "certificate_path": "/etc/shadow"}),
               dict(obs[1], tag="b", detour="direct"),
               {"type": "direct", "tag": "c", "server": "x", "server_port": 1},
               dict(obs[2], tag="d", server="evil host;rm")]
        rc, out, _ = run_helper("check-input", dict(self.payload, outbounds=bad + obs[3:4]))
        self.assertEqual(rc, 0)
        self.assertEqual(len(out["skipped"]), 4)
        self.assertEqual(out["config"]["outbounds"][0]["outbounds"], [obs[3]["tag"]])
        self.assertNotIn("/etc/shadow", json.dumps(out["config"]))

    def test_refuses_bad_input(self):
        for payload in ("not json", [], dict(self.payload, outbounds=[]), dict(self.payload, secret="short"),
                        dict(self.payload, secret="has space in it 123"), dict(self.payload, apiPort=80),
                        dict(self.payload, outbounds=[{"type": "direct", "tag": "x"}])):
            rc, out, _ = run_helper("check-input", payload)
            self.assertEqual(rc, 1, payload if not isinstance(payload, dict) else list(payload))
            self.assertEqual(out["error"]["code"], "bad_input")

    def test_cleanup_rule_parser(self):
        root = {"__name__": "root"}
        exec(compile(HELPER.read_text(encoding="utf-8"), str(HELPER), "exec"), root)
        rules = ("0:\tfrom all lookup local\n"
                 "100:\tfrom all lookup 200\n"
                 "9000:\tfrom all to 172.19.0.0/30 lookup 2022\n"
                 "9001:\tfrom all lookup 2022 suppress_prefixlength 0\n"
                 "9002:\tnot from all dport 53 lookup main suppress_prefixlength 0\n"
                 "9003:\tfrom all iif serp-tun0 goto 9010\n"
                 "9010:\tfrom all nop\n"
                 "32766:\tfrom all lookup main\n"
                 "32767:\tfrom all lookup default\n")
        self.assertEqual(root["rules_to_delete"](rules), [9000, 9001, 9002, 9003, 9010])
        self.assertEqual(root["rules_to_delete"]("0:\tfrom all lookup local\n32766:\tfrom all lookup main\n"), [])


class HelperApply(unittest.TestCase):
    def setUp(self):
        self.root = RootEnv()
        cfg, settings = servers_config()
        self.payload = vpn.tun_payload(cfg, settings)
        self.conf = os.path.join(self.root.etc, "config.json")

    def tearDown(self):
        self.root.close()

    def test_apply_writes_checked_config(self):
        rc, out, err = run_helper("apply", self.payload)
        self.assertEqual((rc, out.get("ok")), (0, True), err + json.dumps(out))
        cfg = json.loads(Path(self.conf).read_text(encoding="utf-8"))
        self.assertEqual(cfg["inbounds"][0]["type"], "tun")
        if POSIX:
            self.assertEqual(os.stat(self.conf).st_mode & 0o777, 0o600)
            self.assertEqual(os.stat(self.root.etc).st_mode & 0o777, 0o700)
        self.assertEqual([f for f in os.listdir(self.root.etc) if f.startswith(".new-")], [])

    def test_failed_check_keeps_old_config(self):
        run_helper("apply", self.payload)
        before = Path(self.conf).read_text(encoding="utf-8")
        rc, out, _ = run_helper("apply", dict(self.payload, apiPort=9555), {"FAKE_SINGBOX_FAIL": "1"})
        self.assertEqual((rc, out["error"]["code"]), (1, "check_failed"))
        self.assertIn("forced failure", out["error"]["detail"])
        self.assertNotIn(self.root.etc, out["error"]["detail"])          # temp path is hidden
        self.assertEqual(Path(self.conf).read_text(encoding="utf-8"), before)
        self.assertEqual([f for f in os.listdir(self.root.etc) if f.startswith(".new-")], [])

    def test_old_or_missing_singbox(self):
        rc, out, _ = run_helper("apply", self.payload, {"FAKE_SINGBOX_VERSION": "1.10.3"})
        self.assertEqual((rc, out["error"]["code"]), (2, "old_singbox"))
        rc, out, _ = run_helper("apply", self.payload, {"SERP_VPN_ROOT_TOOLS": self.root.sys})
        self.assertEqual((rc, out["error"]["code"]), (2, "no_singbox"))
        self.assertFalse(os.path.exists(self.conf))

    def test_forget(self):
        run_helper("apply", self.payload)
        rc, out, _ = run_helper("forget", "")
        self.assertEqual((rc, out["ok"]), (0, True))
        self.assertFalse(os.path.exists(self.conf))


# ---- client: connect / disconnect / hung service / force-off ------------------------------


class TunLifecycle(unittest.TestCase):
    def setUp(self):
        self.root = RootEnv()
        self.sub = base.SubServer()
        self.sub.body = base.LINK_LIST.encode()
        vpn.set_source(self.sub.url("tok-tun"))

    def tearDown(self):
        self.root.close()
        self.sub.close()

    def test_mode_connect_select_disconnect(self):
        self.assertTrue(vpn.tun_installed())
        st = vpn.set_mode("tun")
        self.assertEqual(st["mode"], "tun")
        self.assertFalse(st["running"])
        st = vpn.connect()
        self.assertEqual(st["state"], "connected", st.get("error"))
        self.assertTrue(st["tunActive"])
        self.assertEqual(self.root.calls("pkexec"), [f"{HELPER} apply"])          # servers on stdin only
        self.assertIn("restart serpantinum-vpn.service", self.root.calls("systemctl"))
        self.assertTrue(os.path.exists(os.path.join(self.root.env.state, "tun_applied")))
        tags = [s["tag"] for s in vpn._servers()]
        self.assertEqual(vpn.select(tags[2])["current"], tags[2])                 # live through the Clash API
        self.assertIn(tags[2], vpn.ping()["delays"])                              # ping uses the service API
        st = vpn.disconnect()
        self.assertEqual(st["state"], "disconnected")
        self.assertEqual(st["tunState"], "inactive")
        for line in self.root.calls("pkexec") + self.root.calls("systemctl"):
            self.assertNotIn("tok-tun", line)

    def test_switch_modes_while_connected(self):
        if not POSIX:
            self.skipTest("the stage 1 user proxy lifecycle runs on Linux only")
        vpn.connect()                                   # proxy mode first
        self.assertTrue(vpn.is_running())
        st = vpn.set_mode("tun")
        self.assertEqual((st["state"], st["tunActive"]), ("connected", True))
        self.assertFalse(vpn.is_running())              # the user proxy was stopped: same ports
        st = vpn.set_mode("proxy")
        self.assertEqual(st["state"], "connected")
        self.assertTrue(vpn.is_running())
        self.assertEqual(vpn.tun_state(), "inactive")

    def test_not_authorized(self):
        vpn.set_mode("tun")
        os.environ["FAKE_PKEXEC_DENY"] = "1"
        try:
            with self.assertRaises(vpn.VpnError) as ctx:
                vpn.connect()
        finally:
            os.environ.pop("FAKE_PKEXEC_DENY")
        self.assertEqual(ctx.exception.code, "not_authorized")
        self.assertIn("installer", ctx.exception.as_dict()["message"])
        os.environ["FAKE_SYS_DENY"] = "1"
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.connect()
        self.assertEqual(ctx.exception.code, "not_authorized")

    def test_service_fails_to_start(self):
        vpn.set_mode("tun")
        os.environ["FAKE_SYS_FAIL"] = "1"
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.connect()
        self.assertEqual(ctx.exception.code, "service_failed")
        st = vpn.status()
        self.assertEqual(st["state"], "error")
        self.assertIn("serpantinum-vpn", st["error"])

    def test_hung_service_and_force_off(self):
        vpn.set_mode("tun")
        self.assertEqual(vpn.connect()["state"], "connected")
        os.environ["FAKE_SYS_HANG"] = "1"
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.disconnect()
        self.assertEqual(ctx.exception.code, "stop_timeout")
        self.assertIn("force-off", ctx.exception.as_dict()["message"])
        st = vpn.status()
        self.assertEqual((st["state"], st["tunState"]), ("error", "deactivating"))
        st = vpn.force_off()
        self.assertEqual(st["tunState"], "inactive")
        self.assertEqual(st["forced"]["kill"], "ok")
        self.assertEqual(st["forced"]["cleanup"], "ok")
        self.assertIn(f"{HELPER} cleanup", self.root.calls("pkexec"))
        self.assertIn("kill --signal=SIGKILL serpantinum-vpn.service", self.root.calls("systemctl"))
        self.assertNotEqual(st["state"], "connected")

    def test_clear_wipes_root_config(self):
        vpn.set_mode("tun")
        vpn.connect()
        self.assertTrue(os.path.exists(os.path.join(self.root.etc, "config.json")))
        vpn.clear()
        self.assertFalse(os.path.exists(os.path.join(self.root.etc, "config.json")))
        self.assertEqual(vpn.tun_state(), "inactive")

    def test_tun_not_installed(self):
        os.environ["SERP_VPN_UNIT_FILE"] = os.path.join(self.root.tmp, "missing.service")
        st = vpn.status()
        self.assertFalse(st["tunInstalled"])
        with self.assertRaises(vpn.VpnError) as ctx:
            vpn.set_mode("tun")
        self.assertEqual(ctx.exception.code, "tun_not_installed")
        self.assertEqual(vpn.load_settings()["mode"], "proxy")

    def test_cli_json(self):
        env = dict(os.environ, PYTHONIOENCODING="utf-8")
        p = subprocess.run([sys.executable, str(base.SCRIPT), "check", "--json"], capture_output=True,
                           text=True, env=env, timeout=30)
        data = json.loads(p.stdout)
        self.assertTrue(data["ok"] and data["tunInstalled"])
        p = subprocess.run([sys.executable, str(base.SCRIPT), "mode", "bogus", "--json"], capture_output=True,
                           text=True, env=env, timeout=30)
        self.assertEqual(json.loads(p.stdout)["error"]["code"], "bad_mode")
        p = subprocess.run([sys.executable, str(base.SCRIPT), "force-off", "--json"], capture_output=True,
                           text=True, env=env, timeout=60)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("forced", json.loads(p.stdout))


# ---- DNS and conflicts -----------------------------------------------------------------------


class Checks(unittest.TestCase):
    def test_interfaces(self):
        names = ["lo", "enp3s0", "wlp2s0", "docker0", "virbr0", "tunl0", "ip6tnl0", "serp-tun0",
                 "wg0", "tun0", "tailscale0", "nordlynx", "proton0", "CloudflareWARP", "br-1a2b"]
        self.assertEqual(vpn.iface_conflicts(names), ["CloudflareWARP", "nordlynx", "proton0", "tun0", "wg0"])
        self.assertEqual(vpn.iface_conflicts(["lo", "enp3s0", "serp-tun0", "tunl0"]), [])

    def test_processes(self):
        self.assertEqual(vpn.proc_conflicts(["bash", "openvpn", "Xray", "sing-box", "mihomo", "openvpn"]),
                         ["Mihomo (Clash)", "OpenVPN", "Xray"])
        self.assertEqual(vpn.proc_conflicts(["sing-box", "systemd", "quickshell"]), [])

    def test_nmcli(self):
        text = ("Wired connection 1:802-3-ethernet\n"
                "Office\\: Riga:vpn\n"
                "wg-home:wireguard\n"
                "lo:loopback\n"
                "Home WiFi:802-11-wireless\n")
        self.assertEqual(vpn.parse_nmcli_active(text), ["Office: Riga", "wg-home"])
        self.assertEqual(vpn.parse_nmcli_active(""), [])

    def test_resolvectl(self):
        on = "Global\n       Protocols: +LLMNR +mDNS +DNSOverTLS DNSSEC=no/unsupported\n"
        off = "Global\n       Protocols: +LLMNR +mDNS -DNSOverTLS DNSSEC=no/unsupported\n"
        self.assertTrue(vpn.parse_resolvectl_dot(on))
        self.assertFalse(vpn.parse_resolvectl_dot(off))
        self.assertTrue(vpn.parse_resolvectl_dot("DNSOverTLS=opportunistic"))

    def test_dns(self):
        self.assertEqual(vpn.dns_checks("/run/systemd/resolve/stub-resolv.conf", True, False), [])
        self.assertEqual([c for c, _ in vpn.dns_checks("", False, False)], ["dns_no_resolved"])
        self.assertEqual(vpn.dns_checks("/etc/resolv.conf", True, False), [("dns_not_stub", "/etc/resolv.conf")])
        self.assertEqual([c for c, _ in vpn.dns_checks("/run/systemd/resolve/stub-resolv.conf", True, True)],
                         ["dns_dot"])

    def test_build_checks_messages(self):
        items = vpn.build_checks(["enp3s0", "tailscale0", "wg0"], ["tailscaled"], ["Office VPN"],
                                 "/run/systemd/resolve/stub-resolv.conf", True, False)
        self.assertEqual([i["code"] for i in items], ["conflict_tailscale", "conflict_iface", "conflict_nm"])
        self.assertTrue(all(i["level"] == "warn" for i in items))
        self.assertIn("wg0", items[1]["message"])
        os.environ["SERP_VPN_LANG"] = "ru"
        try:
            ru = vpn.build_checks([], [], [], "", False, False)
        finally:
            os.environ["SERP_VPN_LANG"] = "en"
        self.assertEqual(ru[0]["level"], "info")
        self.assertIn("systemd-resolved не запущен", ru[0]["message"])


# ---- system files and installer ---------------------------------------------------------------


class SystemFiles(unittest.TestCase):
    def test_unit(self):
        unit = (SYS / "serpantinum-vpn.service").read_text(encoding="utf-8")
        self.assertIn("ExecStart=/usr/libexec/serpantinum/serp-vpn-root run", unit)
        self.assertIn("ExecStopPost=/usr/libexec/serpantinum/serp-vpn-root cleanup", unit)
        self.assertIn("ExecStartPre=/usr/libexec/serpantinum/serp-vpn-root cleanup", unit)
        self.assertIn("TimeoutStopSec=", unit)
        self.assertIn("ConditionPathExists=/etc/serpantinum-vpn/config.json", unit)
        self.assertNotIn("[Install]", unit)                  # never started at boot behind the user's back

    def test_polkit_action(self):
        import xml.etree.ElementTree as ET
        action = ET.parse(SYS / "org.serpantinum.vpn.policy").getroot().find("action")
        self.assertEqual(action.get("id"), "org.serpantinum.vpn.helper")
        self.assertEqual(action.find("defaults/allow_any").text, "no")
        self.assertEqual(action.find("defaults/allow_active").text, "auth_admin")
        path = next(a.text for a in action.findall("annotate") if a.get("key") == "org.freedesktop.policykit.exec.path")
        self.assertEqual(path, "/usr/libexec/serpantinum/serp-vpn-root")

    def test_polkit_rule(self):
        rule = (SYS / "49-serpantinum-vpn.rules.in").read_text(encoding="utf-8")
        self.assertEqual(rule.count("@USER@"), 2)            # once in the comment, once in the check
        self.assertIn('subject.user !== "@USER@"', rule)
        self.assertIn('action.lookup("unit") === "serpantinum-vpn.service"', rule)
        self.assertIn('"org.serpantinum.vpn.helper"', rule)
        self.assertNotIn("isInGroup", rule)                  # no group-wide grants
        self.assertEqual(rule.count("polkit.Result.YES"), 2)
        node = shutil.which("node")
        if not node:
            self.skipTest("node not installed: the rule logic was checked as text only")
        code = rule.replace("@USER@", "alice")
        harness = ("var polkit={Result:{YES:'yes',NOT_HANDLED:'nh'},addRule:function(f){globalThis.rule=f}};\n" + code +
                   "\nfunction A(id,unit,verb){return {id:id,lookup:function(k){return k==='unit'?unit:verb}}}\n"
                   "function S(u,local,active){return {user:u,local:local,active:active}}\n"
                   "var M='org.freedesktop.systemd1.manage-units', U='serpantinum-vpn.service';\n"
                   "var out=[rule(A('org.serpantinum.vpn.helper'),S('alice',true,true)),"
                   "rule(A(M,U,'stop'),S('alice',true,true)),"
                   "rule(A(M,U,'kill'),S('alice',true,true)),"
                   "rule(A(M,'sshd.service','stop'),S('alice',true,true)),"
                   "rule(A(M,U,'enable'),S('alice',true,true)),"
                   "rule(A('org.serpantinum.vpn.helper'),S('bob',true,true)),"
                   "rule(A('org.serpantinum.vpn.helper'),S('alice',false,true)),"
                   "rule(A('org.serpantinum.vpn.helper'),S('alice',true,false))];\n"
                   "console.log(JSON.stringify(out));\n")
        p = subprocess.run([node, "-e", harness], capture_output=True, text=True, timeout=30)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout), ["yes", "yes", "yes", "nh", "nh", "nh", "nh", "nh"])

    def test_installer_module(self):
        mod = (ROOT / "install/modules/vpn.sh").read_text(encoding="utf-8")
        inst = (ROOT / "install/install.sh").read_text(encoding="utf-8")
        self.assertIn('source "$MODULES_DIR/vpn.sh"', inst)
        self.assertIn("\ninstall_vpn_service\n", inst)
        self.assertIn("-Dm755 -o root -g root", mod)
        self.assertIn("install -dm700 -o root -g root /etc/serpantinum-vpn", mod)
        self.assertNotIn("systemctl enable", mod)            # the service is not enabled at boot
        for lang in ("en", "ru"):
            data = json.loads((ROOT / f"src/assets/languages/{lang}.json").read_text(encoding="utf-8"))
            for key in ("installing", "installed", "skipped", "bad_user", "failed"):
                self.assertTrue(data["installer"]["vpn"][key])

    def test_installer_user_name_check(self):
        bash = shutil.which("bash")
        if not bash:
            self.skipTest("bash not available")
        mod = (ROOT / "install/modules/vpn.sh").as_posix()
        tpl = (SYS / "49-serpantinum-vpn.rules.in").as_posix()
        script = (f'source "{mod}"; vpn_render_polkit_rules alice "{tpl}" | grep -c \'"alice"\'; '
                  f'vpn_render_polkit_rules \'x"; evil\' "{tpl}"; echo "rc=$?"')
        p = subprocess.run([bash, "-c", script], capture_output=True, text=True, timeout=30)
        self.assertIn("rc=1", p.stdout, p.stderr)
        self.assertTrue(p.stdout.startswith("1"), p.stdout)

    def test_helper_source_rules(self):
        src = HELPER.read_text(encoding="utf-8")
        self.assertTrue(src.startswith("#!/usr/bin/python3 -I"))   # isolated mode as root
        self.assertNotIn("shell=True", src)
        self.assertNotIn("os.system", src)


if __name__ == "__main__":
    unittest.main(verbosity=1)
