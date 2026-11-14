#!/usr/bin/env bash
# VPN, TUN mode (stage 2): root helper, systemd unit and polkit files.
# Installs:
#   /usr/libexec/serpantinum/serp-vpn-root               (root:root 755, from src/scripts/system/serp_vpn_root.py)
#   /etc/systemd/system/serpantinum-vpn.service          (not enabled; the shell starts it on demand)
#   /usr/share/polkit-1/actions/org.serpantinum.vpn.policy
#   /etc/polkit-1/rules.d/49-serpantinum-vpn.rules       (only for the user running the installer)
#   /etc/serpantinum-vpn/                                (700; config.json is written later by the helper, 600)
# sing-box itself is not installed here (see docs/configure/vpn.md).

VPN_HELPER_DST="/usr/libexec/serpantinum/serp-vpn-root"
VPN_UNIT_DST="/etc/systemd/system/serpantinum-vpn.service"
VPN_POLICY_DST="/usr/share/polkit-1/actions/org.serpantinum.vpn.policy"
VPN_RULES_DST="/etc/polkit-1/rules.d/49-serpantinum-vpn.rules"

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
    local user="${SUDO_USER:-${USER:-$(id -un)}}"
    local rendered

    echo -e "\n\e[36m[ INFO ]\e[0m $(t "installer.vpn.installing")"
    if [ "$(detect_init_system)" != "systemd" ] || [ ! -d /usr/share/polkit-1 ]; then
        echo -e "\e[33m[ WARN ]\e[0m $(t "installer.vpn.skipped")"
        return 0
    fi
    if ! rendered="$(vpn_render_polkit_rules "$user" "$sys_dir/49-serpantinum-vpn.rules.in")"; then
        echo -e "\e[33m[ WARN ]\e[0m $(t "installer.vpn.bad_user" "user=$user")"
        return 0
    fi

    if sudo install -Dm755 -o root -g root "$root/src/scripts/system/serp_vpn_root.py" "$VPN_HELPER_DST" \
        && sudo install -Dm644 -o root -g root "$sys_dir/serpantinum-vpn.service" "$VPN_UNIT_DST" \
        && sudo install -Dm644 -o root -g root "$sys_dir/org.serpantinum.vpn.policy" "$VPN_POLICY_DST" \
        && sudo mkdir -p "$(dirname "$VPN_RULES_DST")" \
        && printf '%s\n' "$rendered" | sudo tee "$VPN_RULES_DST" >/dev/null \
        && sudo chown root:root "$VPN_RULES_DST" && sudo chmod 644 "$VPN_RULES_DST" \
        && sudo install -dm700 -o root -g root /etc/serpantinum-vpn; then
        sudo systemctl daemon-reload 2>/dev/null || true
        # an update while TUN is on: pick up the new helper/unit
        sudo systemctl try-restart serpantinum-vpn.service 2>/dev/null || true
        echo -e "\e[32m[ OK ] $(t "installer.vpn.installed" "user=$user")\e[0m"
    else
        echo -e "\e[31m[ FAILED ] $(t "installer.vpn.failed")\e[0m"
        FAILED_PKGS+=("serpantinum-vpn")
    fi
}
