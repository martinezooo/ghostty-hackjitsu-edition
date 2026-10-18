#!/usr/bin/env bash
# All process calls mocked. No real Ghostty windows are touched.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_STATE_HOME="$TMP/home/.local/state"
export HJ_LAUNCH_LOG="$TMP/actions.log" HJ_PROCESS_MARKER="$TMP/ghostty-running"
mkdir -p "$HOME" "$TMP/bin"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/pgrep" <<'MOCK'
#!/bin/sh
[ -e "$HJ_PROCESS_MARKER" ]
MOCK
cat > "$TMP/bin/pkill" <<'MOCK'
#!/bin/sh
printf 'pkill %s\n' "$*" >> "$HJ_LAUNCH_LOG"
if [ "${HJ_KILL_FAIL:-0}" = 1 ]; then exit 1; fi
if [ "${HJ_KILL_STUCK:-0}" != 1 ]; then rm -f "$HJ_PROCESS_MARKER"; fi
MOCK
cat > "$TMP/bin/open" <<'MOCK'
#!/bin/sh
printf 'open %s\n' "$*" >> "$HJ_LAUNCH_LOG"
if [ "${HJ_OPEN_FAIL:-0}" = 1 ]; then exit 1; fi
if [ "${HJ_OPEN_NO_PROCESS:-0}" != 1 ]; then : > "$HJ_PROCESS_MARKER"; fi
MOCK
cat > "$TMP/bin/sleep" <<'MOCK'
#!/bin/sh
/bin/sleep 0.02
MOCK
cat > "$TMP/bin/osascript" <<'MOCK'
#!/bin/sh
printf 'osascript %s\n' "$*" >> "$HJ_LAUNCH_LOG"
exit 19
MOCK
chmod +x "$TMP/bin"/*
: > "$HJ_LAUNCH_LOG"
helper="$ROOT/shell/restart-ghostty.sh"
# If not yet running, launch once.
bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim >"$TMP/initial.log"
grep -Fq 'HACK-JITSU EDITION | SETUP FINISHED' "$TMP/initial.log"
grep -Fq 'AFTER INSTALLATION: Ghostty will close, then restart automatically' "$TMP/initial.log"
grep -Fq 'Ghostty is running. Press Option+Tab' "$TMP/initial.log"
test -e "$HJ_PROCESS_MARKER"
test "$(grep -c '^open -a Ghostty$' "$HJ_LAUNCH_LOG")" -eq 1
! grep -q '^pkill ' "$HJ_LAUNCH_LOG"
# Existing app: close -> observe disappearance -> open once.
: > "$HJ_LAUNCH_LOG"
bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim >"$TMP/restart.log"
grep -Fq '[PASS] Previous Ghostty instance stopped' "$TMP/restart.log"
test "$(grep -c '^pkill ' "$HJ_LAUNCH_LOG")" -eq 1
test "$(grep -c '^open -a Ghostty$' "$HJ_LAUNCH_LOG")" -eq 1
test "$(head -1 "$HJ_LAUNCH_LOG")" != 'open -a Ghostty'
# --no-quit, --dry-run and --check are read-only for app state.
for flag in --no-quit --dry-run --check; do
  : > "$HJ_LAUNCH_LOG"
  touch "$HJ_PROCESS_MARKER"
  bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim "$flag" >"$TMP/no-effect.log" 2>&1 || [ "$flag" = --check ]
  test -e "$HJ_PROCESS_MARKER"
  test ! -s "$HJ_LAUNCH_LOG"
done
# Explicit no-relaunch leaves app shut down.
: > "$HJ_LAUNCH_LOG"
touch "$HJ_PROCESS_MARKER"
bash "$ROOT/install.sh" --no-relaunch --no-brew --no-shell --no-nvim >"$TMP/no-relaunch.log"
grep -Fq 'left Ghostty stopped' "$TMP/no-relaunch.log"
test ! -e "$HJ_PROCESS_MARKER"
! grep -q '^open ' "$HJ_LAUNCH_LOG"
# If closing fails, do not launch an additional app.
: > "$HJ_LAUNCH_LOG"; touch "$HJ_PROCESS_MARKER"
if HJ_KILL_FAIL=1 bash "$helper" --foreground >"$TMP/fail-kill.log" 2>&1; then
  echo 'Expected failure on pkill error' >&2; exit 1
fi
grep -Fq 'refusing to launch a second instance' "$TMP/fail-kill.log"
! grep -q '^open ' "$HJ_LAUNCH_LOG"
# If opening fails, do not falsely claim success.
: > "$HJ_LAUNCH_LOG"; rm -f "$HJ_PROCESS_MARKER"
if HJ_OPEN_FAIL=1 bash "$helper" --foreground >"$TMP/fail-open.log" 2>&1; then
  echo 'Expected failure on open error' >&2; exit 1
fi
grep -Fq "couldn't start Ghostty" "$TMP/fail-open.log"
# Process still alive after TERM: no duplicate instance is started.
: > "$HJ_LAUNCH_LOG"; touch "$HJ_PROCESS_MARKER"
if HJ_KILL_STUCK=1 bash "$helper" --foreground >"$TMP/stuck.log" 2>&1; then
  echo 'Expected shutdown timeout' >&2; exit 1
fi
grep -Fq 'did not stop within 10 seconds' "$TMP/stuck.log"
! grep -q '^open ' "$HJ_LAUNCH_LOG"
# open(1) success alone is insufficient if no new Ghostty process appeared.
: > "$HJ_LAUNCH_LOG"; rm -f "$HJ_PROCESS_MARKER"
if HJ_OPEN_NO_PROCESS=1 bash "$helper" --foreground >"$TMP/no-process.log" 2>&1; then
  echo 'Expected missing new app process to fail' >&2; exit 1
fi
grep -Fq 'no Ghostty process was detected' "$TMP/no-process.log"
# Real detached helper survives the caller that is inside Ghostty.
: > "$HJ_LAUNCH_LOG"; touch "$HJ_PROCESS_MARKER"
TERM_PROGRAM=ghostty bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim >"$TMP/deferred.log"
grep -Fq 'Restart helper started' "$TMP/deferred.log"
log="$XDG_STATE_HOME/ghostty-hackjitsu/restart.log"
success=0
for i in {1..100}; do
  if [ -f "$log" ] && grep -Fq '[PASS] Ghostty is running' "$log"; then success=1; break; fi
  /bin/sleep 0.05
done
if [ "$success" != 1 ]; then
  echo 'Deferred helper failed' >&2; [ ! -f "$log" ] || cat "$log" >&2; exit 1
fi
test -e "$HJ_PROCESS_MARKER"
test "$(grep -c '^pkill ' "$HJ_LAUNCH_LOG")" -eq 1
test "$(grep -c '^open -a Ghostty$' "$HJ_LAUNCH_LOG")" -eq 1
! grep -q '^osascript ' "$HJ_LAUNCH_LOG"
# --no-relaunch from inside Ghostty also needs a detached helper.
: > "$HJ_LAUNCH_LOG"; touch "$HJ_PROCESS_MARKER"
TERM_PROGRAM=ghostty bash "$ROOT/install.sh" --no-relaunch --no-brew --no-shell --no-nvim >"$TMP/deferred-stop.log"
log="$XDG_STATE_HOME/ghostty-hackjitsu/restart.log"
stopped=0
for i in {1..100}; do
  if [ -f "$log" ] && grep -Fq 'left Ghostty stopped as requested' "$log"; then stopped=1; break; fi
  /bin/sleep 0.05
done
test "$stopped" = 1
test ! -e "$HJ_PROCESS_MARKER"
! grep -q '^open ' "$HJ_LAUNCH_LOG"
test "$(stat -f %Lp "$log" 2>/dev/null || stat -c %a "$log")" = 600
for flag in --restart --launch; do
  if bash "$ROOT/install.sh" "$flag" >"$TMP/rejected.log" 2>&1; then
    echo "Obsolete flag unexpectedly accepted: $flag" >&2; exit 1
  fi
done
echo 'PASS: launch/restart from Terminal and Ghostty, no duplicate, safeguarded failures and opt-outs'
