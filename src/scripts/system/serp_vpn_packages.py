#!/usr/bin/python3 -I
"""Polkit entry point for the Fedora VPN components installed by Serpantinum."""
import json
import os
import subprocess
import sys


PACKAGES = {"sing-box", "python3-pyyaml", "iproute", "nftables"}
REPO = "serpantinum-sagernet"
DNF_TIMEOUT = 20 * 60


def command(packages, action):
    verb = "reinstall" if action == "repair" else action
    args = ["/usr/bin/dnf5", "--assumeyes", "--no-plugins", "--setopt=install_weak_deps=False",
            "--setopt=*.pkg_gpgcheck=True", "--setopt=timeout=25", "--setopt=retries=3"]
    if packages == ["sing-box"]:
        args += [f"--repofrompath={REPO},https://rpm.sagernet.org/",
                 f"--setopt={REPO}.repo_gpgcheck=True",
                 f"--setopt={REPO}.gpgkey=https://sing-box.app/gpg.key",
                 f"--setopt={REPO}.includepkgs=sing-box"]
        # Select upstream explicitly even if another repository publishes this name.
        return args + [verb, f"--from-repo={REPO}", "sing-box"]
    return args + [verb, *packages]


def main(args):
    if os.geteuid() != 0 or not args or args[0] not in {"install", "repair", "upgrade"}:
        return 64
    packages = args[1:]
    if not packages or len(set(packages)) != len(packages) or set(packages) - PACKAGES:
        return 64
    action = args[0]
    if (action != "install" or "sing-box" in packages) and packages != ["sing-box"]:
        return 64
    env = {"PATH": "/usr/sbin:/usr/bin", "HOME": "/root", "LANG": "C.UTF-8"}
    os.chdir("/")
    # Authorization is over once this line is out: the caller switches from the polkit
    # timeout to the transaction timeout (serp_vpn.py install_fedora_packages).
    print(json.dumps({"event": "started"}), flush=True)
    detail = ""
    try:
        result = subprocess.run(command(packages, action), stdin=subprocess.DEVNULL,
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
