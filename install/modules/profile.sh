#!/usr/bin/env bash

inspect_install_hardware() {
    RAM_MIB=$(awk '/^MemTotal:/ {print int($2 / 1024); exit}' /proc/meminfo)
    CPU_THREADS=$(nproc)
    CPU_CORES=$(lscpu -p=CORE,SOCKET 2>/dev/null | awk '!/^#/ && NF && !seen[$0]++ {n++} END {print n+0}')
    GPU_DRIVERS=$(lspci -k 2>/dev/null | awk '/VGA compatible controller|3D controller|Display controller/ {gpu=1; next} /^[^[:space:]]/ {gpu=0} gpu && /Kernel driver in use:/ {sub(/.*: /,""); print}' | paste -sd ,)
    ACCELERATION=unknown
    local renderer
    if command -v glxinfo >/dev/null && [[ -n "${DISPLAY:-}" ]]; then
        renderer=$(timeout 5s glxinfo -B 2>/dev/null || true)
        case "$renderer" in
            *'Accelerated: yes'*) ACCELERATION=hardware ;;
            *'Accelerated: no'*|*llvmpipe*|*softpipe*) ACCELERATION=software ;;
        esac
    fi
    RECOMMENDED_PROFILE=full
    if (( CPU_THREADS < 4 || ${RAM_MIB:-0} < 6144 )) || [[ "$ACCELERATION" == software ]]; then
        RECOMMENDED_PROFILE=light
    fi
}

apply_install_profile() (
    local profile="$1" destination="$2" setting original updated temp
    case "$profile" in
        full) setting=false ;;
        light) setting=true ;;
        *) echo 'Choose profile full or light.' >&2; return 2 ;;
    esac
    if ! command -v jq >/dev/null; then
        echo "The profile command needs jq. Install it with your package manager." >&2
        return 1
    fi
    if ! destination="$(realpath -e -- "$destination" 2>/dev/null)"; then
        echo "Serpantinum settings are missing. Run the installer first." >&2
        return 1
    fi
    original=$(cat -- "$destination") || return 1
    updated=$(jq -e --argjson value "$setting" '.general.performance = $value' <<<"$original") || return 1
    if jq -e --argjson value "$setting" '.general.performance == $value' <<<"$original" >/dev/null; then
        return 0
    fi
    temp=$(mktemp -- "${destination}.profile.XXXXXX") || return 1
    trap 'rm -f -- "$temp"' EXIT
    cp -p -- "$destination" "$temp" || return 1
    printf '%s\n' "$updated" >"$temp" || return 1
    local backup
    backup=$(mktemp -- "${destination}.backup.XXXXXX") || return 1
    cp -p -- "$destination" "$backup" || return 1
    if [[ "$(cat -- "$backup")" != "$original" ]] || ! cmp -s -- "$backup" "$destination"; then
        printf "Settings changed during the profile update. Retry. Snapshot: %s\n" "$backup" >&2
        return 1
    fi
    mv -f -- "$temp" "$destination" || return 1
    printf 'Settings backup: %s\n' "$backup"
)
