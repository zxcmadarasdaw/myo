#!/usr/bin/env bash

# Bootstrap only the runtime needed to start the structured queue. These small
# native transactions retain their own explicit user confirmation.
pm_queue_run() {
    local backend="$1" package check
    shift
    if ! command -v python3 >/dev/null; then
        package=python3
        [ "$backend" != pacman ] || package=python
        bootstrap_tool "$package" 'Python 3 is required for the download queue.' || return 1
    fi
    if [ "$backend" = dnf ]; then
        package=python3-dnf check='import dnf'
        if command -v dnf5 >/dev/null; then package=python3-libdnf5; check='import libdnf5.base, libdnf5.repo, libdnf5.rpm'; fi
        if ! python3 -c "$check" 2>/dev/null; then
            bootstrap_tool "$package" 'The native DNF Python API is required to resolve the download queue.' || return 1
            python3 -c "$check" || return 1
        fi
    fi
    python3 "$PM_QUEUE_WORKER" "$backend" "$@"
}
