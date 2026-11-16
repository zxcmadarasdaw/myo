#!/usr/bin/python3 -I
"""Polkit entry point for the Fedora VPN components installed by Serpantinum."""
import json
import os
import signal
import subprocess
import sys


PACKAGES = {"python3-pyyaml", "iproute", "nftables"}
DNF_TIMEOUT = 20 * 60
OFFLINE_TIMEOUT = 90


def command(packages):
    return ["/usr/bin/dnf5", "--assumeyes", "--no-plugins", "--setopt=install_weak_deps=False",
            "--setopt=*.pkg_gpgcheck=True", "--setopt=timeout=25", "--setopt=retries=3",
            "install", *packages]


def offline_engine():
    # Python's isolated mode ignores the caller's PYTHONPATH. Import the copy
    # installed alongside this root-owned entry point and its pinned asset lock.
    sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
    from serp_vpn_singbox import SingboxError, install_system_from_stream

    def expire(_signum, _frame):
        raise SingboxError("sb_bundle_timeout")

    print(json.dumps({"event": "started"}), flush=True)
    signal.signal(signal.SIGALRM, expire)
    signal.alarm(OFFLINE_TIMEOUT)
    try:
        result = install_system_from_stream(sys.stdin.buffer)
    except SingboxError as exc:
        result = {"ok": False, "error": {"code": exc.code, "detail": exc.detail}}
    except OSError as exc:
        result = {"ok": False, "error": {"code": "setup_storage", "detail": exc.strerror or type(exc).__name__}}
    finally:
        signal.alarm(0)
    print(json.dumps(result), flush=True)
    return 0 if result["ok"] else 1


def main(args):
    if os.geteuid() != 0 or not args:
        return 64
    if args == ["offline-engine"]:
        return offline_engine()
    if args[0] != "install":
        return 64
    packages = args[1:]
    if not packages or len(set(packages)) != len(packages) or set(packages) - PACKAGES:
        return 64
    env = {"PATH": "/usr/sbin:/usr/bin", "HOME": "/root", "LANG": "C.UTF-8"}
    os.chdir("/")
    # Authorization is over once this line is out: the caller switches from the polkit
    # timeout to the transaction timeout (serp_vpn.py install_fedora_packages).
    print(json.dumps({"event": "started"}), flush=True)
    detail = ""
    try:
        result = subprocess.run(command(packages), stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env,
                                text=True, errors="replace", timeout=DNF_TIMEOUT)
    except subprocess.TimeoutExpired:      # killed here, as root: no dnf is left behind
        result, detail = None, f"DNF5 did not finish in {DNF_TIMEOUT // 60} min and was stopped"
    except OSError:
        result = None
    if result is not None and result.returncode:
        detail = "\n".join(result.stdout.strip().splitlines()[-6:])[-700:]
    print(json.dumps({"ok": result is not None and result.returncode == 0, "detail": detail}))
    return 0 if result is not None and result.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
