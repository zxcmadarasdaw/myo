#!/usr/bin/env bash

PM_BOOTSTRAP_TOOLS=(jq curl git pciutils unzip fontconfig python3)
PM_EXTRA_PKGS=(polkit)
PM_AUDIO_BUILD_PKGS=(pkgconf pipewire)

# Logical package names used by the shared installer. Version/USE constraints
# are checked both against the installed database and by Portage's resolver.
pm_resolve_name() {
    case "$1" in
        jq|fastfetch) echo "app-misc/$1" ;;
        kitty) echo x11-terms/kitty ;;
        zbar) echo media-gfx/zbar ;;
        tesseract) echo app-text/tesseract ;;
        tesseract-data-eng) echo app-text/tesseract ;;
        wl-clipboard|satty|wf-recorder|qt6ct)
            echo "gui-apps/$1" ;;
        cliphist) echo app-misc/cliphist ;;
        matugen) echo x11-misc/matugen ;;
        gpu-screen-recorder) echo media-video/gpu-screen-recorder ;;
        quickshell) echo '>=gui-apps/quickshell-0.3.0' ;;
        hyprland|niri|sway|mangowm|umbriel) echo "gui-wm/$1" ;;
        weston) echo dev-libs/weston ;;
        qt6-multimedia) echo 'dev-qt/qtmultimedia:6[qml,pipewire]' ;;
        qt6-imageformats) echo dev-qt/qtimageformats:6 ;;
        qt6-wayland) echo dev-qt/qtwayland:6 ;;
        qt6-declarative) echo dev-qt/qtdeclarative:6 ;;
        qt6-svg) echo dev-qt/qtsvg:6 ;;
        ddcutil) echo app-misc/ddcutil ;;
        pciutils) echo sys-apps/pciutils ;;
        zip|unzip) echo "app-arch/$1" ;;
        curl) echo net-misc/curl ;;
        git) echo dev-vcs/git ;;
        fontconfig) echo media-libs/fontconfig ;;
        bluez) echo net-wireless/bluez ;;
        networkmanager) echo net-misc/networkmanager ;;
        pipewire) echo media-video/pipewire ;;
        pipewire-pulse) echo 'media-video/pipewire[sound-server]' ;;
        pipewire-alsa) echo 'media-video/pipewire[pipewire-alsa]' ;;
        wireplumber|ffmpeg) echo "media-video/$1" ;;
        libpulse) echo media-libs/libpulse ;;
        python|python3) echo dev-lang/python ;;
        imagemagick) echo media-gfx/imagemagick ;;
        file) echo sys-apps/file ;;
        pkgconf) echo dev-util/pkgconf ;;
        grim) echo gui-apps/grim ;;
        playerctl) echo media-sound/playerctl ;;
        xdg-desktop-portal-gtk) echo sys-apps/xdg-desktop-portal-gtk ;;
        power-profiles-daemon) echo sys-power/power-profiles-daemon ;;
        adwaita-icon-theme) echo x11-themes/adwaita-icon-theme ;;
        adw-gtk-theme) echo x11-themes/adw-gtk3 ;;
        sddm) echo gui-apps/sddm ;;
        polkit) echo sys-auth/polkit ;;
        *) printf 'No Gentoo mapping for %s\n' "$1" >&2; return 1 ;;
    esac
}

pm_is_installed() {
    local atom
    atom="$(pm_resolve_name "$1")" || return 2
    portageq has_version / "$atom"
}

pm_missing_pkgs() {
    local pkg status
    for pkg in "$@"; do
        status=0
        pm_is_installed "$pkg" || status=$?
        case "$status" in
            0) ;;
            1) printf '%s\n' "$pkg" ;;
            *) return "$status" ;;
        esac
    done
}

pm_emerge_transaction() {
    local pkg atom
    local atoms=()
    for pkg in "$@"; do
        atom="$(pm_resolve_name "$pkg")" || return 1
        if [[ " ${atoms[*]} " != *" $atom "* ]]; then atoms+=("$atom"); fi
    done
    local options=(--oneshot --autounmask=y --autounmask-write=n --autounmask-continue=n)
    if ! emerge --pretend --verbose "${options[@]}" "${atoms[@]}"; then
        echo 'Review the Portage output for missing ebuilds, KEYWORDS, masks or USE settings. Configure repositories and package-specific options manually, then retry.' >&2
        return 1
    fi
    sudo emerge --ask "${options[@]}" "${atoms[@]}" </dev/tty
}

pm_bootstrap_install() { pm_emerge_transaction "$@"; }

pm_install_batch() {
    pm_emerge_transaction "$@" || return 1
    PM_BATCH_LEFT=()
}

pm_install_pkg() { pm_emerge_transaction "$1"; }
pm_upgrade_quickshell() { pm_emerge_transaction quickshell; }
pm_upgrade_hyprland() { pm_emerge_transaction hyprland; }
