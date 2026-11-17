#!/usr/bin/env bash
set -euo pipefail

BUNDLE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="${SERPANTINUM_DIR:-$HOME/.local/share/serpantinum/src}/scripts/system"
KEEP="${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum/vpn-bundle"
SYSTEM_HELPER=/usr/libexec/serpantinum/serp-vpn-packages
NEED_SYSTEM=false
NEED_YAML=false
CHECK=false
VERIFY_BUNDLE=false
for arg in "$@"; do
    case "$arg" in
        --system) NEED_SYSTEM=true ;;
        --yaml) NEED_YAML=true ;;
        --check) CHECK=true ;;
        --verify-bundle) VERIFY_BUNDLE=true ;;
        --bundle=*) BUNDLE="$(realpath "${arg#--bundle=}")" ;;
        *) echo "Usage: $0 [--system] [--yaml] [--check|--verify-bundle]" >&2; exit 2 ;;
    esac
done

if [ ! -f "$SYSTEM_DIR/serp_vpn_singbox.py" ]; then
    echo "Install this version of Serpantinum first. VPN backend not found at $SYSTEM_DIR." >&2
    exit 1
fi

archive="$(timeout 15s python3 "$SYSTEM_DIR/serp_vpn_singbox.py" bundle-archive --verify --bundle="$BUNDLE")"
(cd "$BUNDLE" && timeout 120s sha256sum --strict --check --quiet SHA256SUMS)
if [ "$VERIFY_BUNDLE" = true ]; then
    echo "Offline VPN bundle verified."
    exit 0
fi

ID="" ID_LIKE="" VERSION_ID=""
. /etc/os-release
is_arch=false
case " $ID $ID_LIKE " in
    *" arch "*|*" cachyos "*) is_arch=true ;;
esac

install_dependencies() {
    local needed=() package filename machine
    if [ "$is_arch" = true ]; then
        if [ "$NEED_SYSTEM" = true ]; then needed+=(iproute2 nftables polkit); fi
        if [ "$NEED_YAML" = true ]; then needed+=(python-yaml); fi
        local missing=()
        for package in "${needed[@]}"; do
            pacman -T "$package" >/dev/null || missing+=("$package")
        done
        if [ "${#missing[@]}" -gt 0 ]; then
            printf 'Missing Arch VPN packages: %s\n' "${missing[*]}" >&2
            printf 'Install them with: sudo pacman -Syu --needed %s\n' "${missing[*]}" >&2
            return 1
        fi
        return 0
    fi
    if [ "$NEED_SYSTEM" = true ]; then
        needed+=(iproute nftables)
    fi
    if [ "$NEED_YAML" = true ]; then
        needed+=(python3-pyyaml)
    fi
    [ "${#needed[@]}" -gt 0 ] || return 0
    if [ "$ID" != fedora ]; then
        echo "Automatic dependency setup for this kit supports Fedora and Arch-based distributions." >&2
        return 1
    fi
    if rpm -q --quiet "${needed[@]}"; then
        return 0
    fi
    machine="$(uname -m)"
    if [ "$VERSION_ID/$machine" != '45/x86_64' ] || [ ! -r "$BUNDLE/rpms/packages.tsv" ]; then
        echo "Missing dependencies (${needed[*]}). This RPM kit supports Fedora 45 x86_64." >&2
        return 1
    fi
    local rpms=()
    while IFS=$'\t' read -r package filename; do
        [[ "$package" =~ ^[a-zA-Z0-9_-]+$ && "$filename" =~ ^[a-zA-Z0-9_.+-]+\.rpm$ ]] || return 1
        if ! rpm -q --quiet "$package"; then
            rpms+=("$BUNDLE/rpms/$filename")
        fi
    done < "$BUNDLE/rpms/packages.tsv"
    [ "${#rpms[@]}" -gt 0 ] || return 1
    printf 'Installing Fedora VPN dependencies from local signed RPMs: %s\n' "${needed[*]}"
    local confirmation=--assumeyes
    if [ "${SERPANTINUM_MANAGED_VPN:-false}" = true ]; then confirmation=--setopt=assumeyes=False; fi
    sudo /usr/bin/timeout -k 15s 6m /usr/bin/dnf5 "$confirmation" --no-plugins --disable-repo='*' \
        --setopt=localpkg_gpgcheck=True --setopt=install_weak_deps=False --setopt=allow_downgrade=False \
        install "${rpms[@]}" || return 1
    rpm -q --quiet "${needed[@]}"
}

check_configs() {
    local managed="${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum/vpn/bin/sing-box" binary
    binary="$(python3 - "$SYSTEM_DIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from serp_vpn import singbox_bin
print(singbox_bin())
PY
)"
    [ -x "${binary:-$managed}" ] || { echo 'Install the Proxy engine first.' >&2; return 1; }
    timeout 15s "${binary:-$managed}" check -c "$BUNDLE/proxy.check.json"
    if [ "$NEED_SYSTEM" = true ]; then
        [ -c /dev/net/tun ] || { echo 'TUN device /dev/net/tun is unavailable.' >&2; return 1; }
        command -v ip >/dev/null && command -v nft >/dev/null || { echo 'TUN requires iproute and nftables.' >&2; return 1; }
        if ! timeout 10s systemctl show serpantinum-vpn.service -p LoadState --value | grep -qx loaded; then
            echo 'The Serpantinum systemd VPN service is unavailable.' >&2
            return 1
        fi
        if ! timeout 10s systemctl show serpantinum-vpn.service -p CapabilityBoundingSet --value | grep -qw cap_net_admin; then
            echo 'The Serpantinum VPN unit needs CAP_NET_ADMIN.' >&2
            return 1
        fi
        binary=/usr/local/bin/sing-box
        [ -x "$binary" ] || binary=/usr/bin/sing-box
        timeout 15s "$binary" check -c "$BUNDLE/tun.check.json"
    fi
    echo 'VPN configuration checks passed.'
}

if [ "$CHECK" = true ]; then
    check_configs
    exit 0
fi

install_dependencies
if [ "$NEED_SYSTEM" = false ]; then
    timeout 120s python3 "$SYSTEM_DIR/serp_vpn.py" singbox-install --offline --ensure --bundle="$BUNDLE"
fi
if [ "$BUNDLE" != "$(realpath -m "$KEEP")" ]; then
    mkdir -p "$KEEP"
    cp -f "$BUNDLE/proxy.check.json" "$BUNDLE/tun.check.json" "$BUNDLE/README.txt" \
        "$BUNDLE/install-vpn-bundle.sh" "$KEEP/"
    # A multi-architecture bundle must remain complete so SHA256SUMS still works.
    cp -f "$BUNDLE"/*.tar.gz "$KEEP/"
    if [ -d "$BUNDLE/rpms" ]; then cp -r "$BUNDLE/rpms" "$KEEP/"; fi
    for name in SOURCES.md LICENSE.sing-box; do
        if [ -f "$BUNDLE/$name" ]; then cp -f "$BUNDLE/$name" "$KEEP/"; fi
    done
    cp -f "$BUNDLE/SHA256SUMS" "$BUNDLE/manifest.json" "$KEEP/"
fi

if [ "$NEED_SYSTEM" = true ]; then
    [ -x "$SYSTEM_HELPER" ] || { echo 'Update Serpantinum to install its system VPN helper.' >&2; exit 1; }
    engine_check=(system-engine-check)
    if [ "$is_arch" = false ]; then engine_check+=(--bundled); fi
    if ! timeout 5s python3 "$SYSTEM_DIR/serp_vpn.py" "${engine_check[@]}"; then
        sudo "$SYSTEM_HELPER" offline-engine < "$archive"
    fi
fi
echo 'Offline VPN component files installed.'
