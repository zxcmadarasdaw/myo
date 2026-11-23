#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home" XDG_STATE_HOME="$work/state" XDG_CACHE_HOME="$work/cache"
export SERPANTINUM_DIR="$repo/src" TELEMETRY_TEST_LOG="$work/network"
mkdir -p "$HOME" "$work/bin"
cat > "$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TELEMETRY_TEST_LOG"
EOF
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH"
source "$repo/install/modules/version.sh"

[ "$(get_telemetry_enabled)" = false ]
write_version_state 2.5.1 fixture "" false hyprland
grep -Fx 'TELEMETRY_ID=""' "$VERSION_FILE"
grep -Fx 'ENABLE_TELEMETRY="false"' "$VERSION_FILE"
bash "$repo/install/modules/telemetry.sh" --mode init --os Test --version fixture
bash "$repo/install/modules/telemetry.sh" --mode done --enabled false --os Test --version fixture
[ ! -e "$TELEMETRY_TEST_LOG" ]
printf 'PASS: fresh and explicit opt-out emit no requests and store no telemetry ID\n'
