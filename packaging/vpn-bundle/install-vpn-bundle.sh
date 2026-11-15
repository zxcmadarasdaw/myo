#!/usr/bin/env bash
# Install sing-box from this offline bundle. No network is used.
#   ./install-vpn-bundle.sh            proxy mode: ~/.local/share/serpantinum/vpn/bin/sing-box
#   ./install-vpn-bundle.sh --system   also TUN mode: /usr/local/bin/sing-box (root-owned, sudo)
# The checks (version, size, SHA-256 against Serpantinum's pinned lock) are done by
# Serpantinum's own scripts, so Serpantinum must be installed first.
set -euo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SERPANTINUM_DIR:-$HOME/.local/share/serpantinum/src}"
SYSTEM_DIR="$SRC/scripts/system"

if [ ! -f "$SYSTEM_DIR/serp_vpn.py" ]; then
    echo "Serpantinum is not installed ($SYSTEM_DIR not found). Install Serpantinum first." >&2
    exit 1
fi

# Keep a copy next to the install so the panel can reinstall without this drive.
KEEP="${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum/vpn-bundle"
if [ "$(realpath "$BUNDLE")" != "$(realpath -m "$KEEP")" ]; then
    mkdir -p "$KEEP"
    cp -f "$BUNDLE"/manifest.json "$BUNDLE"/SHA256SUMS "$BUNDLE"/*.tar.gz "$KEEP"/
    cp -f "$BUNDLE"/README.txt "$BUNDLE"/install-vpn-bundle.sh "$KEEP"/ 2>/dev/null || true
fi

python3 "$SYSTEM_DIR/serp_vpn.py" singbox-install --offline --bundle="$BUNDLE"
echo

if [ "${1:-}" = "--system" ]; then
    sudo python3 "$SYSTEM_DIR/serp_vpn_singbox.py" install-system --bundle="$BUNDLE"
    echo
fi
echo "VPN engine installed. Open Super+N -> VPN."
