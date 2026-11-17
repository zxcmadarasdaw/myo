#!/usr/bin/env bash
# VPN, TUN mode (stage 2): root helper, systemd unit and polkit files.
# Installs:
#   /usr/libexec/serpantinum/serp-vpn-root               (root:root 755, from src/scripts/system/serp_vpn_root.py)
#   /usr/libexec/serpantinum/serp-vpn-packages           (root:root 755, admin authentication required)
#   /etc/systemd/system/serpantinum-vpn.service          (not enabled; the shell starts it on demand)
#   /usr/share/polkit-1/actions/org.serpantinum.vpn.policy
#   /etc/polkit-1/rules.d/49-serpantinum-vpn.rules       (only for the user running the installer)
#   /etc/serpantinum-vpn/                                (700; config.json is written later by the helper, 600)
# Fedora gets sing-box and missing VPN dependencies from the local bundle.

VPN_HELPER_DST="/usr/libexec/serpantinum/serp-vpn-root"
VPN_PACKAGES_DST="/usr/libexec/serpantinum/serp-vpn-packages"
VPN_UNIT_DST="/etc/systemd/system/serpantinum-vpn.service"
VPN_POLICY_DST="/usr/share/polkit-1/actions/org.serpantinum.vpn.policy"
VPN_RULES_DST="/etc/polkit-1/rules.d/49-serpantinum-vpn.rules"

vpn_source_bundle() {
    local dir
    for dir in "$PROJECT_ROOT/vpn-bundle" "$PROJECT_ROOT/dist/vpn-bundle" \
        "${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum/vpn-bundle"; do
        if [ "${1:-}" = "--skip-shipped" ] && [ "$dir" = "$PROJECT_ROOT/vpn-bundle" ]; then
            continue
        fi
        if [ -f "$dir/manifest.json" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

install_vpn_bundle() {
    local bundle="$1"
    shift
    echo "Installing VPN components from $bundle (offline)"
    SERPANTINUM_DIR="$PROJECT_ROOT/src" bash "$PROJECT_ROOT/packaging/vpn-bundle/install-vpn-bundle.sh" --bundle="$bundle" "$@"
}

# Prints the polkit rules for one user; refuses anything that is not a plain user name.
vpn_render_polkit_rules() {
    local user="$1" template="$2"
    if [[ ! "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        return 1
    fi
    sed "s/@USER@/$user/g" "$template"
}

install_vpn_service() {
    local root="${PROJECT_ROOT:?}"
    local sys_dir="$root/install/system/vpn"
    local user
    local rendered
    user="$(id -un)" || return 1

    echo -e "\n\e[36m[ INFO ]\e[0m $(t "installer.vpn.installing")"
    if [ "$(detect_init_system)" != "systemd" ] || [ ! -d /usr/share/polkit-1 ]; then
        echo -e "\e[33m[ WARN ]\e[0m $(t "installer.vpn.skipped")"
        return 1
    fi
    if ! rendered="$(vpn_render_polkit_rules "$user" "$sys_dir/49-serpantinum-vpn.rules.in")"; then
        echo -e "\e[33m[ WARN ]\e[0m $(t "installer.vpn.bad_user" "user=$user")"
        return 1
    fi

    if sudo install -Dm755 -o root -g root "$root/src/scripts/system/serp_vpn_root.py" "$VPN_HELPER_DST" \
        && sudo install -Dm644 -o root -g root "$root/src/scripts/system/serp_vpn_singbox.py" "$(dirname "$VPN_PACKAGES_DST")/serp_vpn_singbox.py" \
        && sudo install -Dm644 -o root -g root "$root/src/scripts/system/serp_vpn_singbox.lock.json" "$(dirname "$VPN_PACKAGES_DST")/serp_vpn_singbox.lock.json" \
        && sudo install -Dm755 -o root -g root "$root/src/scripts/system/serp_vpn_packages.py" "$VPN_PACKAGES_DST" \
        && sudo install -Dm644 -o root -g root "$sys_dir/serpantinum-vpn.service" "$VPN_UNIT_DST" \
        && sudo install -Dm644 -o root -g root "$sys_dir/org.serpantinum.vpn.policy" "$VPN_POLICY_DST" \
        && sudo mkdir -p "$(dirname "$VPN_RULES_DST")" \
        && printf '%s\n' "$rendered" | sudo tee "$VPN_RULES_DST" >/dev/null \
        && sudo chown root:root "$VPN_RULES_DST" && sudo chmod 644 "$VPN_RULES_DST" \
        && sudo install -dm700 -o root -g root /etc/serpantinum-vpn; then
        sudo timeout 20s systemctl daemon-reload || return 1
        echo -e "\e[32m[ OK ] $(t "installer.vpn.installed" "user=$user")\e[0m"
    else
        echo -e "\e[31m[ FAILED ] $(t "installer.vpn.failed")\e[0m"
        return 1
    fi
}

vpn_verify_unit_permission() {
    local pid="$BASHPID" info
    local fields=()
    IFS= read -r info < "/proc/$pid/stat" || return 1
    read -r -a fields <<< "${info##*) }"
    # Action details require a trusted caller. The subject of the check is
    # still the installer user's live process, identified by PID, start time and uid.
    sudo -n /usr/bin/timeout 8s /usr/bin/pkcheck \
        --process "$pid,${fields[19]},$UID" --action-id org.freedesktop.systemd1.manage-units \
        --detail unit serpantinum-vpn.service --detail verb restart || {
        echo "Polkit did not authorize this session to control the VPN unit. Retry from an active local session." >&2
        return 1
    }
}

vpn_prepare_linux() {
    local bundle machine unit_state
    local engine_check=(system-engine-check)
    machine="$(uname -m)" || return 1
    case "$machine" in
        x86_64|aarch64) ;;
        *) echo "VPN installation does not support architecture $machine" >&2; return 1 ;;
    esac
    echo "Preparing VPN for $DISTRO_ID ${DISTRO_VERSION:-rolling} / $machine"
    if [ "$DISTRO_ID" = fedora ]; then
        engine_check+=(--bundled)
        if grep -Eq '(^| )(rd\.live\.image|root=live:)' /proc/cmdline || [ -d /run/initramfs/live ]; then
            echo "Fedora Live detected. With a nonpersistent overlay, repeat setup after reboot."
        fi
    fi
    if ! bundle="$(vpn_source_bundle)"; then
        echo "Offline VPN bundle missing. Restore vpn-bundle/ from the matching Serpantinum checkout."
        return 1
    fi
    install_vpn_bundle "$bundle" --verify-bundle || return 1
    unit_state="$(timeout 6s systemctl show serpantinum-vpn.service -p ActiveState --value 2>/dev/null)" || true
    case "$unit_state" in
        active)
            echo "Serpantinum TUN is active. Checking the current system engine without restarting it."
            timeout 5s python3 "$PROJECT_ROOT/src/scripts/system/serp_vpn.py" "${engine_check[@]}" || {
                echo "Disconnect TUN before repairing the system engine."
                return 1
            }
            ;;
        activating|deactivating|reloading)
            echo "Serpantinum TUN is changing state. Wait for it to finish before repairing the components."
            return 1
            ;;
        *)
            if [ ! -c /dev/net/tun ] && command -v modprobe >/dev/null; then
                sudo timeout 10s modprobe tun || echo "Could not load the TUN kernel module."
            fi
            if [ ! -c /dev/net/tun ]; then
                echo "TUN is unavailable: /dev/net/tun must be a character device."
            fi
            install_vpn_service || return 1
            install_vpn_bundle "$bundle" --system --yaml || return 1
            ;;
    esac
    sudo -v && vpn_verify_unit_permission
}

check_vpn_components() {
    local bundle status=0
    local engine_check=(system-engine-check)
    if [ "$DISTRO_ID" = fedora ]; then engine_check+=(--bundled); fi
    if bundle="$(vpn_source_bundle)"; then
        install_vpn_bundle "$bundle" --verify-bundle || status=$?
    else
        echo "Offline VPN bundle missing. Restore vpn-bundle/ from the matching checkout."
        status=1
    fi
    if [ "$status" -eq 0 ]; then
        timeout 5s python3 "$PROJECT_ROOT/src/scripts/system/serp_vpn.py" "${engine_check[@]}" || status=$?
    fi
    timeout 65s python3 "$PROJECT_ROOT/src/scripts/system/serp_vpn.py" verify-install \
        "--prepare-status=$status"
}

install_vpn_components() (
    set -o pipefail
    local bundle prep_status=0 check_status=0
    if [[ "$DISTRO_ID" != fedora && "$PM_NAME" != pacman ]]; then
        # Keep the pre-existing service and optional local bundle on other distros.
        # The payload shipped in a Git checkout is for Fedora.
        install_vpn_service || true
        if bundle="$(vpn_source_bundle --skip-shipped)"; then
            if [ -x "$VPN_PACKAGES_DST" ] && [ -f "$VPN_UNIT_DST" ]; then
                install_vpn_bundle "$bundle" --system || return 1
            else
                install_vpn_bundle "$bundle" || return 1
            fi
        fi
        return 0
    fi
    if [ "$PM_NAME" = pacman ]; then
        local missing missing_packages=()
        missing="$(pm_missing_pkgs polkit python-yaml iproute2 nftables)" || return 1
        if [ -n "$missing" ]; then
            mapfile -t missing_packages <<< "$missing"
            pm_install_batch "${missing_packages[@]}" || return 1
        fi
    fi

    local state="${SERP_VPN_STATE_DIR:-${QS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum}/vpn}"
    umask 077
    mkdir -p "$state" || return 1
    echo "VPN setup log: $state/components-install.log"
    trap 'echo "VPN setup cancelled. Retry with bash install/install.sh --vpn-only." | tee -a "$state/components-install.log" >&2; exit 130' INT TERM
    vpn_prepare_linux 2>&1 | tee -a "$state/components-install.log" || prep_status=$?
    timeout 65s python3 "$PROJECT_ROOT/src/scripts/system/serp_vpn.py" verify-install \
        "--prepare-status=$prep_status" 2>&1 | tee -a "$state/components-install.log" || check_status=$?
    if [ "$prep_status" -ne 0 ] || [ "$check_status" -ne 0 ]; then
        echo "VPN components: FAILED. See $state/components-install.log. Retry with bash install/install.sh --vpn-only." >&2
        return 1
    fi
    echo "VPN components: READY"
)
