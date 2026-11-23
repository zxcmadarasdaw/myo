#!/usr/bin/env bash

EXTRA_CONFIGS=(
    "kitty"
)

render_wallpaper_progress() {
    local current="$1"
    local total="$2"
    local label="${3:-Installing wallpapers}"
    local bar_width=30
    local percent=0
    if [ "$total" -gt 0 ]; then
        percent=$(( current * 100 / total ))
    fi
    local filled=0
    if [ "$total" -gt 0 ]; then
        filled=$(( current * bar_width / total ))
    fi
    local empty=$(( bar_width - filled ))
    local bar_fill=""
    local bar_empty=""
    if [ "$filled" -gt 0 ]; then
        bar_fill=$(printf "%*s" "$filled" "" | tr ' ' '=')
    fi
    if [ "$empty" -gt 0 ]; then
        bar_empty=$(printf "%*s" "$empty" "" | tr ' ' ' ')
    fi
    printf "\r\e[36m[ INFO ]\e[0m %s \e[32m[%s%s]\e[0m %3d%% (%d/%d)" "$label" "$bar_fill" "$bar_empty" "$percent" "$current" "$total"
}

get_wallpaper_dir() {
    local user_pics=""
    if [ -f "$HOME/.config/user-dirs.dirs" ]; then
        user_pics=$(grep '^XDG_PICTURES_DIR' "$HOME/.config/user-dirs.dirs" 2>/dev/null | cut -d= -f2 | tr -d '"' | sed "s|\$HOME|$HOME|g")
    fi
    if [[ -z "$user_pics" || "$user_pics" == "$HOME" ]]; then
        if command -v xdg-user-dir &>/dev/null; then
            user_pics="$(xdg-user-dir PICTURES 2>/dev/null || true)"
        fi
    fi
    if [[ -z "$user_pics" || "$user_pics" == "$HOME" ]]; then
        user_pics="$HOME/Pictures"
    fi
    user_pics="${user_pics%/}"
    echo "$user_pics/Wallpapers"
}

# Copies the wallpapers shipped inside bundled Themess packages into an empty
# wallpaper folder so the first start never ends on a bare background.
install_bundled_wallpapers() {
    local wallpaper_dir="$1" f copied=0
    [ -n "$(find -L "$wallpaper_dir" -maxdepth 1 -type f 2>/dev/null | head -n 1)" ] && return 0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        cp -n "$f" "$wallpaper_dir/" 2>/dev/null && copied=$((copied + 1))
    done < <(find -L "$HOME/.local/share/serpantinum/themess" -maxdepth 3 -type f -path "*/wallpapers/*" \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.gif" -o -iname "*.webm" \) 2>/dev/null)
    [ "$copied" -gt 0 ] && echo -e "\e[36m[ INFO ]\e[0m Installed $copied bundled wallpaper(s) into $wallpaper_dir"
    return 0
}

install_wallpapers() {
    local full_pack="${1:-true}"
    local wallpaper_dir
    wallpaper_dir=$(get_wallpaper_dir)
    local wallpaper_repo="https://github.com/ilyamiro/shell-wallpapers.git"
    local clone_dir="${XDG_CACHE_HOME:-"$HOME/.cache"}/serpantinum-wallpapers"

    mkdir -p "$wallpaper_dir"

    local sync_success=false
    if [ -d "$clone_dir/.git" ]; then
        if git -C "$clone_dir" fetch --depth 1 origin 2>/dev/null; then
            if git -C "$clone_dir" reset --hard FETCH_HEAD 2>/dev/null || \
               git -C "$clone_dir" reset --hard origin/HEAD 2>/dev/null || \
               git -C "$clone_dir" reset --hard origin/main 2>/dev/null || \
               git -C "$clone_dir" reset --hard origin/master 2>/dev/null; then
                sync_success=true
            fi
        fi
    fi

    if [ "$sync_success" != true ]; then
        rm -rf "$clone_dir"
        echo -e "\n\e[36m[ INFO ]\e[0m Cloning wallpapers repository..."
        git clone --depth 1 "$wallpaper_repo" "$clone_dir" 2>/dev/null || true
    fi

    local src_dir="$clone_dir"
    if [ -d "$clone_dir/images" ]; then
        src_dir="$clone_dir/images"
    fi

    if [ ! -d "$src_dir" ]; then
        echo -e "\n\e[33m[ WARN ]\e[0m Wallpaper pack could not be downloaded (network?)."
        install_bundled_wallpapers "$wallpaper_dir"
        return 0
    fi

    if [ "$full_pack" = true ]; then
        local files=()
        while IFS= read -r f; do
            [[ -n "$f" ]] && files+=("$f")
        done < <(find "$src_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) 2>/dev/null)

        local total=${#files[@]}
        local count=0

        if [ "$total" -gt 0 ]; then
            for file in "${files[@]}"; do
                cp -n "$file" "$wallpaper_dir/" 2>/dev/null || true
                count=$((count + 1))
                render_wallpaper_progress "$count" "$total" "Installing wallpapers"
            done
            echo ""
        else
            find "$src_dir" -type f ! -name "README.md" ! -name "LICENSE" ! -path "*/.git/*" -exec cp -n {} "$wallpaper_dir/" \; 2>/dev/null || true
        fi
    else
        if [ -z "$(ls -A "$wallpaper_dir" 2>/dev/null | grep -iE '\.(jpg|jpeg|png|gif|webp)$')" ]; then
            local random_pics=()
            while IFS= read -r pic; do
                [[ -n "$pic" ]] && random_pics+=("$pic")
            done < <(find "$src_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \) 2>/dev/null | shuf -n 3)

            local total=${#random_pics[@]}
            local count=0

            if [ "$total" -gt 0 ]; then
                for pic in "${random_pics[@]}"; do
                    cp -n "$pic" "$wallpaper_dir/" 2>/dev/null || true
                    count=$((count + 1))
                    render_wallpaper_progress "$count" "$total" "Installing wallpapers"
                done
                echo ""
            fi
        fi
    fi

    install_bundled_wallpapers "$wallpaper_dir"
}

resolve_sddm_backend() {
    local requested_wayland="${1:-false}"
    local wayland_cmd="" bin

    if bin="$(find_sddm_binary weston)"; then
        wayland_cmd="$bin --shell=kiosk"
    elif bin="$(find_sddm_binary kwin_wayland)"; then
        wayland_cmd="$bin --no-global-shortcuts --no-lockscreen --locale1"
    fi

    local has_xorg=false
    if sddm_has_xorg; then
        has_xorg=true
    fi

    if [ "$requested_wayland" = true ]; then
        if [ -n "$wayland_cmd" ]; then
            printf 'wayland\n%s\n' "$wayland_cmd"
            return 0
        elif [ "$has_xorg" = true ]; then
            echo -e "  \e[33m[ WARN ]\e[0m $(t "installer.deploy.sddm_no_wayland_compositor")" >&2
            echo "x11"
            return 0
        fi
    else
        if [ "$has_xorg" = true ]; then
            echo "x11"
            return 0
        elif [ -n "$wayland_cmd" ]; then
            echo -e "  \e[33m[ WARN ]\e[0m $(t "installer.deploy.sddm_no_xorg" "compositor=${wayland_cmd%% *}")" >&2
            printf 'wayland\n%s\n' "$wayland_cmd"
            return 0
        fi
    fi

    echo -e "  \e[31m[ ERROR ]\e[0m $(t "installer.deploy.sddm_no_backend")" >&2
    return 1
}

configure_sddm_cursor() {
    local conf="$1" theme=""
    if [ -d /usr/share/icons/Adwaita/cursors ]; then
        theme="Adwaita"
    else
        theme="$(find /usr/share/icons -mindepth 2 -maxdepth 2 -type d -name cursors 2>/dev/null | head -n 1 | xargs -r dirname | xargs -r basename)"
    fi
    [ -n "$theme" ] || return 0
    sudo sed -i -e "/^ThemeDir=/a CursorTheme=$theme" -e "/^ThemeDir=/a CursorSize=24" "$conf"
}

active_display_manager() {
    local current
    current="$(systemctl show --property=Id --value display-manager.service 2>/dev/null)" || return 0
    if [[ "$current" =~ ^[a-zA-Z0-9_.@-]+\.service$ && "$current" != display-manager.service ]]; then
        printf '%s\n' "${current%.service}"
    fi
}

backup_system_path() {
    local path="$1" backup
    [ -e "$path" ] || return 0
    backup="$(sudo mktemp -d -- "${path}.backup.XXXXXX")" || return 1
    if ! sudo cp -a -- "$path" "$backup/"; then
        echo "Could not back up $path. Its contents will be kept." >&2
        return 1
    fi
    printf 'Backup of %s: %s\n' "$path" "$backup"
}

setup_sddm() {
    local project_root="$1"

    if [ "$OPT_SDDM" != true ]; then
        return 0
    fi

    local sddm_display_server=""
    local sddm_compositor_cmd=""
    local backend_output=""
    if ! backend_output=$(resolve_sddm_backend "$SDDM_WAYLAND"); then
        echo -e "  \e[33m[ WARN ]\e[0m $(t "installer.deploy.sddm_skipped")" >&2
        return 0
    fi

    {
        read -r sddm_display_server
        read -r sddm_compositor_cmd || true
    } <<< "$backend_output"

    local init_sys
    init_sys="$(detect_init_system)"
    local current_dm=""
    if [ "$init_sys" = systemd ]; then
        current_dm="$(active_display_manager)"
        if [[ -n "$current_dm" && "$current_dm" != sddm && "$REPLACE_DM" != true ]]; then
            printf 'Leaving the current display manager (%s) in place. SDDM setup skipped.\n' "$current_dm"
            return 0
        fi
    fi

    local sddm_theme_src="$project_root/config/sddm/themes/material-you"
    local sddm_theme_dest="/usr/share/sddm/themes/material-you"
    local sddm_config="/etc/sddm.conf.d/10-material-you.conf"
    if [[ -L "$sddm_theme_dest" || -L "$sddm_config" ]] ||
        { [ -d "$sddm_theme_dest" ] && [ -n "$(find "$sddm_theme_dest" -type l -print -quit)" ]; }; then
        echo "SDDM theme or drop-in contains symbolic links. Keep it and configure SDDM from its existing files." >&2
        return 1
    fi
    backup_system_path "$sddm_config" || return 1

    if [ -d "$sddm_theme_src" ] && ! diff -rq -- "$sddm_theme_src" "$sddm_theme_dest" >/dev/null 2>&1; then
        backup_system_path "$sddm_theme_dest" || return 1
        sudo mkdir -p "$sddm_theme_dest"
        sudo cp -r "$sddm_theme_src/." "$sddm_theme_dest/"
    fi

    sudo mkdir -p /etc/sddm.conf.d

    if [ "$sddm_display_server" = "wayland" ]; then
        cat <<EOF | sudo tee "$sddm_config" > /dev/null
[Theme]
Current=material-you
ThemeDir=/usr/share/sddm/themes

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1
InputMethod=

[Wayland]
CompositorCommand=$sddm_compositor_cmd
EOF
    else
        cat <<EOF | sudo tee "$sddm_config" > /dev/null
[Theme]
Current=material-you
ThemeDir=/usr/share/sddm/themes

[General]
DisplayServer=x11
InputMethod=
EOF
    fi

    if [ "$PM_SDDM_CURSOR_FIX" = true ]; then
        configure_sddm_cursor "$sddm_config"
    fi

    if declare -f pm_configure_sddm_session >/dev/null; then
        pm_configure_sddm_session "$sddm_config"
    fi

    if [ "$init_sys" = systemd ]; then
        if [[ -n "$current_dm" && "$current_dm" != sddm ]]; then
            sudo systemctl disable "$current_dm.service" || return 1
            if ! sudo systemctl enable sddm.service; then
                sudo systemctl enable "$current_dm.service" || true
                return 1
            fi
        else
            sudo systemctl enable sddm.service || return 1
        fi
    elif declare -f pm_enable_display_manager >/dev/null; then
        pm_enable_display_manager "sddm" "$init_sys"
    else
        enable_system_service "sddm" "$init_sys"
    fi

    echo -e "  \e[32m$(t "installer.deploy.sddm_success")\e[0m"
}

setup_pam_service() {
    local pam_dir="/etc/pam.d"
    local target="$pam_dir/serpantinum"
    local base=""

    [ -d "$pam_dir" ] || return 0
    [ -e /etc/NIXOS ] && return 0

    for candidate in system-auth login; do
        if [ -f "$pam_dir/$candidate" ]; then
            base="$candidate"
            break
        fi
    done
    [ -n "$base" ] || return 0

    local content=""
    if ! grep -qs "pam_fprintd" "$pam_dir/$base"; then
        content+="-auth       sufficient   pam_fprintd.so"$'\n'
    fi
    content+="auth        include      $base"$'\n'
    content+="account     include      $base"$'\n'

    if [ -e "$target" ] || [ -L "$target" ]; then
        return 0
    fi

    printf '%s' "$content" | sudo tee "$target" >/dev/null
    sudo chmod 644 "$target"
}

remove_settings_desktop_entry() {
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local apps_dir="$data_home/applications"
    local icons_dir="$data_home/icons/hicolor"

    if [ -f "$apps_dir/serpantinum-settings.desktop" ]; then
        rm -f "$apps_dir/serpantinum-settings.desktop"
        if command -v update-desktop-database >/dev/null 2>&1; then
            update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
        fi
    fi

    if [ -f "$icons_dir/scalable/apps/serpantinum-settings.svg" ]; then
        rm -f "$icons_dir/scalable/apps/serpantinum-settings.svg"
        if command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache -qf "$icons_dir" >/dev/null 2>&1 || true
        fi
    fi
}

# Replace <dst> with a copy of <src> (without Python caches). The copy is
# staged first so an interrupted copy never leaves a half-written tree.
create_config_backup_dir() {
    local parent="$1" prefix="$2"
    mkdir -p -- "$parent" && mktemp -d -- "$parent/${prefix}_XXXXXX"
}

confirm_config_replacement() {
    if [ "${MANAGED_INSTALL:-false}" = true ]; then
        [ "$OPT_REPLACE_CONFIG" = true ]
        return
    fi
    local answer
    printf 'Back up and replace matching configuration files in %s? [y/N] ' "$1" >&2
    if [ -t 0 ]; then
        read -r answer || return 1
    elif [ -r /dev/tty ]; then
        read -r answer < /dev/tty || return 1
    else
        return 1
    fi
    [[ "$answer" =~ ^[Yy]$ ]]
}

replace_config_file() (
    local source="$1" destination="$2" staged
    staged="$(mktemp -- "${destination}.new.XXXXXX")" || return 1
    trap 'rm -f -- "$staged"' EXIT
    cp -p -- "$source" "$staged" && mv -T -- "$staged" "$destination"
)

install_config_tree() {
    local source="$1" target="$2" entry destination backup
    local changed=false replaces=false
    [ -d "$source" ] || return 1

    if [ -L "$target" ] || { [ -e "$target" ] && [ ! -d "$target" ]; }; then
        echo "Cannot deploy into $target. The existing path was kept." >&2
        return 1
    fi
    while IFS= read -r -d '' entry; do
        destination="$target/${entry#"$source/"}"
        if [ -L "$destination" ] || [ -L "$entry" ]; then
            echo "Cannot deploy linked config $destination." >&2
            return 1
        fi
        if [ -d "$entry" ]; then
            if [ -e "$destination" ] && [ ! -d "$destination" ]; then
                echo "Cannot replace a file with a config directory at $destination." >&2
                return 1
            fi
            [ -d "$destination" ] || changed=true
        elif [ -e "$destination" ] && [ ! -f "$destination" ]; then
            echo "Cannot deploy a config file over $destination." >&2
            return 1
        elif ! cmp -s -- "$entry" "$destination"; then
            changed=true
            if [ -e "$destination" ]; then replaces=true; fi
        fi
    done < <(find "$source" -mindepth 1 -print0)
    [ "$changed" = true ] || return 0

    if [ -d "$target" ]; then
        if [ "$replaces" = true ] && ! confirm_config_replacement "$target"; then
            printf 'Keeping %s. For a custom compositor configuration, add serpantinumd start to its autostart.\n' "$target"
            return 0
        fi
        if [ "$replaces" = true ] || [ "${MANAGED_INSTALL:-false}" != true ]; then
            backup="$(create_config_backup_dir "${target}_backup" backup)" || return 1
            if ! cp -a -- "$target/." "$backup/"; then
                echo "Backup failed for $target. Its contents were kept." >&2
                return 1
            fi
            printf 'Backup of %s: %s\n' "$target" "$backup"
        fi
    fi
    mkdir -p -- "$target" || return 1
    while IFS= read -r -d '' entry; do
        destination="$target/${entry#"$source/"}"
        if [ -d "$entry" ]; then
            mkdir -p -- "$destination" || return 1
        elif ! cmp -s -- "$entry" "$destination"; then
            replace_config_file "$entry" "$destination" || return 1
        fi
    done < <(find "$source" -mindepth 1 -print0)
}

# Updates never overwrite compositor configs wholesale. A file the user has not edited
# (identical to the version shipped by the previous commit) is replaced by the new one,
# after a backup; an edited file is kept and only reported.
update_untouched_compositor_file() {
    local repo="$1" old_commit="$2" file="$3"
    shift 3
    local comp_part="${file#compositor*/}"
    local comp_name="${comp_part%%/*}" comp_file="${comp_part#*/}" comp target dest backup
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    for comp in "$@"; do
        [[ "$comp" == "$comp_name" ]] || continue
        case "$comp" in
            hyprland) target="hypr" ;;
            *) target="$comp" ;;
        esac
        dest="$config_home/$target/$comp_file"
        if [[ -L "$config_home/$target" || -L "$(dirname "$dest")" ]]; then
            echo "Preserving linked compositor config: $dest"
            continue
        fi
        [ -f "$repo/$file" ] || continue
        cmp -s "$repo/$file" "$dest" && continue
        if [ -L "$dest" ]; then
            echo -e "\e[33m[ NOTE ]\e[0m ~/.config/$target/$comp_file is a symlink and was kept; the new version is $repo/$file"
        elif [ ! -e "$dest" ]; then
            mkdir -p "$(dirname "$dest")" && replace_config_file "$repo/$file" "$dest" || return 1
        elif [ -n "$old_commit" ] && git -C "$repo" show "$old_commit:$file" 2>/dev/null | cmp -s - "$dest"; then
            backup="$(create_config_backup_dir "$config_home/${target}_backup" update)" || return 1
            backup="$backup/$comp_file"
            if mkdir -p "$(dirname "$backup")" && cp -a "$dest" "$backup" && replace_config_file "$repo/$file" "$dest"; then
                echo -e "\e[32m[ OK ]\e[0m Updated ~/.config/$target/$comp_file (backup: $backup)"
            else
                echo "Could not back up or update $dest." >&2
                return 1
            fi
        else
            echo -e "\e[33m[ NOTE ]\e[0m ~/.config/$target/$comp_file has your own edits and was kept; the new version is $repo/$file"
        fi
    done
}

sync_program_dir() (
    local src="$1" dst="$2" work
    [ -d "$src" ] || return 0
    if [ -L "$dst" ]; then
        echo "Cannot replace the linked program directory $dst." >&2
        return 1
    fi
    work="$(mktemp -d -- "$dst.swap.XXXXXX")" || return 1
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    trap '
        if [ -e "$work/previous" ] && [ ! -e "$dst" ]; then
            mv -T -- "$work/previous" "$dst" || {
                echo "Previous program files are at $work/previous." >&2
                exit 1
            }
        fi
        rm -rf -- "$work"
    ' EXIT
    if ! mkdir "$work/new" || ! cp -r -- "$src/." "$work/new/"; then
        echo -e "\e[31m[ ERROR ]\e[0m Failed to copy $src to $dst" >&2
        return 1
    fi
    find "$work/new" -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
    if [ -e "$dst" ]; then mv -T -- "$dst" "$work/previous" || return 1; fi
    mv -T -- "$work/new" "$dst"
)

install_launcher_link() {
    local source="$1" link="$2"
    local global="/usr/local/bin/${link##*/}"
    if [ -e "$link" ] || [ -L "$link" ]; then
        if [ "$(readlink -- "$link")" != "$source" ]; then
            echo "Launcher path $link already belongs to another installation." >&2
            return 1
        fi
    else
        ln -s -- "$source" "$link" || return 1
    fi
    if [ ! -e "$global" ] && [ ! -L "$global" ]; then
        if [ "${MANAGED_INSTALL:-false}" = true ]; then
            if [ "${OPT_GLOBAL_LAUNCHERS:-false}" = true ]; then
                sudo ln -sT -- "$source" "$global" || return 1
            fi
        else
            sudo ln -s -- "$source" "$global" || echo "Launcher installed in $link."
        fi
    fi
}

deploy_package() {
    local REPO_ROOT="$1"
    local OLD_COMMIT="$2"
    local IS_REINSTALL="$4"
    local INSTALL_STATE="$5"
    shift 5
    local COMPOSITORS=("$@")

    local TARGET_BASE="$HOME/.local/share/serpantinum"
    local BIN_DIR="$HOME/.local/bin"

    local is_update=false
    if [[ "$INSTALL_STATE" == "current" && "$IS_REINSTALL" != "true" ]]; then
        is_update=true
    fi

    local comp cfg src_comp
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    mkdir -p "$TARGET_BASE" "$BIN_DIR"

    if [ "${MANAGED_INSTALL:-false}" = true ] && [ "$OPT_CONFIG" != true ]; then
        echo "Keeping compositor and Kitty configuration."
    elif [ "$is_update" = true ]; then
        # Refresh stock Hyprland files and leave locally modified ones in place.
        for cfg in config/settings.lua config/keybinds.lua config/canvas.lua config/autostart.lua config/env.lua hyprland.lua; do
            update_untouched_compositor_file "$REPO_ROOT" "$OLD_COMMIT" \
                "compositors/hyprland/$cfg" "${COMPOSITORS[@]}" || return 1
        done
        for cfg in config.toml config/input.toml config/layout.toml config/autostart.toml config/keybinds.toml; do
            update_untouched_compositor_file "$REPO_ROOT" "$OLD_COMMIT" \
                "compositors/umbriel/$cfg" "${COMPOSITORS[@]}" || return 1
        done
    else
        for cfg in "${EXTRA_CONFIGS[@]}"; do
            install_config_tree "$REPO_ROOT/config/$cfg" "$config_home/$cfg" || return 1
        done
        for comp in "${COMPOSITORS[@]}"; do
            src_comp="$REPO_ROOT/compositors/$comp"
            [ -d "$src_comp" ] || src_comp="$REPO_ROOT/compositor/$comp"
            cfg="$(get_compositor_config_dir_name "$comp")"
            install_config_tree "$src_comp" "$config_home/$cfg" || return 1
        done
    fi

    # Mirror installed program directories, including local source changes.
    # User data and the cached VPN bundle live outside these directories.
    for cfg in bin src themess; do
        if [ "${MANAGED_INSTALL:-false}" = true ] &&
            diff -rq -x __pycache__ -x version.txt -- "$REPO_ROOT/$cfg" "$TARGET_BASE/$cfg" >/dev/null 2>&1; then
            continue
        fi
        sync_program_dir "$REPO_ROOT/$cfg" "$TARGET_BASE/$cfg" || return 1
    done
    chmod +x "$TARGET_BASE/bin/"* 2>/dev/null || true
    find "$TARGET_BASE/src" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} + 2>/dev/null || true

    if [ -f "$REPO_ROOT/version.txt" ]; then
        replace_config_file "$REPO_ROOT/version.txt" "$TARGET_BASE/src/version.txt" || return 1
    fi

    if [ -f "$TARGET_BASE/bin/serpantinum" ]; then
        install_launcher_link "$TARGET_BASE/bin/serpantinum" "$BIN_DIR/serpantinum" || return 1
    fi

    if [ -f "$TARGET_BASE/bin/serpantinumd" ]; then
        install_launcher_link "$TARGET_BASE/bin/serpantinumd" "$BIN_DIR/serpantinumd" || return 1
    fi

    if [ "${MANAGED_INSTALL:-false}" != true ] || [ "$OPT_CONFIG" = true ]; then
        remove_settings_desktop_entry
    fi
    if [ "${MANAGED_INSTALL:-false}" != true ] || [ "$OPT_SERVICES" = true ]; then
        setup_pam_service
    fi
}
