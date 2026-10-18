#!/usr/bin/env bash
# Restart the app after install; never force a second Ghostty window.
# Run outside the Ghostty process being closed.
set -euo pipefail

DEFERRED=0
RELAUNCH=1
for flag in "$@"; do
  case "$flag" in
    --foreground) ;;
    --deferred) DEFERRED=1 ;;
    --no-relaunch) RELAUNCH=0 ;;
    *) echo "[FAIL] Ghostty restart: invalid mode $flag" >&2; exit 2 ;;
  esac
done

# Native macOS pgrep/pkill user selection avoids affecting other users' apps.
UID_ACTUAL="$(id -u)"
running() { pgrep -u "$UID_ACTUAL" -ix ghostty >/dev/null 2>&1; }
say() {
  local message="$*" color='' reset=''
  # Same label palette as install.sh. Detached output stays uncolored.
  if [[ -z "${NO_COLOR:-}" && "${HJ_INSTALL_COLOR:-auto}" != never ]] &&
     { [[ -t 1 ]] || [[ "${HJ_INSTALL_COLOR:-auto}" == always ]]; }; then
    case "$message" in
      '[PASS]'*) color=$'\033[1;32m' ;;
      '[FAIL]'*) color=$'\033[1;31m' ;;
      '[INFO]'*) color=$'\033[1;36m' ;;
    esac
    reset=$'\033[0m'
  fi
  if [[ -n "$color" ]]; then
    printf '%s%s%s\n' "$color" "$message" "$reset"
  else
    printf '%s\n' "$message"
  fi
}

if (( DEFERRED )); then
  # Let install.sh finish printing before SIGTERM closes its own terminal.
  sleep 2
fi

if running; then
  say "[INFO] Closing existing Ghostty instance (save active work before installing)."
  if ! pkill -TERM -u "$UID_ACTUAL" -ix ghostty; then
    say "[FAIL] Cannot close Ghostty; refusing to launch a second instance." >&2
    exit 1
  fi
  # macOS may need time to release its quick-terminal hotkey and accessory-app registration.
  stopped=0
  for ((i=0; i<40; i++)); do
    if ! running; then stopped=1; break; fi
    sleep 0.25
  done
  if [[ "$stopped" != 1 ]]; then
    say "[FAIL] Ghostty did not stop within 10 seconds; no relaunch attempted." >&2
    exit 1
  fi
  say "[PASS] Previous Ghostty instance stopped."
else
  say "[INFO] Ghostty is not running."
fi

if (( ! RELAUNCH )); then
  say "[PASS] --no-relaunch: left Ghostty stopped as requested."
  exit 0
fi

# Small delay after confirmed exit; never a substitute for process checks.
sleep 1
say "[INFO] Starting Ghostty from Applications..."
if ! open -a Ghostty; then
  say "[FAIL] macOS couldn't start Ghostty. Try: open -a Ghostty" >&2
  exit 1
fi
for ((i=0; i<40; i++)); do
  if running; then
    say "[PASS] Ghostty is running. Press Option+Tab to open the dropdown."
    exit 0
  fi
  sleep 0.25
done
say "[FAIL] macOS accepted launch, but no Ghostty process was detected." >&2
exit 1
