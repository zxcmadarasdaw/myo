#!/usr/bin/env bash

manager_record() {
    local kind="$1" item
    shift
    printf '%s' "$kind"
    for item in "$@"; do
        item="${item//$'\n'/ }"
        printf '\t%s' "${item//$'\t'/ }"
    done
    printf '\n'
}

manager_options() {
    local comps="$1" options="$2" comp
    OPT_SDDM=false SDDM_WAYLAND=false REPLACE_DM=false
    OPT_SERVICES=false OPT_CONFIG=false OPT_REPLACE_CONFIG=false OPT_BACKUP=false OPT_GLOBAL_LAUNCHERS=false
    OPT_BUILD=false OPT_AUR=false OPT_SYNC=false OPT_VPN=false OPT_ENGINES=false OPT_EXTRAS=false
    OPT_FONTS=false OPT_WALLPAPERS=false INSTALL_FULL_WALLPAPERS=false ENABLE_TELEMETRY=false
    [[ ",$options," != *,sddm,* ]] || OPT_SDDM=true
    [[ ",$options," != *,wayland,* ]] || SDDM_WAYLAND=true
    [[ ",$options," != *,display-manager,* ]] || REPLACE_DM=true
    [[ ",$options," != *,services,* ]] || OPT_SERVICES=true
    [[ ",$options," != *,config,* ]] || OPT_CONFIG=true
    [[ ",$options," != *,replace,* ]] || OPT_REPLACE_CONFIG=true
    [[ ",$options," != *,backup,* ]] || OPT_BACKUP=true
    [[ ",$options," != *,global-launchers,* ]] || OPT_GLOBAL_LAUNCHERS=true
    [[ ",$options," != *,build,* ]] || OPT_BUILD=true
    [[ ",$options," != *,aur,* ]] || OPT_AUR=true
    [[ ",$options," != *,sync,* ]] || OPT_SYNC=true
    [[ ",$options," != *,vpn,* ]] || OPT_VPN=true
    [[ ",$options," != *,engines,* ]] || OPT_ENGINES=true
    [[ ",$options," != *,extras,* ]] || OPT_EXTRAS=true
    [[ ",$options," != *,fonts,* ]] || OPT_FONTS=true
    [[ ",$options," != *,wallpapers,* ]] || OPT_WALLPAPERS=true
    [[ ",$options," != *,full-wallpapers,* ]] || INSTALL_FULL_WALLPAPERS=true
    [[ ",$options," != *,telemetry,* ]] || ENABLE_TELEMETRY=true
    if [ "$comps" != auto ]; then
        IFS=, read -r -a SELECTED_COMPOSITORS <<< "$comps"
    fi
    for comp in "${SELECTED_COMPOSITORS[@]}"; do
        case "$comp" in hyprland|niri|sway|mango|umbriel) ;; *) return 1 ;; esac
    done
}

manager_disk() {
    local path="$1" required="$2" target="$1" available
    while [[ ! -e "$target" && "$target" != / ]]; do target="$(dirname -- "$target")"; done
    available="$(df -Pk -- "$target" | awk 'NR==2 {print $4}')"
    manager_record disk "$path" "$required" "${available:-unknown}"
    [[ "$available" =~ ^[0-9]+$ ]] && (( available >= required ))
}

manager_space() {
    local size path needed cache_size=unknown shortfall=0
    size="$(du -sk -- "$PROJECT_ROOT/bin" "$PROJECT_ROOT/src" "$PROJECT_ROOT/themess" |
        awk '{sum += $1} END {print sum+0}')"
    manager_disk "$HOME/.local/share" "$(( size + 16384 ))" || shortfall=1
    manager_disk "${XDG_CACHE_HOME:-$HOME/.cache}" 65536 || shortfall=1
    manager_record change "Root filesystem: $(findmnt -no FSTYPE / 2>/dev/null || echo unknown). Available RAM: $(awk '/^MemAvailable:/ {print $2 " KiB"}' /proc/meminfo)."
    case "$PM_NAME" in
        pacman) path="$(pacman-conf CacheDir | head -n 1)" ;;
        dnf) if command -v dnf5 >/dev/null; then path=/var/cache/libdnf5; else path=/var/cache/dnf; fi ;;
        *) path=/var/cache ;;
    esac
    if size="$(du -sk -- "$path" 2>/dev/null)"; then
        cache_size="${size%%[[:space:]]*}"
    fi
    manager_record change "Native cache: ${path:-unknown}. Current size in KiB: $cache_size."
    manager_disk "${path:-/var/cache}" 0 || shortfall=1
    for path in /usr /var "${TMPDIR:-/tmp}"; do
        needed=131072
        if [ "$MANAGER_LIVE" = true ] && [ "${#MANAGER_MISSING[@]}" -gt 0 ]; then
            # This is headroom for a desktop transaction. Both native managers
            # still show the resolved sizes and perform their own space checks.
            needed=262144
            if [ "$path" != "${TMPDIR:-/tmp}" ]; then needed=1048576; fi
        fi
        manager_disk "$path" "$needed" || shortfall=1
    done
    if (( shortfall )); then
        if [ "$MANAGER_LIVE" = true ]; then
            manager_record error "Insufficient Live storage for the desktop transaction. The temporary overlay must hold the installed files and may also hold the package cache. Use a system with sufficient persistent storage."
        else
            manager_record error "Insufficient free space. Free space on the listed filesystems and review the plan again."
        fi
        return 1
    fi
}

manager_pacman_preflight() {
    local message pkg files bytes cache installed_kib estimated_kib
    if [ "$OPT_SYNC" = true ] && [ "${MANAGER_LIVE:-false}" = true ]; then
        manager_record error 'Full upgrades are disabled in Live mode. Use an installed system or a current Live image with matching repository databases.'
        return 1
    fi
    [ "$OPT_SYNC" != true ] && [ ${#MANAGER_MISSING[@]} -gt 0 ] || return 0
    if ! message="$(pm_pacman_ready 2>&1)"; then
        message="${message%%$'\n'*}"
        manager_record error "${message:-Failed to read pacman repository databases.}"
        return 1
    fi
    local official=()
    for pkg in "${MANAGER_MISSING[@]}"; do
        if pacman -Si -- "$pkg" >/dev/null 2>&1; then
            official+=("$pkg")
        elif [ "$OPT_AUR" = true ] && pm_aur_recipe "$pkg" >/dev/null; then
            manager_record change "Binary package unavailable in configured repositories. AUR fallback planned for $pkg."
            if [ "$pkg" = umbriel ] && ! pm_is_installed xdg-desktop-portal-umbriel-git; then
                manager_record change 'Review the separate xdg-desktop-portal-umbriel-git recipe first.'
            fi
        else
            if pm_aur_recipe "$pkg" >/dev/null; then
                manager_record error "$pkg is unavailable in configured pacman repositories. Enable the reviewed AUR build and source builds."
            else
                manager_record error "$pkg is unavailable in configured pacman repositories. Check repository metadata and mirrors."
            fi
            return 1
        fi
    done
    [ ${#official[@]} -gt 0 ] || return 0
    if ! files="$(pacman -Sp --needed --print-format $'SP-SIZE:%s\t%r/%n' "${official[@]}" </dev/null 2>&1)"; then
        manager_record error "Pacman could not resolve all required dependencies. $files"
        return 1
    fi
    bytes="$(awk '/^SP-SIZE:[0-9]+([[:space:]]|$)/ { sub(/^SP-SIZE:/, ""); sum += $1 } END { printf "%.0f", sum }' <<< "$files")"
    local resolved=()
    mapfile -t resolved < <(awk -F '\t' '/^SP-SIZE:[0-9]+\t/ && $2 != "" { print $2 }' <<< "$files")
    if [ "${#resolved[@]}" -gt 0 ]; then
        if ! message="$(LC_ALL=C pacman -Si -- "${resolved[@]}" 2>&1)"; then
            manager_record error "Could not read installed sizes from pacman: $message"
            return 1
        fi
        installed_kib="$(awk '/^Installed Size[[:space:]]*:/ {
            units = $NF; size = $(NF-1)
            if (units == "MiB") size *= 1024
            if (units == "GiB") size *= 1048576
            if (units == "B") size /= 1024
            sum += size
        } END { printf "%.0f", sum + 1 }' <<< "$message")"
        manager_record change "Pacman resolved ${#resolved[@]} packages, with $(( (installed_kib + 1023) / 1024 )) MiB of installed files before accounting for replacements."
    fi
    if (( bytes > 0 )); then
        cache="$(pacman-conf CacheDir)" || return 1
        cache="${cache%%$'\n'*}"
        cache="${cache:-/var/cache/pacman/pkg}"
        manager_record change "Pacman estimates $(( (bytes + 1048575) / 1048576 )) MiB of package downloads from current databases."
        if ! manager_disk "$cache" "$(( (bytes + 1023) / 1024 ))"; then
            manager_record error "The pacman cache at $cache has insufficient free space for the estimated downloads."
            return 1
        fi
    fi
    if [ "$MANAGER_LIVE" = true ] && [ -n "${installed_kib:-}" ]; then
        estimated_kib="$installed_kib"
        # Typical Live images place /usr and the package cache on one overlay.
        # Allow a separately mounted cache to use its own free-space budget.
        cache="${cache:-$(pacman-conf CacheDir | head -n 1)}"
        cache="${cache:-/var/cache/pacman/pkg}"
        while [ ! -e "$cache" ] && [ "$cache" != / ]; do cache="$(dirname -- "$cache")"; done
        if [ "$(stat -c %d -- /usr)" = "$(stat -c %d -- "$cache")" ]; then
            estimated_kib=$(( estimated_kib + (bytes + 1023) / 1024 ))
        fi
        if ! manager_disk /usr "$estimated_kib"; then
            manager_record error 'The Live overlay has insufficient space for the resolved package transaction.'
            return 1
        fi
    fi
}

manager_command_status() {
    local label="$1" command="$2" path
    if path="$(command -v "$command")"; then
        manager_record component "$label" Installed "$path"
    else
        manager_record component "$label" Missing "$command is unavailable on PATH"
    fi
}

manager_components() {
    local target="$HOME/.local/share/serpantinum" version job label path missing
    local qml="$target/src/quickshell" ready=false
    if [ "$PACKAGED_INSTALL" = true ]; then
        manager_record component Serpantinum Installed 'System package. Update and repair it with pacman.'
    elif [ -f "$qml/Shell.qml" ] && [ -x "$target/bin/serpantinumd" ]; then
        if installed_program_matches "$target"; then
            manager_record component Serpantinum Installed "Program files match the checkout."
        elif version_at_least "$TARGET_VERSION" "$OLD_VERSION" &&
            { [ "$TARGET_VERSION" != "$OLD_VERSION" ] ||
              { [ -n "$OLD_COMMIT" ] && [ "$TARGET_COMMIT" != unknown ] && [ "$TARGET_COMMIT" != "$OLD_COMMIT" ]; }; }; then
            manager_record component Serpantinum 'Update available' "Installed $OLD_VERSION ($OLD_COMMIT) · checkout $TARGET_VERSION ($TARGET_COMMIT)"
        else
            manager_record component Serpantinum Failed 'Installed shell differs from the checkout. Run Verify for details.'
        fi
    elif [ -d "$target/src" ] || [ "$INSTALL_STATE" = current ]; then
        manager_record component Serpantinum Failed 'The shell entry point or launcher is missing.'
    else
        manager_record component Serpantinum Missing 'The checkout is available for deployment.'
    fi
    if version="$(hyprland_version)"; then
        if version_at_least "$version" "$MIN_HYPRLAND_LUA_VERSION"; then
            manager_record component Hyprland Installed "$version · supports Lua configuration"
        else
            manager_record component Hyprland 'Update required' "$version · needs $MIN_HYPRLAND_LUA_VERSION or newer"
        fi
    else
        manager_record component Hyprland Missing 'Hyprland executable unavailable.'
    fi
    if quickshell_is_current; then
        manager_record component Quickshell Installed "$(quickshell_version)"
        ready=true
    elif command -v quickshell >/dev/null; then
        manager_record component Quickshell 'Update required' "$(quickshell_version) · needs $MIN_QUICKSHELL_VERSION or newer"
    else
        manager_record component Quickshell Missing 'The installer can run without the shell.'
    fi
    missing="$(pm_missing_pkgs qt6-multimedia qt6-imageformats qt6-wayland)" || return 1
    if [ -z "$missing" ]; then
        manager_record component 'Qt Multimedia' Installed 'Multimedia, image and Wayland packages are present.'
    else
        ready=false
        manager_record component 'Qt Multimedia' Missing "$missing"
    fi
    for job in 'Wallpaper Engine|wallpaper/WallpaperEngine.qml' 'Wallpaper Hub|../scripts/wallpaper/wallhub.py' \
        'Music Studio|widgets/MusicWidgetDrawer.qml' 'Desktop Terminal|widgets/faces/terminal/TerminalCore.qml'; do
        label="${job%%|*}" path="${job#*|}"
        if [ "$ready" = true ] && [ -f "$qml/$path" ] &&
            { [[ "$label" != Wallpaper* ]] || command -v ffmpeg >/dev/null; } &&
            { [ "$label" != 'Music Studio' ] || {
                command -v playerctl >/dev/null && command -v wpctl >/dev/null && audio_installed_version >/dev/null;
            }; }; then
            manager_record component "$label" Ready 'Installed implementation and local runtime prerequisites found.'
        elif [ -f "$PROJECT_ROOT/src/quickshell/$path" ]; then
            manager_record component "$label" Missing 'Available in checkout. Deployment or runtime dependencies required.'
        else
            manager_record component "$label" Failed 'Implementation missing from checkout.'
        fi
    done
    manager_command_status 'Terminal / Kitty' kitty
    if version="$(audio_installed_version)"; then
        manager_record component 'Audio DSP' Installed "$version · verify routing in the PipeWire session"
    else
        manager_record component 'Audio DSP' Missing 'The executable is missing or cannot run.'
    fi
    manager_command_status 'Ski file manager' ski
    manager_command_status 'Core daemon' serpantinum-core
    manager_command_status 'Gamma daemon' serpantinum-gamma
    if [ -x "$VPN_HELPER_DST" ] && [ -f "$VPN_UNIT_DST" ] &&
        timeout 5s python3 "$PROJECT_ROOT/src/scripts/system/serp_vpn.py" system-engine-check >/dev/null 2>&1; then
        manager_record component 'VPN Engine' Installed 'System engine and service files found. Verify TUN separately.'
    elif [ -e "$VPN_HELPER_DST" ] || [ -e "$VPN_UNIT_DST" ]; then
        manager_record component 'VPN Engine' Failed 'System engine or service setup is incomplete.'
    else
        manager_record component 'VPN Engine' Optional 'Enable VPN setup to install the offline engine and TUN integration.'
    fi
    if path="$(command -v ollama)"; then
        manager_record component 'AI Backend' Installed "$path · start the server and select a model in Serpantinum"
    else
        manager_record component 'AI Backend' Optional 'Ollama is configured separately in the shell. No model downloads are planned.'
    fi
}

manager_dependency_plan() {
    local pkg tool result
    local targets=()
    collect_dependency_targets targets
    if [ "${OPT_EXTRAS:-false}" != true ]; then
        local required=()
        for pkg in "${targets[@]}"; do
            case "$pkg" in
                zbar|tesseract|tesseract-data-eng|cliphist|ddcutil|fastfetch|satty|gpu-screen-recorder|wf-recorder) ;;
                xwayland-satellite)
                    if [[ " ${SELECTED_COMPOSITORS[*]} " == *" niri "* ]]; then required+=("$pkg"); fi ;;
                *) required+=("$pkg") ;;
            esac
        done
        targets=("${required[@]}")
    fi
    local bootstrap=(jq curl git unzip fontconfig diffutils)
    for pkg in "${bootstrap[@]}"; do
        tool="$pkg"
        case "$pkg" in
            fontconfig) tool=fc-cache ;;
            diffutils) tool=cmp ;;
        esac
        if ! command -v "$tool" >/dev/null; then targets+=("$pkg"); fi
    done
    mapfile -t DEPENDENCY_TARGETS < <(printf '%s\n' "${targets[@]}" | awk '!seen[$0]++')
    result="$(pm_missing_pkgs "${DEPENDENCY_TARGETS[@]}")" || return 1
    MANAGER_MISSING=()
    if [ -n "$result" ]; then mapfile -t MANAGER_MISSING <<< "$result"; fi
    if [[ " ${MANAGER_MISSING[*]} " != *" quickshell "* ]] &&
        command -v quickshell >/dev/null && ! quickshell_is_current; then
        MANAGER_MISSING+=(quickshell)
    fi
    if [[ " ${SELECTED_COMPOSITORS[*]} " == *" hyprland "* && " ${MANAGER_MISSING[*]} " != *" hyprland "* ]] &&
        hyprland_binary >/dev/null && ! version_at_least "$(hyprland_version)" "$MIN_HYPRLAND_LUA_VERSION"; then
        MANAGER_MISSING+=(hyprland)
    fi
}

manager_probe() {
    local pkg state missing=" ${MANAGER_MISSING[*]} "
    manager_record meta "$OS_NAME" "$DISTRO_ID" "$PM_NAME" "$TARGET_VERSION" "$TARGET_COMMIT" "$INSTALL_STATE"
    manager_record selected "${SELECTED_COMPOSITORS[*]}"
    manager_record display "$(active_display_manager)"
    if [ "$MANAGER_LIVE" = true ]; then
        manager_record session live
        manager_record warning 'Live/overlay session detected. Verify persistence and space before system changes.'
    fi
    if [ "$PACKAGED_INSTALL" = true ]; then
        manager_record error 'A native Serpantinum package is installed. Use pacman to manage this copy.'
    fi
    for pkg in "${DEPENDENCY_TARGETS[@]}"; do
        state=Installed
        if [[ "$missing" == *" $pkg "* ]]; then state=Missing; fi
        manager_record package "$pkg" "$state"
    done
    if [ "$MANAGER_ACTION" = inspect ]; then
        manager_components
        manager_space || true
    fi
    if [ "$MANAGER_ACTION" = verify ] || [ "$MANAGER_ACTION" = inspect ]; then return 0; fi
    if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then manager_record error 'Select a compositor.'; fi
    if [ "$OPT_AUR" = true ] && [ "$OPT_BUILD" != true ]; then
        manager_record error 'AUR requires explicit permission to build packages.'
    fi
    if [ "$OPT_REPLACE_CONFIG" = true ] && [ "$OPT_CONFIG" != true ]; then
        manager_record error 'Configuration replacement requires configuration deployment.'
    fi
    manager_space || true
    if [ "$PM_NAME" = pacman ]; then
        if [ "$OPT_SYNC" = true ]; then
            manager_record change 'Refresh pacman databases and perform a full system upgrade after reviewing its transaction.'
            if [ "$MANAGER_LIVE" = true ]; then
                manager_record warning 'This full upgrade can consume significant temporary space in Live. Review the package manager’s actual download and installation sizes before approving its transaction.'
            fi
        else
            manager_record change 'Install using existing pacman databases. Refresh requires a separately selected full system upgrade.'
        fi
        if [ "$OPT_AUR" = true ]; then
            manager_record change 'Allow known AUR recipes for Quickshell or Umbriel when the binary package is unavailable. Review the recipe before building.'
        fi
        manager_pacman_preflight || true
    else
        manager_record change 'Install with DNF. Missing or outdated packages may require COPR. Review the repository and signing key prompts.'
        for pkg in "${MANAGER_MISSING[@]}"; do
            if [ -n "${PM_COPR_MAP[$pkg]:-}" ]; then
                manager_record change "COPR fallback for $pkg: ${PM_COPR_MAP[$pkg]}."
            fi
        done
    fi
    manager_record change "Package targets missing or outdated: ${MANAGER_MISSING[*]:-none}. Native transaction reviews include dependencies, conflicts, changes and sizes."
    manager_record change 'Deploy the shell and themes under ~/.local/share/serpantinum, create user launch links and initial settings, and record the installed version.'
    if [ "$OPT_GLOBAL_LAUNCHERS" = true ]; then
        manager_record change 'Add missing compatibility links in /usr/local/bin using sudo.'
    elif [[ " ${SELECTED_COMPOSITORS[*]} " =~ [[:space:]](niri|sway|mango|umbriel)[[:space:]] ]]; then
        manager_record warning 'For this desktop session, ensure ~/.local/bin is on its PATH or select compatibility launch links.'
    fi
    if [ "$OPT_CONFIG" = true ]; then
        manager_record change "Deploy configuration for ${SELECTED_COMPOSITORS[*]} and Kitty as applicable."
        if [ "$OPT_REPLACE_CONFIG" = true ]; then
            manager_record change 'Back up and replace matching compositor/Kitty files during installation or repair.'
        elif [ "$MANAGER_ACTION" = update ]; then
            manager_record change 'Update matching unmodified Hyprland files with backups. Keep locally edited files.'
        fi
    fi
    if [ "$OPT_BACKUP" = true ]; then manager_record change 'Make a private pre-installation settings snapshot.'; fi
    if [ "$OPT_SDDM" = true ]; then
        manager_record change "Install SDDM packages and theme. Switch the existing display manager: $REPLACE_DM."
        local display_manager
        display_manager="$(active_display_manager)"
        if [[ -n "$display_manager" && "$display_manager" != sddm && "$REPLACE_DM" != true ]]; then
            manager_record warning "The active display manager is $display_manager. SDDM configuration will be skipped unless switching is selected."
        fi
    fi
    if [ "$OPT_SERVICES" = true ]; then manager_record change 'Set up PAM, NetworkManager, power profiles and PipeWire services.'; fi
    if [ "$OPT_VPN" = true ]; then manager_record change 'Install compatible VPN components and applicable systemd/polkit integration. No VPN connection is started.'; fi
    if [ "$OPT_ENGINES" = true ]; then manager_record change 'Install Ski and the audio, gamma and core daemons from Serpantinum upstream releases. Update mode checks for newer releases.'; fi
    if [[ " ${SELECTED_COMPOSITORS[*]} " == *" umbriel "* ]]; then
        manager_record change "Umbriel requires Serpantinum Core $CORE_VERSION for workspace IPC."
    fi
    if [ "$OPT_BUILD" = true ]; then manager_record change 'Allow the audio daemon source build and its compiler dependencies if required.'; fi
    if [ "$OPT_FONTS" = true ]; then manager_record change 'Download missing Iosevka Nerd Fonts.'; fi
    if [ "$OPT_WALLPAPERS" = true ]; then manager_record change "Download wallpapers. Full pack: $INSTALL_FULL_WALLPAPERS."; fi
    if [ "$ENABLE_TELEMETRY" = true ]; then manager_record change 'Send anonymous installation telemetry.'; fi
}

manager_pacman_packages() {
    local pkg official=() aur=() db
    if [ "$OPT_SYNC" != true ] && [ ${#MANAGER_MISSING[@]} -eq 0 ]; then return 0; fi
    db="$(pacman-conf DBPath)" || return 1
    if [ -e "${db%/}/db.lck" ]; then
        echo "Pacman is locked at ${db%/}/db.lck. Wait and retry."
        return 1
    fi
    if [ "$OPT_SYNC" = true ]; then
        local sync_targets=()
        for pkg in "${MANAGER_MISSING[@]}"; do
            if [ "$OPT_AUR" = true ] && pm_aur_recipe "$pkg" >/dev/null &&
                ! pacman -Si -- "$pkg" >/dev/null 2>&1; then continue; fi
            sync_targets+=("$pkg")
        done
        printf '@@activity\tDownloading\tPacman databases and system packages\n'
        pm_queue_run pacman --upgrade -- "${sync_targets[@]}" </dev/tty || return 1
        pm_pacman_ready || return 1
        manager_dependency_plan || return 1
        [ ${#MANAGER_MISSING[@]} -gt 0 ] || return 0
    fi
    pm_pacman_ready || return 1
    for pkg in "${MANAGER_MISSING[@]}"; do
        if pacman -Si -- "$pkg" >/dev/null 2>&1; then
            official+=("$pkg")
        elif [ "$OPT_AUR" = true ] && pm_aur_recipe "$pkg" >/dev/null; then
            aur+=("$pkg")
        else
            echo "$pkg is missing from configured pacman repositories. Check mirror metadata or provide a trusted package source."
            return 1
        fi
    done
    if [ ${#official[@]} -gt 0 ]; then
        printf '@@activity\tInstalling\t%s\n' "${official[*]}"
        pm_pacman_install "${official[@]}" </dev/tty || return 1
    fi
    for pkg in "${aur[@]}"; do pm_aur_install "$pkg" || return 1; done
}

manager_dnf_packages() {
    local pkg
    [ ${#MANAGER_MISSING[@]} -gt 0 ] || return 0
    printf '@@activity\tInstalling\t%s\n' "${MANAGER_MISSING[*]}"
    pm_install_batch "${MANAGER_MISSING[@]}" </dev/tty || return 1
    for pkg in "${PM_BATCH_LEFT[@]}"; do
        printf '@@activity\tInstalling\t%s\n' "$pkg"
        pm_install_pkg "$pkg" 1 </dev/tty || return 1
    done
    hash -r
    if [[ " ${MANAGER_MISSING[*]} " == *" hyprland "* ]] &&
        ! version_at_least "$(hyprland_version)" "$MIN_HYPRLAND_LUA_VERSION"; then
        pm_upgrade_hyprland </dev/tty || return 1
    fi
    if [[ " ${MANAGER_MISSING[*]} " == *" quickshell "* ]] && ! quickshell_is_current; then
        pm_upgrade_quickshell </dev/tty || return 1
    fi
}

manager_dependencies() {
    if [ "$PM_NAME" = pacman ]; then manager_pacman_packages || return 1; else manager_dnf_packages || return 1; fi
    hash -r
    manager_dependency_plan || return 1
    if [ ${#MANAGER_MISSING[@]} -gt 0 ]; then
        printf 'Required packages are still missing or outdated: %s\n' "${MANAGER_MISSING[*]}" >&2
        return 1
    fi
    quickshell_is_current || { echo "Quickshell $MIN_QUICKSHELL_VERSION or newer is required."; return 1; }
    if [[ " ${SELECTED_COMPOSITORS[*]} " == *" hyprland "* ]]; then
        version_at_least "$(hyprland_version)" "$MIN_HYPRLAND_LUA_VERSION" ||
            { echo "Hyprland $MIN_HYPRLAND_LUA_VERSION or newer is required."; return 1; }
        if [ "$OPT_CONFIG" = true ]; then check_hyprland_config "$PROJECT_ROOT/compositors/hyprland/hyprland.lua"; fi
    fi
}

manager_engines() {
    local job command fn before
    if [ "$OPT_ENGINES" != true ]; then
        if [[ " ${SELECTED_COMPOSITORS[*]} " == *" umbriel "* ]] &&
            ! version_at_least "$(core_installed_version)" "$CORE_VERSION"; then
            install_core_daemon
            version_at_least "$(core_installed_version)" "$CORE_VERSION" || {
                echo "Umbriel integration needs Serpantinum Core $CORE_VERSION or later." >&2
                return 1
            }
        fi
        return 0
    fi
    for job in 'ski:install_ski' 'serpantinum-audio:install_audio_daemon' \
        'serpantinum-gamma:install_gamma_daemon' 'serpantinum-core:install_core_daemon'; do
        command="${job%%:*}" fn="${job#*:}"
        before=${#FAILED_PKGS[@]}
        if [ "$MANAGER_ACTION" = update ] || ! manager_engine_ready "$command"; then
            printf '@@activity\tDownloading\t%s\n' "$command"
            if ! "$fn"; then FAILED_PKGS+=("$command"); fi
            hash -r
        fi
        if manager_engine_ready "$command" && [ "${#FAILED_PKGS[@]}" -eq "$before" ]; then
            manager_record '@@component' "$command" Installed 'Executable verified.'
        else
            if [ "${#FAILED_PKGS[@]}" -eq "$before" ]; then FAILED_PKGS+=("$command"); fi
            manager_record '@@component' "$command" Failed 'See the release, package manager or build output above.'
        fi
    done
    if [ ${#FAILED_PKGS[@]} -gt 0 ]; then
        printf 'Component setup failed: %s\n' "${FAILED_PKGS[*]}"
        return 1
    fi
}

manager_engine_ready() {
    if [ "$1" = serpantinum-audio ]; then
        audio_installed_version >/dev/null
    else
        command -v "$1" >/dev/null
    fi
}

manager_deploy() {
    local wallpapers
    if [ "$MANAGER_ACTION" != missing ] ||
        [ ! -x "$HOME/.local/bin/serpantinumd" ] ||
        [ ! -f "$HOME/.local/share/serpantinum/src/quickshell/Shell.qml" ]; then
        deploy_package "$PROJECT_ROOT" "$OLD_COMMIT" "$TARGET_COMMIT" "$IS_REINSTALL" "$INSTALL_STATE" "${SELECTED_COMPOSITORS[@]}"
    elif [ "$OPT_CONFIG" = true ]; then
        echo 'Existing program kept. Use Repair to deploy compositor configuration.'
    fi
    wallpapers="$(get_wallpaper_dir)"
    mkdir -p -- "$wallpapers"
    if [ "$OPT_WALLPAPERS" = true ]; then
        printf '@@activity\tDownloading\tWallpaper collection\n'
        if ! install_wallpapers "$INSTALL_FULL_WALLPAPERS"; then
            manager_record '@@component' 'Wallpaper collection' Failed 'Check the upstream checkout and wallpaper directory.'
            return 1
        fi
        manager_record '@@component' 'Wallpaper collection' Installed "$wallpapers"
    else
        install_bundled_wallpapers "$wallpapers"
    fi
    init_serpantinum_config "$PROJECT_ROOT" "$wallpapers"
    if [ "$OPT_CONFIG" = true ]; then
        configure_qt_icon_theme
        configure_ski_defaults "$SERP_NEW_SETTINGS"
    fi
    if [ "$OPT_FONTS" = true ]; then
        if ! install_fonts; then
            manager_record '@@component' 'Iosevka Nerd Font' Failed 'Download, extraction or font cache update failed.'
            return 1
        fi
        manager_record '@@component' 'Iosevka Nerd Font' Installed
    fi
    if [ "$OPT_GLOBAL_LAUNCHERS" = true ]; then
        local launcher
        for launcher in serpantinum serpantinumd; do
            install_launcher_link "$HOME/.local/share/serpantinum/bin/$launcher" "$HOME/.local/bin/$launcher" || return 1
        done
    fi
}

manager_services() {
    setup_sddm "$PROJECT_ROOT"
    if [ "$OPT_SERVICES" = true ]; then setup_services; fi
    if [ "$OPT_ENGINES" = true ]; then hand_over_from_easyeffects || return 1; fi
    if [ "$OPT_VPN" = true ]; then
        if [ "$MANAGER_ACTION" = missing ] && [ -f "$VPN_UNIT_DST" ] && [ -x "$VPN_HELPER_DST" ] &&
            timeout 5s python3 "$PROJECT_ROOT/src/scripts/system/serp_vpn.py" system-engine-check >/dev/null 2>&1; then
            echo 'Existing VPN engine and service kept.'
        else
            if ! install_vpn_components; then
                manager_record '@@component' 'VPN' Failed 'See the VPN component log and the detected platform.'
                return 1
            fi
        fi
        if [[ "$DISTRO_ID" = fedora || "$PM_NAME" = pacman ]]; then
            manager_record '@@component' 'VPN' Installed 'System engine and service present.'
        else
            manager_record '@@component' 'VPN' 'Platform limited' 'Only compatible local bundles and applicable service files are included.'
        fi
    fi
}

manager_verify() {
    if verify_installation; then
        manager_record '@@integration' SUCCESS 'Installed configuration and selected sessions passed verification.'
    else
        manager_record '@@integration' FAILED 'Installed environment failed verification. See the specific checks in the journal.'
        return 1
    fi
}

manager_backup() (
    if [ "$OPT_BACKUP" = true ]; then
        source "$INSTALL_DIR/maintenance.sh"
        local snapshot
        snapshot="$(make_snapshot)" || return 1
        echo "Private settings snapshot: $snapshot"
    fi
)

manager_step() {
    local number="$1" status="$2" label="$3"
    shift 3
    if (( number < MANAGER_RESUME )); then return 0; fi
    manager_record '@@phase' "$number" 6 "$status" "$label"
    "$@"
    manager_record '@@done' "$number"
}

manager_run_exit() {
    local version
    if [[ " ${SELECTED_COMPOSITORS[*]} " == *" hyprland "* ]]; then
        if version="$(hyprland_version)" && [ -n "$version" ]; then
            manager_record '@@component' Hyprland Installed "$version"
        elif hyprland_binary >/dev/null; then
            manager_record '@@component' Hyprland Failed 'Hyprland executable could not report its version.'
        else
            manager_record '@@component' Hyprland Missing 'Hyprland executable is unavailable after this run.'
        fi
    fi
    if quickshell_is_current; then
        manager_record '@@component' Quickshell Installed "$(quickshell_version)"
    elif command -v quickshell >/dev/null; then
        manager_record '@@component' Quickshell 'Update required' "Requires Quickshell $MIN_QUICKSHELL_VERSION or newer."
    else
        manager_record '@@component' Quickshell Missing 'Quickshell executable is unavailable after this run.'
    fi
    rm -rf -- "$MANAGER_TMP"
}

manager_run() {
    local lock="${STATE_DIR%/*}/.serpantinum-install.lock"
    if [ "$PACKAGED_INSTALL" = true ]; then
        echo 'Use pacman to manage the native Serpantinum package.'
        return 1
    fi
    if [ "$MANAGER_ACTION" = verify ]; then
        if [ -f "$lock" ]; then
            exec 9<"$lock"
            flock -sn 9 || { echo 'An installation is in progress. Verify after it finishes.'; return 1; }
        fi
        manager_record '@@phase' 1 1 Verifying 'Installed environment'
        manager_verify || return 1
        manager_record '@@done' 1
        return
    fi
    [ ${#SELECTED_COMPOSITORS[@]} -gt 0 ] || return 1
    if ! manager_space; then return 1; fi
    if [ "$PM_NAME" = pacman ] && (( MANAGER_RESUME <= 2 )); then
        manager_pacman_preflight || return 1
    fi

    umask 077
    mkdir -p -- "$STATE_DIR"
    exec 9>"$lock"
    flock -n 9 || { echo 'Another installer or maintenance operation is running.'; return 1; }
    MANAGER_TMP="$(mktemp -d)"
    trap manager_run_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    export SUDO_PROMPT=$'\n[Serpantinum sudo] Password for %u: '
    export GIT_TERMINAL_PROMPT=0 GIT_PAGER=cat DNF5_FORCE_INTERACTIVE=1
    export SERPANTINUM_MANAGED_VPN=true
    manager_step 1 Configuring 'Settings snapshot' manager_backup
    manager_step 2 Installing 'Distribution packages' manager_dependencies
    manager_step 3 Installing 'Desktop engines' manager_engines
    manager_step 4 Configuring 'Shell and configuration' manager_deploy
    manager_step 5 Configuring 'Services and VPN' manager_services
    manager_step 6 Verifying 'Installed environment' manager_verify

    if [ "$MANAGER_ACTION" != missing ] || [ "$INSTALL_STATE" != current ]; then
        local telemetry_id saved_sddm="$OPT_SDDM" saved_wayland="$SDDM_WAYLAND" saved_wallpapers="$INSTALL_FULL_WALLPAPERS"
        if [ "$OPT_SDDM" != true ]; then
            saved_sddm="$(get_saved_preference OPT_SDDM false)"
            saved_wayland="$(get_saved_preference SDDM_WAYLAND false)"
        fi
        if [ "$OPT_WALLPAPERS" != true ]; then
            saved_wallpapers="$(get_saved_preference INSTALL_FULL_WALLPAPERS false)"
        fi
        if [ "$INSTALL_STATE" = legacy ] && [ "$OPT_CONFIG" = true ]; then
            migrate_legacy
        fi
        if [[ "$INSTALL_STATE" != current || "$MANAGER_ACTION" = repair ]]; then
            rm -f -- "$STATE_DIR/first_launch.done" "$HOME/.local/state/quickshell/first_launch.done"
        fi
        telemetry_id=""
        if [ "$ENABLE_TELEMETRY" = true ]; then telemetry_id="$(get_telemetry_id)"; fi
        write_version_state "$TARGET_VERSION" "$TARGET_COMMIT" "$telemetry_id" "$ENABLE_TELEMETRY" \
            "${SELECTED_COMPOSITORS[*]}" "$saved_sddm" "$saved_wayland" "$saved_wallpapers"
        if [ "$ENABLE_TELEMETRY" = true ]; then
            bash "$MODULES_DIR/telemetry.sh" --mode done --version "$TARGET_VERSION" --old-version "$OLD_VERSION" \
                --install-state "$INSTALL_STATE" --compositor "${SELECTED_COMPOSITORS[*]}" --id "$telemetry_id" --enabled true
        fi
    fi
}

installer_manager() {
    MANAGED_INSTALL=true
    MANAGER_ACTION="$2"
    MANAGER_RESUME="${5:-1}"
    export SERP_DOWNLOAD_MODE="${6:-${SERP_DOWNLOAD_MODE:-balanced}}"
    case "$SERP_DOWNLOAD_MODE" in stable|balanced|fast|adaptive) ;; *) return 2 ;; esac
    case "$MANAGER_ACTION" in inspect|install|verify|repair|update|missing) ;; *) return 2 ;; esac
    [[ "$MANAGER_RESUME" =~ ^[1-6]$ ]] || return 2
    source "$PROJECT_ROOT/src/scripts/xdg_paths.sh"
    export QS_STATE_DIR="$(serpantinum_state_dir)" QS_SETTINGS="$(serpantinum_settings_path)"
    source "$MODULES_DIR/version.sh"
    source "$MODULES_DIR/config.sh"
    INSTALL_STATE="$(detect_install_state)"
    TARGET_VERSION="$(get_target_version "$PROJECT_ROOT")"
    TARGET_COMMIT="$(get_target_commit "$PROJECT_ROOT")"
    OLD_VERSION="$(get_installed_version)"
    OLD_COMMIT="$(get_installed_commit)"
    init_compositor_detection
    manager_options "${3:-auto}" "${4:-}"
    MANAGER_LIVE=false PACKAGED_INSTALL=false
    if install_live_session; then MANAGER_LIVE=true; fi
    if [ "$PM_NAME" = pacman ]; then
        source "$MODULES_DIR/pm/aur.sh"
        if pm_is_installed serpantinum || pm_is_installed serpantinum-git; then PACKAGED_INSTALL=true; fi
    fi
    manager_dependency_plan
    IS_REINSTALL=false
    if [ "$MANAGER_ACTION" = repair ]; then IS_REINSTALL=true; fi
    if [ "$1" = --manager-probe ]; then manager_probe; else manager_run; fi
}
