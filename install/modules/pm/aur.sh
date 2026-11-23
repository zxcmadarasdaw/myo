#!/usr/bin/env bash

# A fallback is defined only where the project knows the corresponding AUR
# recipe. A missing repository package does not authorize an arbitrary recipe.
pm_aur_recipe() {
    case "$1" in
        quickshell) printf '%s\n' quickshell-git ;;
        umbriel) printf '%s\n' umbriel-git ;;
        xdg-desktop-portal-umbriel-git) printf '%s\n' xdg-desktop-portal-umbriel-git ;;
        *) return 1 ;;
    esac
}

pm_aur_install() (
    local package="$1" recipe work answer missing file
    recipe="$(pm_aur_recipe "$package")" || return 1
    [ "$EUID" -ne 0 ] && [ "$OPT_AUR" = true ] && [ "$OPT_BUILD" = true ] || return 1
    if pacman -Si -- "$package" >/dev/null 2>&1; then
        pm_pacman_install "$package"
        return
    fi
    pacman -Sl >/dev/null || return 1
    if [ "$package" = umbriel ] && ! pm_is_installed xdg-desktop-portal-umbriel-git; then
        # The Umbriel recipe requires this other AUR package. Review and
        # install it independently, since makepkg only resolves binary repos.
        pm_aur_install xdg-desktop-portal-umbriel-git || return 1
    fi
    work="$(mktemp -d -- "$MANAGER_TMP/aur.XXXXXX")" || return 1
    printf '@@activity\tDownloading\tAUR recipe %s\n' "$recipe"
    git clone --depth 1 -- "https://aur.archlinux.org/$recipe.git" "$work/recipe" || return 1
    cd "$work/recipe" || return 1
    printf 'Review AUR recipe %s at %s\n' "$recipe" "$(git rev-parse HEAD)"
    git ls-files -z | while IFS= read -r -d '' file; do
        printf '\n--- %s ---\n' "$file"
        if [ -L "$file" ] || [ ! -f "$file" ] || [ "$(wc -c < "$file")" -gt 65536 ]; then
            printf 'File cannot be reviewed in the installer.\n'
            exit 1
        fi
        sed 's/^/| /' -- "$file" || exit 1
    done || return 1
    printf '\n@@ask\tBuild and install the reviewed %s recipe? Type BUILD to approve: ' "$recipe"
    read -r answer </dev/tty || return 1
    [ "$answer" = BUILD ] || return 1
    missing="$(pm_missing_pkgs base-devel)" || return 1
    [ -z "$missing" ] || pm_pacman_install base-devel || return 1
    printf '@@activity\tBuilding\t%s\n' "$recipe"
    makepkg --syncdeps --install --needed < /dev/tty
)
