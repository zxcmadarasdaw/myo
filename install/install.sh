#!/usr/bin/env bash

# This file also runs standalone when fetched by get.sh, before the modules
# and possibly Git are available.
detect_install_platform() {
    local release_file="$1" machine="$2"
    local ID="" ID_LIKE="" VERSION_ID=""
    if [ ! -r "$release_file" ]; then
        echo "Cannot read $release_file. The installer requires Linux /etc/os-release." >&2
        return 1
    fi
    . "$release_file"
    DISTRO_ID="$ID"
    DISTRO_VERSION="$VERSION_ID"

    case "$ID" in
        arch|cachyos|endeavouros|manjaro|garuda|arcolinux|archcraft|artix|blackarch|rebornos|mabox|blendos|parch|parchlinux|biglinux|archlabs|archman|alci|bluestar|archbang|archex|archstrike|athena|athenaos|chimeraos|ctlos|crystal|hefftorlinux|instantos|nyarch|obarun|hyperbola|parabola|salentos|snal|steamos|holo|stormos|tearch|xerolinux|axyl|omarchy)
            PM_NAME=pacman ;;
        fedora) PM_NAME=dnf ;;
        void) PM_NAME=void ;;
        rhel|centos|rocky|almalinux|ol|scientific|amzn)
            echo "Unsupported distribution: $ID." >&2
            return 1 ;;
        *)
            case " $ID_LIKE " in
                *" arch "*) PM_NAME=pacman ;;
                *" fedora "*) PM_NAME=dnf ;;
                *" void "*) PM_NAME=void ;;
                *) echo "Unsupported distribution: ${ID:-unknown}." >&2; return 1 ;;
            esac ;;
    esac

    if [[ "$PM_NAME" == dnf && -e /run/ostree-booted ]]; then
        echo "An RPM-OSTree deployment requires a different package installation flow." >&2
        return 1
    fi
    if [[ "$ID" == fedora && ! "$VERSION_ID" =~ ^[0-9]+$ ]]; then
        echo "Cannot determine a numbered Fedora release from $release_file." >&2
        return 1
    fi
    if [[ "$ID" == fedora && "$VERSION_ID" != 45 ]]; then
        echo "Fedora $VERSION_ID detected. This installer targets Fedora 45." >&2
    fi
    if [[ "$PM_NAME" == pacman && "$machine" != x86_64 ]]; then
        echo "The Arch installer and bundled Linux programs require x86_64 (detected $machine)." >&2
        return 1
    fi
    case "$PM_NAME" in
        void) PM_COMMAND=xbps-install ;;
        *) PM_COMMAND="$PM_NAME" ;;
    esac
    if ! command -v "$PM_COMMAND" >/dev/null; then
        echo "$ID requires $PM_COMMAND, but the command is missing." >&2
        return 1
    fi
}

check_install_space() {
    local path="$1" required_kib="$2" available
    while [ ! -e "$path" ] && [ "$path" != / ]; do
        path="$(dirname "$path")"
    done
    available="$(df -Pk -- "$path" | awk 'NR==2 {print $4}')"
    if [[ ! "$available" =~ ^[0-9]+$ ]] || (( available < required_kib )); then
        echo "Disk space check failed for $path: need ${required_kib} KiB, available ${available:-unknown} KiB." >&2
        return 1
    fi
}

bootstrap_git() {
    command -v git >/dev/null && return 0
    case "$PM_NAME" in
        pacman) sudo pacman -Syu --needed git ;;
        dnf) sudo dnf --disablerepo='terra*' install -y git ;;
        void) sudo xbps-install -Suy xbps && sudo xbps-install -Sy git ;;
    esac
}

installer_phase() {
    printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0
set -e

if [ "$EUID" -eq 0 ]; then
    echo "Run the installer as your desktop user. It calls sudo when required." >&2
    exit 1
fi
detect_install_platform /etc/os-release "$(uname -m)"

RAW_SLUG="${REPO_SLUG:-ilyamiro/serpantinum}"
REPO_SLUG="$(printf '%s' "$RAW_SLUG" | tr -d '\r\n\t ' | sed 's/[^a-zA-Z0-9_\/-]//g')"
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-installer"
export REPO_SLUG
export SERPANTINUM_INSTALLER=1

if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    INSTALL_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    PROJECT_ROOT="$(dirname "$INSTALL_DIR")"
else
    INSTALL_DIR=""
    PROJECT_ROOT=""
fi

if [[ -z "$PROJECT_ROOT" || ! -f "$PROJECT_ROOT/install/modules/deps.sh" || ! -d "$PROJECT_ROOT/src" ]]; then
    check_install_space "$CACHE_BASE" 524288
    bootstrap_git
    mkdir -p "$CACHE_BASE"
    checkout="$(mktemp -d "$CACHE_BASE/checkout.XXXXXX")"
    trap 'rm -rf -- "$checkout"' EXIT
    clone_options=()
    if [ -n "${SERPANTINUM_BRANCH:-}" ]; then
        clone_options+=(--branch "$SERPANTINUM_BRANCH")
    fi
    git clone "${clone_options[@]}" "https://github.com/${REPO_SLUG}.git" "$checkout"
    bash "$checkout/install/install.sh" "$@"
    exit
fi

export SERPANTINUM_DIR="$PROJECT_ROOT/src"
export I18N_DIR="$PROJECT_ROOT/src/assets/languages"

MODULES_DIR="$INSTALL_DIR/modules"

source "$PROJECT_ROOT/src/scripts/i18n.sh"
source "$MODULES_DIR/pm.sh"
source "$MODULES_DIR/deps.sh"
source "$MODULES_DIR/ski.sh"
source "$MODULES_DIR/daemons.sh"
source "$MODULES_DIR/audio.sh"
source "$MODULES_DIR/gamma.sh"
source "$MODULES_DIR/core.sh"
source "$MODULES_DIR/state.sh"
source "$MODULES_DIR/migrate.sh"
source "$MODULES_DIR/deploy.sh"
source "$MODULES_DIR/service.sh"
source "$MODULES_DIR/vpn.sh"
source "$MODULES_DIR/ui.sh"
source "$MODULES_DIR/verify.sh"

if [ "${1:-}" = "--vpn-check" ]; then
    check_vpn_components
    exit
fi

if [ "${1:-}" = "--vpn-only" ]; then
    install_vpn_components
    exit
fi

if [ "$PM_NAME" = pacman ] && {
    pacman -Q serpantinum >/dev/null 2>&1 || pacman -Q serpantinum-git >/dev/null 2>&1;
}; then
    echo "Serpantinum is installed as a pacman package. Update it through that installation method." >&2
    exit 1
fi

source_size="$(du -sk -- "$PROJECT_ROOT" | awk '{print $1}')"
[[ "$source_size" =~ ^[0-9]+$ ]] || { echo "Cannot measure the local checkout." >&2; exit 1; }
check_install_space "$HOME/.local/share" "$source_size"
check_install_space /usr 65536
check_install_space /var 65536

source "$PROJECT_ROOT/src/scripts/xdg_paths.sh"
install_log_dir="$(serpantinum_state_dir)"
mkdir -p "$install_log_dir"
exec 9>"${install_log_dir%/*}/.serpantinum-install.lock"
if ! flock -n 9; then
    echo "An installer is already using $install_log_dir." >&2
    exit 1
fi
INSTALL_LOG="$(mktemp "$install_log_dir/install.XXXXXX.log")"
trap 'status=$?; flock -u 9; cleanup_terminal; if (( status != 0 )); then printf "\nInstallation stopped during %s. Resolve the error and run the installer again. Log: %s\n" "$INSTALL_PHASE" "$INSTALL_LOG" >&2; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
INSTALL_PHASE=bootstrap
printf 'Installation log: %s\n' "$INSTALL_LOG"
printf 'Platform: %s %s (%s), provider: %s\n' "$DISTRO_ID" "${DISTRO_VERSION:-rolling}" "$(uname -m)" "$PM_NAME" | tee -a "$INSTALL_LOG"
exec 8>&1 7>&2
exec > >(tee -a "$INSTALL_LOG") 2>&1
bootstrap_installer_deps
exec 1>&8 2>&7
source "$MODULES_DIR/version.sh"
source "$MODULES_DIR/config.sh"

TELEMETRY_ID=$(get_telemetry_id)
ENABLE_TELEMETRY=$(get_telemetry_enabled)
OPT_SDDM=$(get_saved_preference OPT_SDDM "$OPT_SDDM")
SDDM_WAYLAND=$(get_saved_preference SDDM_WAYLAND "$SDDM_WAYLAND")
INSTALL_FULL_WALLPAPERS=$(get_saved_preference INSTALL_FULL_WALLPAPERS "$INSTALL_FULL_WALLPAPERS")

INSTALL_STATE=$(detect_install_state)
OLD_VERSION=$(get_installed_version)
TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG")
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")
OLD_COMMIT=$(get_installed_commit)

init_compositor_detection
INSTALL_PHASE=options
run_installer_ui
exec > >(tee -a "$INSTALL_LOG") 2>&1

TARGET_VERSION=$(get_target_version "$PROJECT_ROOT" "$REPO_SLUG")
TARGET_COMMIT=$(get_target_commit "$PROJECT_ROOT" "$REPO_SLUG")

if [ "$ENABLE_TELEMETRY" = true ] && [ -f "$MODULES_DIR/telemetry.sh" ]; then
    bash "$MODULES_DIR/telemetry.sh" --mode init --version "$TARGET_VERSION" --id "$TELEMETRY_ID" --enabled "$ENABLE_TELEMETRY"
fi

INSTALL_PHASE=dependencies
installer_phase "Checking dependencies for ${SELECTED_COMPOSITORS[*]}"
install_dependencies "$INSTALL_STATE" "$IS_REINSTALL" "${SELECTED_COMPOSITORS[@]}"
if [[ " ${SELECTED_COMPOSITORS[*]} " == *" hyprland "* ]]; then
    ensure_hyprland_lua_support
    check_hyprland_config "$PROJECT_ROOT/compositors/hyprland/hyprland.lua"
fi
INSTALL_PHASE=components
installer_phase "Installing Serpantinum components"
install_ski
install_audio_daemon
install_gamma_daemon
install_core_daemon

INSTALL_PHASE=deployment
installer_phase "Deploying shell and configuration"
deploy_package "$PROJECT_ROOT" "$OLD_COMMIT" "$TARGET_COMMIT" "$IS_REINSTALL" "$INSTALL_STATE" "${SELECTED_COMPOSITORS[@]}"
setup_sddm "$PROJECT_ROOT"
install_wallpapers "$INSTALL_FULL_WALLPAPERS"

WALLPAPER_DIR=$(get_wallpaper_dir)
init_serpantinum_config "$PROJECT_ROOT" "$WALLPAPER_DIR"
configure_ski_defaults "$SERP_NEW_SETTINGS"

INSTALL_PHASE=services
installer_phase "Checking desktop and VPN services"
setup_services
VPN_INSTALL_FAILED=false
if ! install_vpn_components; then
    FAILED_PKGS+=("VPN components")
    VPN_INSTALL_FAILED=true
fi
hand_over_from_easyeffects

INSTALL_PHASE=verification
installer_phase "Verifying installation"
verify_installation || true
if [ "$INSTALL_INCOMPLETE" = false ]; then
    if [ "$INSTALL_STATE" = legacy ]; then
        migrate_legacy
    fi
    write_version_state "$TARGET_VERSION" "$TARGET_COMMIT" "$TELEMETRY_ID" "$ENABLE_TELEMETRY" "${SELECTED_COMPOSITORS[*]}" "$OPT_SDDM" "$SDDM_WAYLAND" "$INSTALL_FULL_WALLPAPERS"
    if [[ "$INSTALL_STATE" == legacy || "$INSTALL_STATE" == fresh || "$IS_REINSTALL" == true ]]; then
        rm -f "$STATE_DIR/first_launch.done" "$HOME/.local/state/quickshell/first_launch.done"
    fi
fi

if [ "$ENABLE_TELEMETRY" = true ] && [ -f "$MODULES_DIR/telemetry.sh" ]; then
    bash "$MODULES_DIR/telemetry.sh" --mode done --version "$TARGET_VERSION" --old-version "$OLD_VERSION" --install-state "$INSTALL_STATE" --compositor "${SELECTED_COMPOSITORS[*]}" --id "$TELEMETRY_ID" --enabled "$ENABLE_TELEMETRY" --failed "${FAILED_PKGS[*]}"
fi

exec 1>&8 2>&7
printf 'Installation log: %s\n' "$INSTALL_LOG"
draw_completion_screen "$TARGET_VERSION" "$TARGET_COMMIT"
[ "$INSTALL_INCOMPLETE" = true ] && exit 1
exit 0
