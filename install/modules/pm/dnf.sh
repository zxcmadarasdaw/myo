#!/usr/bin/env bash

PM_BOOTSTRAP_TOOLS=(fzf jq curl git pciutils unzip fontconfig)
PM_QUEUE_WORKER="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../native_packages.py"
source "$(dirname "$PM_QUEUE_WORKER")/modules/download_queue.sh"

PM_EXTRA_PKGS=(jetbrains-mono-fonts fontawesome-6-free-fonts xdg-user-dirs xwayland-satellite pipewire-utils pulseaudio-utils)
PM_SDDM_EXTRA_PKGS=(sddm-wayland-generic adwaita-cursor-theme)
PM_SDDM_WAYLAND_DEFAULT=true
PM_SDDM_CURSOR_FIX=true
PM_AUDIO_BUILD_PKGS=(gcc-c++ make pkgconf-pkg-config pipewire-devel)

declare -A PM_PKG_MAP=(
    [kitty]="kitty"
    [zbar]="zbar"
    [tesseract]="tesseract"
    [tesseract-data-eng]="tesseract-langpack-eng"
    [wl-clipboard]="wl-clipboard"
    [qt6-multimedia]="qt6-qtmultimedia"
    [qt6-imageformats]="qt6-qtimageformats"
    [cliphist]="cliphist"
    [jq]="jq"
    [ddcutil]="ddcutil"
    [bluez]="bluez"
    [networkmanager]="NetworkManager"
    [matugen]="matugen"
    [pipewire]="pipewire"
    [wireplumber]="wireplumber"
    [pipewire-pulse]="pipewire-pulseaudio"
    [pipewire-alsa]="pipewire-alsa"
    [libpulse]="pulseaudio-libs"
    [python]="python3"
    [imagemagick]="ImageMagick"
    [file]="file"
    [ffmpeg]="ffmpeg-free|ffmpeg"
    [fastfetch]="fastfetch"
    [quickshell]="quickshell"
    [grim]="grim"
    [playerctl]="playerctl"
    [satty]="satty"
    [xdg-desktop-portal-gtk]="xdg-desktop-portal-gtk"
    [power-profiles-daemon]="ppd-service"
    [qt6-wayland]="qt6-qtwayland"
    [qt6ct]="qt6ct"
    [adwaita-icon-theme]="adwaita-icon-theme"
    [gpu-screen-recorder]="gpu-screen-recorder"
    [wf-recorder]="wf-recorder"
    [adw-gtk-theme]="adw-gtk3-theme"
    [hyprland]="hyprland"
    [niri]="niri"
    [sway]="sway"
    [mangowm]="mangowm"
    [umbriel]="umbriel-nightly"
    [sddm]="sddm"
    [qt6-declarative]="qt6-qtdeclarative"
    [qt6-svg]="qt6-qtsvg"
)

declare -A PM_COPR_MAP=(
    [quickshell]="errornointernet/quickshell"
    [hyprland]="mineiro/hyprland"
    [cliphist]="mecattaf/duoRPM"
    [gpu-screen-recorder]="arabianq/gpu-screen-recorder"
)
# The original Hyprland COPR has an empty Fedora 45 repository.
if [ "${DISTRO_VERSION:-}" = 45 ]; then
    PM_COPR_MAP[hyprland]="sdegler/hyprland"
fi

declare -A PM_TERRA_MAP=(
    [mangowm]=1
    [umbriel]=1
)

PM_YUM_REPOS_DIR="${PM_YUM_REPOS_DIR:-/etc/yum.repos.d}"
PM_USE_TERRA=false

# Ids of the Terra repositories configured on this system (terra,
# terra-extras, ...). They exist once terra-release was installed, e.g. by an
# earlier MangoWC install.
pm_terra_repo_ids() {
    local f
    for f in "$PM_YUM_REPOS_DIR"/*.repo; do
        [ -f "$f" ] || continue
        sed -n 's/^[[:space:]]*\[\(terra[^]]*\)\][[:space:]]*$/\1/p' "$f"
    done
}

# Terra is needed only for the packages in PM_TERRA_MAP (MangoWC). dnf aborts
# every transaction when an enabled repository cannot be loaded, so a configured
# but unreachable Terra repo broke the Hyprland install too. Every installer
# dnf call excludes Terra unless PM_USE_TERRA=true (set only while installing a
# PM_TERRA_MAP package).
pm_dnf_repo_opts() {
    PM_DNF_OPTS=()
    [ "$PM_USE_TERRA" = true ] && return 0
    local id
    while IFS= read -r id; do
        [ -n "$id" ] && PM_DNF_OPTS+=("--disablerepo=$id")
    done < <(pm_terra_repo_ids)
}

pm_dnf() {
    local PM_DNF_OPTS
    pm_dnf_repo_opts
    local operation="" item refresh=() queue_targets=() queue_options=()
    for item in "$@"; do
        case "$item" in
            install|upgrade) operation="$item" ;;
            -y|--assumeyes) ;;
            --refresh) refresh=(--refresh) ;;
            -*) queue_options+=("$item") ;;
            *) queue_targets+=("$item") ;;
        esac
    done
    if [ -n "$operation" ] && [ ${#queue_options[@]} -eq 0 ]; then
        local repo_args=()
        for item in "${PM_DNF_OPTS[@]}"; do repo_args+=("--repo-option=$item"); done
        pm_queue_run dnf --operation "$operation" "${repo_args[@]}" "${refresh[@]}" -- "${queue_targets[@]}"
        return
    fi
    if [ "${MANAGED_INSTALL:-false}" = true ]; then
        local arg args=()
        for arg in "$@"; do
            case "$arg" in -y|--assumeyes) ;; *) args+=("$arg");; esac
        done
        printf 'Running:'
        printf ' %q' sudo dnf "${PM_DNF_OPTS[@]}" --setopt=assumeyes=False "${args[@]}"
        printf '\n'
        sudo dnf "${PM_DNF_OPTS[@]}" --setopt=assumeyes=False "${args[@]}"
        return
    fi
    sudo dnf "${PM_DNF_OPTS[@]}" "$@"
}

pm_dnf_query() {
    local PM_DNF_OPTS
    pm_dnf_repo_opts
    if [ "${MANAGED_INSTALL:-false}" = true ]; then
        printf 'Repository lookup:' >&2
        printf ' %q' dnf "${PM_DNF_OPTS[@]}" "$@" >&2
        printf '\n' >&2
    fi
    timeout 75s dnf "${PM_DNF_OPTS[@]}" "$@" </dev/null || {
        local status=$?
        if [ "$status" = 124 ]; then echo 'DNF repository lookup timed out. Check the connection and enabled repositories.' >&2; fi
        return "$status"
    }
}

PM_MATUGEN_MIN_MAJOR=4
PM_MATUGEN_REPO="InioX/matugen"

declare -A PM_RELEASE_MAP=(
    [matugen]="https://github.com/InioX/matugen/releases/download/v4.2.0/matugen-4.2.0-x86_64.tar.gz"
    [satty]="https://github.com/gabm/Satty/releases/latest/download/satty-x86_64-unknown-linux-gnu.tar.gz"
)

pm_supports_os() {
    [ -f /etc/os-release ] || return 1
    [ -e /run/ostree-booted ] && return 1
    local id like
    id=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
    like=$(awk -F= '/^ID_LIKE=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
    case "$id" in
        rhel|centos|rocky|almalinux|ol|scientific|amzn) return 1 ;;
    esac
    case " $id $like " in
        *" fedora "*) return 0 ;;
    esac
    return 1
}

pm_prepare_repos() {
    true
}

pm_bootstrap_install() {
    pm_dnf install -y "$@"
}

pm_bootstrap_helper() {
    true
}

pm_full_upgrade() {
    pm_dnf makecache --refresh >/dev/null 2>&1 || true
}

pm_resolve_name() {
    echo "${PM_PKG_MAP[$1]:-$1}"
}

pm_dnf_target() {
    local spec="$1" alternative available
    if [[ "$spec" == *'|'* ]]; then
        while IFS= read -r alternative; do
            available="$(pm_dnf_query --setopt=assumeno=True repoquery --available --quiet "$alternative")" || return 1
            if [ -n "$available" ]; then printf '%s\n' "$alternative"; return 0; fi
        done < <(tr '|' '\n' <<< "$spec")
        echo "No configured repository provides any of: $spec" >&2
        return 1
    fi
    printf '%s\n' "$spec"
}

pm_matugen_major() {
    local bin="$1" ver
    [ -x "$bin" ] || return 1
    ver="$("$bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)"
    [ -n "$ver" ] || return 1
    echo "${ver%%.*}"
}

pm_matugen_ok() {
    local bin major
    for bin in "$HOME/.local/bin/matugen" "$(command -v matugen 2>/dev/null)"; do
        [ -n "$bin" ] || continue
        major="$(pm_matugen_major "$bin")" || continue
        [ "$major" -ge "$PM_MATUGEN_MIN_MAJOR" ] && return 0
    done
    return 1
}

pm_matugen_release_url() {
    local url
    url="$(curl -fsSL --connect-timeout 15 --max-time 60 --retry 3 "https://api.github.com/repos/$PM_MATUGEN_REPO/releases/latest" 2>/dev/null \
        | jq -r '[.assets[] | select(.name | test("x86_64\\.tar\\.gz$"))][0].browser_download_url // empty' 2>/dev/null)"
    echo "${url:-${PM_RELEASE_MAP[matugen]}}"
}

pm_install_matugen() {
    pm_install_release_binary "$(pm_matugen_release_url)" matugen || return 1
    pm_matugen_ok || return 1
    if [ "${MANAGED_INSTALL:-false}" != true ] && rpm -q matugen &>/dev/null; then
        pm_dnf remove -y matugen || true
    fi
}

pm_missing_pkgs() {
    local pkg spec alt satisfied
    for pkg in "$@"; do
        if [ "$pkg" = "matugen" ]; then
            pm_matugen_ok || echo "$pkg"
            continue
        fi
        if [ -n "${PM_RELEASE_MAP[$pkg]:-}" ]; then
            if ! command -v "$pkg" &>/dev/null && [ ! -x "$HOME/.local/bin/$pkg" ]; then
                echo "$pkg"
            fi
            continue
        fi
        spec="$(pm_resolve_name "$pkg")"
        satisfied=false
        while IFS= read -r alt; do
            if rpm -q --whatprovides "$alt" &>/dev/null; then
                satisfied=true
                break
            fi
        done < <(tr '|' '\n' <<< "$spec")
        [ "$satisfied" = true ] || echo "$pkg"
    done
}

pm_is_installed() {
    rpm -q "$1" &>/dev/null
}

pm_enable_copr() {
    local repo="$1"
    echo -e "\e[36m[ INFO ]\e[0m $(t "installer.deps.enabling_copr" "repo=$repo")"
    if ! dnf copr --help &>/dev/null; then
        if command -v dnf5 &>/dev/null; then
            pm_dnf install -y dnf5-plugins || return 1
        else
            pm_dnf install -y dnf-plugins-core || return 1
        fi
    fi
    pm_dnf copr enable -y "$repo"
}

pm_enable_terra() {
    rpm -q terra-release &>/dev/null && return 0
    echo "This package needs a configured and trusted Terra repository. Configure Terra with its signing keys before retrying." >&2
    return 1
}

pm_install_release_binary() {
    local url="$1" binary="$2"
    local bin_dir="$HOME/.local/bin"
    local tmp found digest=""
    [ "$(uname -m)" = "x86_64" ] || return 1
    if [ "${MANAGED_INSTALL:-false}" = true ]; then
        local repo release asset
        if [[ ! "$url" =~ ^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/releases/(download/([A-Za-z0-9_.-]+)|latest/download)/([A-Za-z0-9_.-]+)$ ]]; then
            echo "Cannot match the upstream release asset for $binary." >&2
            return 1
        fi
        repo="${BASH_REMATCH[1]}" release="${BASH_REMATCH[3]}" asset="${BASH_REMATCH[4]}"
        local endpoint=latest
        if [ -n "$release" ]; then endpoint="tags/$release"; fi
        local metadata
        metadata="$(curl -fsSL --connect-timeout 15 --max-time 60 "https://api.github.com/repos/$repo/releases/$endpoint")" || return 1
        digest="$(jq -r --arg name "$asset" '.assets[] | select(.name == $name) | .digest // empty' <<< "$metadata")"
        if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
            echo "No SHA-256 digest is published for $repo/$asset. Install a verified package and retry." >&2
            return 1
        fi
    fi
    tmp="$(mktemp -d)"
    mkdir -p "$bin_dir"
    if curl -fsSL --connect-timeout 15 --max-time 180 --retry 3 "$url" -o "$tmp/pkg.tar.gz" &&
        { [ -z "$digest" ] || printf '%s  %s\n' "${digest#sha256:}" "$tmp/pkg.tar.gz" | sha256sum -c --quiet -; } &&
        tar -xzf "$tmp/pkg.tar.gz" -C "$tmp"; then
        found="$(find "$tmp" -type f -name "$binary" | head -n 1)"
        if [ -n "$found" ]; then
            install -m 0755 "$found" "$bin_dir/$binary"
            rm -rf "$tmp"
            return 0
        fi
    fi
    rm -rf "$tmp"
    return 1
}

pm_install_batch() {
    PM_BATCH_LEFT=("$@")
    local batch=() names=() rest=() pkg target
    for pkg in "$@"; do
        if [ -n "${PM_RELEASE_MAP[$pkg]:-}" ] || [ -n "${PM_TERRA_MAP[$pkg]:-}" ]; then
            rest+=("$pkg")
        elif [ "${MANAGED_INSTALL:-false}" != true ] && [ -n "${PM_COPR_MAP[$pkg]:-}" ]; then
            rest+=("$pkg")
        else
            target="$(pm_dnf_target "$(pm_resolve_name "$pkg")")" || return 1
            if [ -n "${PM_COPR_MAP[$pkg]:-}" ]; then
                local available minimum=0
                case "$pkg" in
                    hyprland) minimum="$MIN_HYPRLAND_LUA_VERSION" ;;
                    quickshell) minimum="$MIN_QUICKSHELL_VERSION" ;;
                esac
                available="$(pm_dnf_query --setopt=assumeno=True repoquery --available --latest-limit=1 \
                    --queryformat '%{version}\n' "$target")" || return 1
                available="$(sort -V <<< "$available" | tail -n 1)"
                if ! version_at_least "$available" "$minimum"; then
                    pm_enable_copr "${PM_COPR_MAP[$pkg]}" || return 1
                fi
            fi
            batch+=("$pkg")
            names+=("$target")
        fi
    done
    [ ${#batch[@]} -gt 0 ] || return 0
    if pm_dnf install -y "${names[@]}"; then
        for pkg in "${batch[@]}"; do
            echo -e "\n\e[32m[ OK ] $(t "installer.deps.install_ok" "pkg=$pkg")\e[0m"
        done
        PM_BATCH_LEFT=("${rest[@]}")
    elif [ "${MANAGED_INSTALL:-false}" = true ]; then
        return 1
    fi
}

pm_install_pkg() {
    local pkg="$1"
    local spec target

    if [ "$pkg" = "matugen" ]; then
        pm_install_matugen
        return
    fi
    if [ -n "${PM_RELEASE_MAP[$pkg]:-}" ]; then
        pm_install_release_binary "${PM_RELEASE_MAP[$pkg]}" "$pkg"
        return
    fi
    spec="$(pm_resolve_name "$pkg")"
    target="$(pm_dnf_target "$spec")" || return 1

    # Only PM_TERRA_MAP packages may use Terra; dynamic scope covers the
    # pm_dnf calls below.
    local PM_USE_TERRA=false
    [ -n "${PM_TERRA_MAP[$pkg]:-}" ] && PM_USE_TERRA=true

    local available
    if [ "${MANAGED_INSTALL:-false}" = true ]; then
        available="$(pm_dnf_query --setopt=assumeno=True repoquery --available --quiet "$target")" || return 1
    else
        available="$(pm_dnf_query repoquery --available --quiet "$target" 2>/dev/null | head -n 1)"
    fi
    if [ -z "$available" ]; then
        if [ -n "${PM_TERRA_MAP[$pkg]:-}" ]; then
            if ! pm_enable_terra; then
                echo -e "\e[31m[ ERROR ]\e[0m Terra repository could not be enabled; $pkg is unavailable (network error or repository down). Other compositors are unaffected." >&2
                return 1
            fi
        fi
        local copr="${PM_COPR_MAP[$pkg]:-}"
        if [ -n "$copr" ]; then
            pm_enable_copr "$copr" || return 1
        fi
    fi

    pm_dnf install -y "$target"
}

pm_enable_display_manager() {
    local svc="$1" init_sys="$2"
    if [ "$init_sys" = "systemd" ]; then
        sudo systemctl enable --force "$svc.service" 2>/dev/null || true
    else
        enable_system_service "$svc" "$init_sys"
    fi
}

pm_disable_display_manager() {
    local svc="$1" init_sys="$2"
    if [ "$init_sys" = "systemd" ]; then
        sudo systemctl disable "$svc.service" 2>/dev/null || true
    else
        disable_system_service "$svc" "$init_sys"
    fi
}

pm_remove_pkg() {
    true
}

pm_remove_conflicting_pkg() {
    true
}

# Fedora's own hyprland package may predate the Lua configuration format.
# Try the COPR build, which tracks upstream releases.
pm_upgrade_hyprland() {
    pm_dnf upgrade -y --refresh hyprland || return 1
    if ! version_at_least "$(hyprland_version)" "$MIN_HYPRLAND_LUA_VERSION"; then
        pm_enable_copr "${PM_COPR_MAP[hyprland]}" && pm_dnf upgrade -y --refresh hyprland
    fi
}

pm_upgrade_quickshell() {
    pm_dnf upgrade -y --refresh quickshell || return 1
    if ! quickshell_is_current; then
        pm_enable_copr "${PM_COPR_MAP[quickshell]}" && pm_dnf upgrade -y --refresh quickshell
    fi
}
