#!/usr/bin/env bash
# GUI launch checks use mocked macOS commands; never stop a real Ghostty.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_STATE_HOME="$TMP/home/.local/state" HJ_LAUNCH_LOG="$TMP/actions.log"
mkdir -p "$HOME" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/open" <<'EOF'
#!/bin/sh
printf 'open %s\n' "$*" >> "$HJ_LAUNCH_LOG"
EOF
cat > "$TMP/bin/pgrep" <<'EOF'
#!/bin/sh
[ -f "$HJ_LAUNCH_LOG" ] && grep -q '^osascript' "$HJ_LAUNCH_LOG" && exit 1
[ "${HJ_FAKE_GHOSTTY_RUNNING:-0}" = 1 ] && exit 0
exit 1
EOF
cat > "$TMP/bin/osascript" <<'EOF'
#!/bin/sh
printf 'osascript %s\n' "$*" >> "$HJ_LAUNCH_LOG"
EOF
chmod +x "$TMP/bin"/*
: > "$HJ_LAUNCH_LOG"
bash "$ROOT/install.sh" --dry-run --no-brew --no-shell --no-nvim --launch >"$TMP/dry.log"
test ! -s "$HJ_LAUNCH_LOG"
bash "$ROOT/install.sh" --check --no-nvim --no-shell --launch >"$TMP/check.log" 2>&1 || true
test ! -s "$HJ_LAUNCH_LOG"
bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim --launch >"$TMP/launch.log"
grep -Fq 'HACK-JITSU EDITION | SETUP FINISHED' "$TMP/launch.log"
grep -Fq 'Option (Alt) + Tab' "$TMP/launch.log"
grep -Eq '^open (-a Ghostty|.*/Ghostty.app)' "$HJ_LAUNCH_LOG"
: > "$HJ_LAUNCH_LOG"
HJ_FAKE_GHOSTTY_RUNNING=1 bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim --launch --no-restart >"$TMP/no-restart.log"
test ! -s "$HJ_LAUNCH_LOG"
HJ_FAKE_GHOSTTY_RUNNING=1 bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim --restart >"$TMP/restart.log"
grep -q '^osascript' "$HJ_LAUNCH_LOG"
grep -Eq '^open (-a Ghostty|.*/Ghostty.app)' "$HJ_LAUNCH_LOG"
echo 'PASS: immediate quick start, launch, explicit restart, no GUI actions in dry-run/check'
