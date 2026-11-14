#!/usr/bin/python3 -I
"""Privileged helper of the Serpantinum VPN (stage 2: TUN). Runs as root.

Installed by the installer as /usr/libexec/serpantinum/serp-vpn-root (root:root 755).
This repository copy is never run as root: polkit only allows the installed path.

    serp-vpn-root apply      (pkexec)  read servers as JSON on stdin, build the TUN
                                        config from a fixed template, `sing-box check`
                                        it and only then replace /etc/serpantinum-vpn/config.json
    serp-vpn-root cleanup    (pkexec / systemd ExecStartPre, ExecStopPost)
                                        remove the TUN interface and the policy-routing
                                        rules sing-box left behind (e.g. after SIGKILL)
    serp-vpn-root run        (systemd ExecStart) exec sing-box with that config
    serp-vpn-root forget     (pkexec)  delete that config (the subscription was removed)
    serp-vpn-root check-input           validate stdin like `apply` and print the config;
                                        writes nothing (used by the tests)

The input never becomes the config as is: only proxy outbounds of known types are
taken, keys that name files (..._path, ..._file) and chaining (detour) are rejected;
inbounds, DNS, routing, ports and the API binding come from this file.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

CONF_DIR = os.environ.get("SERP_VPN_ROOT_DIR_TEST") or "/etc/serpantinum-vpn"
CONF = os.path.join(CONF_DIR, "config.json")
TUN_NAME = "serp-tun0"
TABLE = 2022           # iproute2_table_index in the template
RULE_INDEX = 9000      # iproute2_rule_index in the template (sing-box uses a few priorities from here)
SINGBOX_PATHS = ("/usr/bin/sing-box", "/usr/local/bin/sing-box")
IP_BIN = ("/usr/sbin/ip", "/usr/bin/ip", "/sbin/ip")
NFT_BIN = ("/usr/sbin/nft", "/usr/bin/nft")
MIN_SINGBOX = (1, 12)

OUTBOUND_TYPES = {"vless", "vmess", "trojan", "shadowsocks", "hysteria2", "hysteria", "tuic", "socks", "http", "anytls"}
FORBIDDEN_KEYS = {"detour", "bind_interface", "inet4_bind_address", "inet6_bind_address", "routing_mark",
                  "domain_resolver", "network_strategy", "fallback_delay"}
TAG_RE = re.compile(r"^[^\x00-\x1f]{1,80}$")


class InputError(Exception):
    pass


def _first(paths):
    # Tests only: tools come from one fake directory. pkexec and systemd start this helper
    # with a clean environment, so these variables cannot reach the installed copy.
    if os.environ.get("SERP_VPN_ROOT_DIR_TEST"):
        import shutil
        tools = os.environ.get("SERP_VPN_ROOT_TOOLS", "")
        for p in paths:
            found = shutil.which(os.path.basename(p), path=tools) if tools else None
            if found:
                return found
        return ""
    for p in paths:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return ""


def _check_value(value, where, depth=0):
    if depth > 8:
        raise InputError(f"{where}: nested too deep")
    if isinstance(value, dict):
        for k, v in value.items():
            if not isinstance(k, str) or len(k) > 64:
                raise InputError(f"{where}: bad key")
            low = k.lower()
            if low in FORBIDDEN_KEYS or low.endswith("_path") or low.endswith("_file"):
                raise InputError(f"{where}: key '{k}' is not allowed")
            _check_value(v, f"{where}.{k}", depth + 1)
    elif isinstance(value, list):
        if len(value) > 64:
            raise InputError(f"{where}: list too long")
        for i, v in enumerate(value):
            _check_value(v, f"{where}[{i}]", depth + 1)
    elif isinstance(value, str):
        if len(value) > 4096:
            raise InputError(f"{where}: string too long")
    elif value is None or isinstance(value, (bool, int, float)):
        pass
    else:
        raise InputError(f"{where}: bad value")


def clean_outbound(ob, i):
    if not isinstance(ob, dict):
        raise InputError(f"outbound {i}: not an object")
    t = ob.get("type")
    if t not in OUTBOUND_TYPES:
        raise InputError(f"outbound {i}: type {t!r} is not allowed")
    tag = ob.get("tag")
    if not isinstance(tag, str) or not TAG_RE.match(tag) or tag in ("proxy", "direct"):
        raise InputError(f"outbound {i}: bad tag")
    server = ob.get("server")
    if not isinstance(server, str) or not re.fullmatch(r"[A-Za-z0-9.:\-\[\]_]{1,253}", server):
        raise InputError(f"outbound {i}: bad server")
    port = ob.get("server_port")
    if not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535:
        raise InputError(f"outbound {i}: bad port")
    _check_value(ob, f"outbound {i}")
    tr = ob.get("transport")
    if tr is not None and (not isinstance(tr, dict) or ("path" in tr and not isinstance(tr["path"], str))):
        raise InputError(f"outbound {i}: bad transport")
    return dict(ob)


def build(payload):
    if not isinstance(payload, dict):
        raise InputError("input is not an object")
    obs = payload.get("outbounds")
    if not isinstance(obs, list) or not 1 <= len(obs) <= 2000:
        raise InputError("outbounds: 1..2000 entries expected")
    outbounds, skipped, seen = [], [], set()
    for i, ob in enumerate(obs):           # one odd server must not disable TUN for all of them
        try:
            clean = clean_outbound(ob, i)
        except InputError as e:
            skipped.append(str(e))
            continue
        if clean["tag"] in seen:
            skipped.append(f"outbound {i}: duplicate tag")
            continue
        seen.add(clean["tag"])
        outbounds.append(clean)
    if not outbounds:
        raise InputError("no usable outbounds" + (f" ({skipped[0]})" if skipped else ""))
    build.skipped = skipped
    tags = [o["tag"] for o in outbounds]
    secret = payload.get("secret")
    if not isinstance(secret, str) or not re.fullmatch(r"[A-Za-z0-9_-]{8,128}", secret):
        raise InputError("bad secret")
    ports = {}
    for key, default in (("apiPort", 9097), ("proxyPort", 2080)):
        v = payload.get(key, default)
        if not isinstance(v, int) or isinstance(v, bool) or not 1024 <= v <= 65535:
            raise InputError(f"bad {key}")
        ports[key] = v
    selected = payload.get("selected")
    default = selected if selected in tags else tags[0]
    return {
        "log": {"level": "warn", "timestamp": True},
        "dns": {
            "servers": [
                {"type": "https", "tag": "remote", "server": "1.1.1.1", "detour": "proxy"},
                # resolves the VPN servers' own names: sing-box's outbound sockets are bound
                # to the physical interface, so this never loops back into the tunnel (the
                # "local" server would ask systemd-resolved, whose queries the TUN captures)
                {"type": "udp", "tag": "bootstrap", "server": "1.1.1.1"},
            ],
            "final": "remote",
            "strategy": "prefer_ipv4",
        },
        "inbounds": [
            {"type": "tun", "tag": "tun-in", "interface_name": TUN_NAME,
             "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"], "mtu": 9000,
             "auto_route": True, "strict_route": True, "stack": "mixed",
             "iproute2_table_index": TABLE, "iproute2_rule_index": RULE_INDEX},
            {"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": ports["proxyPort"]},
        ],
        "outbounds": [{"type": "selector", "tag": "proxy", "outbounds": tags, "default": default,
                       "interrupt_exist_connections": True}] + outbounds + [{"type": "direct", "tag": "direct"}],
        "route": {
            "auto_detect_interface": True,
            "default_domain_resolver": "bootstrap",
            "rules": [
                {"action": "sniff"},
                {"protocol": "dns", "action": "hijack-dns"},
                {"ip_is_private": True, "outbound": "direct"},
            ],
            "final": "proxy",
        },
        "experimental": {"clash_api": {"external_controller": f"127.0.0.1:{ports['apiPort']}", "secret": secret}},
    }


def singbox_version(binary):
    try:
        out = subprocess.run([binary, "version"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r"version\s+(\d+)\.(\d+)", out)
    return (int(m.group(1)), int(m.group(2))) if m else None


def fail(code, message, status=1):
    print(json.dumps({"ok": False, "error": {"code": code, "detail": message}}))
    return status


def cmd_apply(check_only=False):
    data = sys.stdin.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024:
        return fail("too_large", "input larger than 4 MB")
    try:
        cfg = build(json.loads(data))
    except (ValueError, InputError) as e:
        return fail("bad_input", str(e))
    skipped = getattr(build, "skipped", [])
    if check_only:
        print(json.dumps({"ok": True, "config": cfg, "skipped": skipped}))
        return 0
    binary = _first(SINGBOX_PATHS)
    if not binary:
        return fail("no_singbox", "sing-box is not installed in /usr/bin or /usr/local/bin", 2)
    ver = singbox_version(binary)
    if ver is None or ver < MIN_SINGBOX:
        return fail("old_singbox", "%d.%d" % MIN_SINGBOX, 2)
    os.makedirs(CONF_DIR, mode=0o700, exist_ok=True)
    os.chmod(CONF_DIR, 0o700)
    fd, tmp = tempfile.mkstemp(dir=CONF_DIR, prefix=".new-", suffix=".json")    # mode 600
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
        p = subprocess.run([binary, "check", "-c", tmp], capture_output=True, text=True, timeout=30)
        if p.returncode != 0:
            detail = re.sub(r"\x1b\[[0-9;]*m", "", (p.stderr or p.stdout).strip()).replace(tmp, "config.json")
            return fail("check_failed", detail[-600:])
        os.replace(tmp, CONF)
        tmp = None
        os.chmod(CONF, 0o600)
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass
    print(json.dumps({"ok": True, "skipped": skipped}))
    return 0


def _run_quiet(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None


def rules_to_delete(rule_text):
    """Priorities of the policy-routing rules that belong to our TUN (from `ip rule show`)."""
    prefs = []
    for line in rule_text.splitlines():
        m = re.match(r"\s*(\d+):\s*(.*)$", line)
        if not m:
            continue
        pref, rest = int(m.group(1)), m.group(2)
        ours = (RULE_INDEX <= pref < RULE_INDEX + 20 or f"lookup {TABLE}" in rest
                or f"iif {TUN_NAME}" in rest or f"oif {TUN_NAME}" in rest)
        if ours and pref not in (0, 32766, 32767):
            prefs.append(pref)
    return prefs


def cmd_cleanup():
    ip = _first(IP_BIN)
    removed = 0
    if ip:
        for fam in ("-4", "-6"):
            p = _run_quiet([ip, fam, "rule", "show"])
            if p and p.returncode == 0:
                for pref in rules_to_delete(p.stdout):
                    q = _run_quiet([ip, fam, "rule", "del", "pref", str(pref)])
                    removed += 1 if q and q.returncode == 0 else 0
            _run_quiet([ip, fam, "route", "flush", "table", str(TABLE)])
        p = _run_quiet([ip, "link", "show", TUN_NAME])
        if p and p.returncode == 0:
            _run_quiet([ip, "link", "delete", TUN_NAME])
            removed += 1
    nft = _first(NFT_BIN)
    if nft:
        p = _run_quiet([nft, "list", "table", "inet", "sing-box"])
        if p and p.returncode == 0:
            _run_quiet([nft, "delete", "table", "inet", "sing-box"])
            removed += 1
    print(json.dumps({"ok": True, "removed": removed}))
    return 0


def cmd_run():
    binary = _first(SINGBOX_PATHS)
    if not binary:
        print("sing-box is not installed", file=sys.stderr)
        return 2
    if not os.path.isfile(CONF):
        print(f"{CONF} does not exist; apply a configuration first", file=sys.stderr)
        return 1
    os.execv(binary, [binary, "run", "-c", CONF])
    return 1


def main(argv):
    cmd = argv[0] if argv else ""
    if cmd == "apply":
        return cmd_apply()
    if cmd == "check-input":
        return cmd_apply(check_only=True)
    if cmd == "cleanup":
        return cmd_cleanup()
    if cmd == "forget":                  # `serpantinum vpn clear`: no server credentials left in /etc
        try:
            os.unlink(CONF)
        except FileNotFoundError:
            pass
        except OSError as e:
            return fail("forget_failed", type(e).__name__)
        print(json.dumps({"ok": True}))
        return 0
    if cmd == "run":
        return cmd_run()
    print(__doc__, file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
