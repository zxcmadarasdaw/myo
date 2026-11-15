Serpantinum offline VPN bundle
==============================

This folder holds the official sing-box release archive (unchanged, from
github.com/SagerNet/sing-box), manifest.json and SHA256SUMS. Installing it needs
no internet. Serpantinum accepts the archive only when its version, size and
SHA-256 match the values pinned in its own source
(src/scripts/system/serp_vpn_singbox.lock.json).

No VPN server, subscription, key or token is included. Servers come from your own
link or configuration file, imported in Super+N -> VPN.

Install
-------
  * With Serpantinum's installer: nothing to do. When this folder is next to the
    installer (serpantinum/vpn-bundle), it is copied to
    ~/.local/share/serpantinum/vpn-bundle and sing-box is installed from it.
  * In the panel: Super+N -> VPN -> "Install VPN Components" uses this folder.
  * By hand:   ./install-vpn-bundle.sh            (proxy mode, no root)
               ./install-vpn-bundle.sh --system   (also TUN mode: /usr/local/bin, asks for sudo)

Check by hand:  sha256sum -c SHA256SUMS

Fedora Live
-----------
A Live session without persistent storage forgets everything at reboot, including
the installed sing-box. Keep this folder on a USB stick or another drive and run
./install-vpn-bundle.sh again after each boot (or choose the folder in the panel).
