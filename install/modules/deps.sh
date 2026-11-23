#!/usr/bin/env bash

REQUIRED_PKGS=(
    "kitty" "zbar" "tesseract" "tesseract-data-eng"
    "wl-clipboard" "qt6-multimedia" "qt6-imageformats"
    "cliphist" "jq" "ddcutil"
    "bluez" "networkmanager" "matugen"
    "pipewire" "wireplumber" "pipewire-pulse" "pipewire-alsa" "libpulse" "python"
    "imagemagick" "file"
    "ffmpeg" "fastfetch" "quickshell"
    "grim" "playerctl" "satty" "xdg-desktop-portal-gtk" "power-profiles-daemon" "qt6-wayland"
    "qt6ct" "adwaita-icon-theme" "gpu-screen-recorder" "wf-recorder" "adw-gtk-theme"
)

FAILED_PKGS=()

suppress_tty_sleep() {
    setterm -blank 0 -powerdown 0 2>/dev/null || true
    printf '\033[9;0]' 2>/dev/null || true
}

bootstrap_installer_deps() {
    suppress_tty_sleep
    if declare -f pm_prepare_repos >/dev/null; then pm_prepare_repos; fi

    local missing=() pkg tool
    for pkg in "${PM_BOOTSTRAP_TOOLS[@]}"; do
        case "$pkg" in
            pciutils) tool=lspci ;;
            fontconfig) tool=fc-cache ;;
            *) tool="$pkg" ;;
        esac
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        pm_bootstrap_install "${missing[@]}" || return 1
    fi
}

install_fonts() (
    local target_fonts_dir="$HOME/.local/share/fonts/IosevkaNerdFont"
    local font_cache font manifest="$target_fonts_dir/.serpantinum-fonts" complete=false
    if [ -s "$manifest" ] && [ ! -L "$manifest" ]; then
        complete=true
        while IFS= read -r font; do
            if [[ "$font" = */* || "$font" != *.ttf ]] || [ ! -s "$target_fonts_dir/$font" ]; then
                complete=false
                break
            fi
        done < "$manifest"
    fi
    if [ "$complete" = false ]; then
        font_cache="$(mktemp -d)" || return 1
        trap 'rm -rf -- "$font_cache"' EXIT
        echo -e "\n\e[36m[ INFO ]\e[0m Downloading Iosevka Nerd Font..."
        curl -fL --connect-timeout 15 --retry 3 "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Iosevka.zip" -o "$font_cache/Iosevka.zip" || return 1
        unzip -q "$font_cache/Iosevka.zip" '*.ttf' -d "$font_cache" || return 1
        shopt -s nullglob
        local fonts=("$font_cache"/*.ttf)
        [ "${#fonts[@]}" -gt 0 ] || { echo 'Iosevka archive did not contain fonts.' >&2; return 1; }
        mkdir -p "$target_fonts_dir" || return 1
        for font in "${fonts[@]}"; do
            cp -n -- "$font" "$target_fonts_dir/" || return 1
            printf '%s\n' "${font##*/}" >> "$font_cache/fonts" || return 1
        done
        replace_config_file "$font_cache/fonts" "$manifest" || return 1
    fi
    fc-cache -f "$HOME/.local/share/fonts"
)

configure_qt_icon_theme() {
    local icon_theme="Adwaita"
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    local qtct

    for qtct in qt6ct; do
        local conf="$config_home/$qtct/$qtct.conf"
        [ -d "$config_home/$qtct" ] || mkdir -p "$config_home/$qtct" 2>/dev/null || continue
        if [ ! -e "$conf" ] && [ ! -L "$conf" ]; then
            printf '[Appearance]\nicon_theme=%s\n' "$icon_theme" > "$conf"
        fi
    done

    # The supplied compositor configurations choose their own Qt platform theme.
    # A user-wide override would also apply to KDE and other desktop sessions.
}

compositor_package_name() {
    case "$1" in
        mango) echo "mangowm" ;;
        *) echo "$1" ;;
    esac
}

find_sddm_binary() {
    local name="$1" dir
    local IFS=:
    for dir in ${SDDM_SEARCH_PATH:-/usr/local/bin:/usr/bin:/bin}; do
        if [ -x "$dir/$name" ]; then
            echo "$dir/$name"
            return 0
        fi
    done
    return 1
}

sddm_has_xorg() {
    find_sddm_binary Xorg >/dev/null || find_sddm_binary X >/dev/null
}

sddm_packages() {
    printf '%s\n' sddm qt6-declarative qt6-svg "${PM_SDDM_EXTRA_PKGS[@]}"
    if [ "$SDDM_WAYLAND" = true ] \
        && ! find_sddm_binary kwin_wayland >/dev/null \
        && ! find_sddm_binary weston >/dev/null \
        && ! sddm_has_xorg; then
        echo weston
    fi
}

MIN_QUICKSHELL_VERSION="0.3.0"

quickshell_version() {
    quickshell --version 2>/dev/null | sed -n 's/^[Qq]uickshell \([0-9][0-9.]*\).*/\1/p' | head -n 1
}

quickshell_is_current() {
    local version
    version="$(quickshell_version)"
    [ -n "$version" ] && [ "$(printf '%s\n%s\n' "$MIN_QUICKSHELL_VERSION" "$version" | sort -V | head -n 1)" = "$MIN_QUICKSHELL_VERSION" ]
}

ensure_quickshell_version() {
    command -v quickshell >/dev/null 2>&1 || return 0
    quickshell_is_current && return 0

    echo -e "\n\e[33m  $(t "installer.deps.quickshell_outdated" "version=$(quickshell_version)" "minimum=$MIN_QUICKSHELL_VERSION")\e[0m"
    if declare -f pm_upgrade_quickshell >/dev/null; then pm_upgrade_quickshell || true; fi
    hash -r

    if ! quickshell_is_current; then
        echo -e "\n\e[31m  $(t "installer.deps.quickshell_still_old" "minimum=$MIN_QUICKSHELL_VERSION")\e[0m"
    fi
}

install_dependencies() {
    local install_state="${1:-$INSTALL_STATE}"
    local is_reinstall="${2:-$IS_REINSTALL}"
    shift 2 2>/dev/null || true
    local compositors=("$@")

    local target_list=("${REQUIRED_PKGS[@]}")
    for comp in "${compositors[@]}"; do
        target_list+=("$(compositor_package_name "$comp")")
    done

    if [ "$OPT_SDDM" = true ]; then
        local sddm_pkgs=()
        mapfile -t sddm_pkgs < <(sddm_packages)
        target_list+=("${sddm_pkgs[@]}")
    fi
    target_list+=("${PM_EXTRA_PKGS[@]}")

    if [[ ("$install_state" == "fresh" || "$install_state" == "legacy") && "$is_reinstall" != "true" ]] &&
        declare -f pm_full_upgrade >/dev/null; then
        pm_full_upgrade
    fi

    local missing_raw
    missing_raw=$(pm_missing_pkgs "${target_list[@]}") || return 1

    local MISSING_PKGS=()
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && MISSING_PKGS+=("$pkg")
    done <<< "$missing_raw"

    FAILED_PKGS=()

    if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
        echo -e "\n\e[32m  $(t "installer.deps.all_installed")\e[0m\n"
    else
        echo -e "\n\e[33m  $(t "installer.deps.missing_count" "count=${#MISSING_PKGS[@]}")\e[0m"
        echo -e "\n\e[36m[ INFO ]\e[0m $(t "installer.deps.installing_title")\n"

        local SAFE_JOBS=$(( $(nproc) / 2 ))
        [[ $SAFE_JOBS -lt 1 ]] && SAFE_JOBS=1
        [[ $SAFE_JOBS -gt 4 ]] && SAFE_JOBS=4

        if declare -f pm_install_batch >/dev/null; then
            pm_install_batch "${MISSING_PKGS[@]}" || return 1
            MISSING_PKGS=("${PM_BATCH_LEFT[@]}")
        fi

        for pkg in "${MISSING_PKGS[@]}"; do
            echo -e "\n\e[36m=================================================================\e[0m"
            echo -e "\e[34m::\e[0m \e[1m$(t "installer.deps.installing_pkg" "pkg=$pkg")\e[0m"
            echo -e "\e[36m=================================================================\e[0m"

            if pm_install_pkg "$pkg" "$SAFE_JOBS"; then
                echo -e "\n\e[32m[ OK ] $(t "installer.deps.install_ok" "pkg=$pkg")\e[0m"
            else
                echo -e "\n\e[31m[ FAILED ] $(t "installer.deps.install_failed" "pkg=$pkg")\e[0m"
                FAILED_PKGS+=("$pkg")
            fi
            sleep 0.2
        done
    fi

    ensure_quickshell_version
    install_fonts || FAILED_PKGS+=("Iosevka Nerd Font")
    configure_qt_icon_theme
}
