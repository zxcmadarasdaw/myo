Serpantinum offline VPN bundle
==============================

This kit contains the official sing-box release from SagerNet, Fedora 45 x86_64
RPMs for iproute, nftables and optional PyYAML, their library dependencies,
manifest.json, SHA256SUMS and Proxy/TUN configuration samples. It assumes a
working Fedora installation and the corresponding Serpantinum backend.
Serpantinum checks the sing-box archive against its installed version, size and
SHA-256 lock. DNF checks Fedora RPM signatures with repositories disabled.

No VPN server, subscription, key or token is included. Servers come from your own
link or configuration file, imported in Super+N -> VPN.

Install
-------
  * From the matching Fedora 45 x86_64 checkout or full release, run
        bash install/install.sh --vpn-only
    The main installer may use repositories for other desktop components.
  * To restore the VPN without reinstalling the desktop, place the bundle
    in the Serpantinum checkout as vpn-bundle/ and run from that checkout:
        bash install/install.sh --vpn-only
  * Already installed Serpantinum:
        bash install-vpn-bundle.sh                  # Proxy
        bash install-vpn-bundle.sh --system         # Proxy and TUN
        bash install-vpn-bundle.sh --system --yaml  # add Clash YAML support

    sha256sum -c SHA256SUMS
    bash install-vpn-bundle.sh --check
    bash install-vpn-bundle.sh --system --check

From the checkout, use bash install/install.sh --vpn-check for the combined
local bundle and installed-component report. See SOURCES.md for provenance.

The check configurations use a local placeholder and are for sing-box check.
They never connect to a public VPN server. To connect, import your own profile.

Fedora Live
-----------
A Live session without persistent storage forgets everything at reboot, including
the installed sing-box. Keep this folder on a USB stick or another drive and run
bash install/install.sh --vpn-only from the matching Serpantinum checkout.

CachyOS / Arch (x86_64)
----------------------
From the Serpantinum checkout, run bash install/install.sh --vpn-only.
It installs missing polkit, iproute2, nftables and python-yaml through pacman.
The engine comes from this local bundle or an already working system sing-box.
RPM dependencies are used only on Fedora. With the Arch dependencies already
installed, the bundle can prepare the engine without network access.
