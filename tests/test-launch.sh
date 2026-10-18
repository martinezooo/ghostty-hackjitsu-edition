#!/usr/bin/env bash
# Simulate Ghostty processes, without touching the real app on this Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_STATE_HOME="$TMP/home/.local/state"
export HJ_LAUNCH_LOG="$TMP/actions.log" HJ_PROCESS_MARKER="$TMP/ghostty-running"
mkdir -p "$HOME" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/pgrep" <<'EOF'
#!/bin/sh
[ -e "$HJ_PROCESS_MARKER" ]
EOF
cat > "$TMP/bin/osascript" <<'EOF'
#!/bin/sh
printf 'osascript %s\n' "$*" >> "$HJ_LAUNCH_LOG"
if [ "${HJ_QUIT_METHOD:-graceful}" = graceful ]; then rm -f "$HJ_PROCESS_MARKER"; fi
EOF
cat > "$TMP/bin/pkill" <<'EOF'
#!/bin/sh
printf 'pkill %s\n' "$*" >> "$HJ_LAUNCH_LOG"
if [ "${HJ_QUIT_METHOD:-graceful}" = term ]; then rm -f "$HJ_PROCESS_MARKER"; fi
EOF
cat > "$TMP/bin/open" <<'EOF'
#!/bin/sh
printf 'open %s\n' "$*" >> "$HJ_LAUNCH_LOG"
EOF
cat > "$TMP/bin/nohup" <<'EOF'
#!/bin/sh
printf 'nohup %s\n' "$*" >> "$HJ_LAUNCH_LOG"
EOF
chmod +x "$TMP/bin"/*
: > "$HJ_LAUNCH_LOG"

# No Ghostty running: setup must NOT launch it.
bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim >"$TMP/initial.log"
grep -Fq 'HACK-JITSU EDITION | SETUP FINISHED' "$TMP/initial.log"
grep -Fq 'AFTER INSTALLATION: Ghostty will QUIT COMPLETELY.' "$TMP/initial.log"
grep -Fq '[PASS] Ghostty is already stopped' "$TMP/initial.log"
test ! -s "$HJ_LAUNCH_LOG"

# Running instance: graceful quit, never open again.
touch "$HJ_PROCESS_MARKER"
HJ_QUIT_METHOD=graceful bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim >"$TMP/graceful.log"
grep -Fq '[PASS] Ghostty completely stopped' "$TMP/graceful.log"
test ! -e "$HJ_PROCESS_MARKER"
grep -q '^osascript ' "$HJ_LAUNCH_LOG"
! grep -q '^open ' "$HJ_LAUNCH_LOG"

# If graceful quit fails to close the app, SIGTERM is attempted.
: > "$HJ_LAUNCH_LOG"
touch "$HJ_PROCESS_MARKER"
HJ_QUIT_METHOD=term bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim >"$TMP/term.log"
grep -q '^pkill ' "$HJ_LAUNCH_LOG"
test ! -e "$HJ_PROCESS_MARKER"
! grep -q '^open ' "$HJ_LAUNCH_LOG"

# --no-quit, --dry-run and --check never touch the running instance.
for flags in '--no-quit' '--dry-run' '--check'; do
  : > "$HJ_LAUNCH_LOG"
  touch "$HJ_PROCESS_MARKER"
  bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim $flags >"$TMP/no-effect.log" 2>&1 || [ "$flags" = --check ]
  test -e "$HJ_PROCESS_MARKER"
  test ! -s "$HJ_LAUNCH_LOG"
done

# When launched *inside* Ghostty, the quit must be deferred outside its shell.
: > "$HJ_LAUNCH_LOG"
touch "$HJ_PROCESS_MARKER"
TERM_PROGRAM=ghostty bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim >"$TMP/deferred.log"
grep -Fq 'Ghostty will quit completely after this terminal session finishes.' "$TMP/deferred.log"
grep -q '^nohup ' "$HJ_LAUNCH_LOG"
! grep -q '^open ' "$HJ_LAUNCH_LOG"

# Deprecated restart/launch flags must not recreate the old behavior.
for flag in --restart --launch; do
  if bash "$ROOT/install.sh" "$flag" >"$TMP/rejected.log" 2>&1; then
    echo "Deprecated flag succeeded unexpectedly: $flag" >&2; exit 1
  fi
done
printf '%s\n' 'PASS: installer quits all Ghostty instances, never relaunches, preserves check/dry-run/no-quit'
