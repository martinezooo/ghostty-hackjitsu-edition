#!/usr/bin/env bash
# Optional real Zellij test: fresh session starts Zsh; Neovim exit returns to shell.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v zellij >/dev/null 2>&1 || ! command -v nvim >/dev/null 2>&1; then
  echo 'SKIP: Zellij or Neovim unavailable'
  exit 0
fi
TMP="$(mktemp -d)"
session="ht-$$"
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"
export ZDOTDIR="$HOME/.config/zdot"
export ZELLIJ_CONFIG_FILE="$ROOT/zellij/config.kdl"
export TERM=xterm-256color
unset ZELLIJ TMUX SSH_TTY SSH_CONNECTION TERM_PROGRAM || true
mkdir -p "$ZDOTDIR"
printf '%s\n' 'PROMPT="HJ_TEST_PROMPT> "' > "$ZDOTDIR/.zshrc"
cleanup() {
  zellij kill-session "$session" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

zellij --config "$ZELLIJ_CONFIG_FILE" setup --check | grep -Fq '[CONFIG FILE]: Well defined.'
zellij attach -b -c "$session" >"$TMP/session-start.log" 2>&1
for i in 1 2 3 4 5 6; do
  zellij --session "$session" action list-panes -c >"$TMP/panes.log" 2>&1 || true
  if grep -Fq 'terminal_0  terminal' "$TMP/panes.log"; then break; fi
  sleep 0.2
done
grep -Fq 'terminal_0  terminal' "$TMP/panes.log" || {
  echo 'FAIL: No interactive shell pane was opened in new Zellij session' >&2
  cat "$TMP/session-start.log" "$TMP/panes.log" >&2
  exit 1
}
if grep -Eq 'About Zellij|welcome-screen' "$TMP/panes.log"; then
  echo 'FAIL: Zellij opened an About/Welcome pane unexpectedly' >&2
  cat "$TMP/panes.log" >&2
  exit 1
fi
# Start a *shell* that runs Neovim, exits with :q! and prints a marker.
# The marker proves that the shell did not disappear when Neovim exited.
cat > "$TMP/roundtrip.sh" <<'SH'
#!/usr/bin/env sh
echo HJ_BEFORE_NVIM
nvim -u NONE -i NONE -c 'qa!' /tmp/hj-zellij-test.txt
echo HJ_AFTER_NVIM
sleep 4
SH
chmod +x "$TMP/roundtrip.sh"
zellij --session "$session" action new-tab -- /bin/sh "$TMP/roundtrip.sh" >"$TMP/newtab.log" 2>&1
ok=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  zellij --session "$session" action list-panes -c >"$TMP/panes2.log" 2>&1 || true
  if grep -Fq 'sleep 4' "$TMP/panes2.log"; then ok=1; break; fi
  sleep 0.2
done
if [ "$ok" != 1 ]; then
  echo 'FAIL: Neovim test shell did not return to its shell command' >&2
  cat "$TMP/newtab.log" "$TMP/panes2.log" >&2
  exit 1
fi
echo 'PASS: real Zellij starts an ordinary Zsh pane, avoids About screen and returns to shell after nvim :q!'
