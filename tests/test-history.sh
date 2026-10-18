#!/usr/bin/env bash
# Zsh history must survive Ghostty restarts without importing personal .zshrc.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HJ_AUTO_ZELLIJ=0 TERM_PROGRAM=Apple_Terminal

setup_profile() {
  export HOME="$1"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"
  export ZDOTDIR="$XDG_CONFIG_HOME/ghostty-hackjitsu/zsh"
  mkdir -p "$HOME"
  bash "$ROOT/install.sh" --no-quit --no-brew --no-shell --no-nvim >"$TMP/install.log"
}

# Reuse a pre-existing standard zsh history, not a disconnected blank one.
oldhome="$TMP/has-existing-history"
mkdir -p "$oldhome"
printf ': 1750000000:0;echo HJ_OLD_HISTORY_FIXTURE\n' > "$oldhome/.zsh_history"
chmod 600 "$oldhome/.zsh_history"
setup_profile "$oldhome"
zsh -ic '[[ "$HISTFILE" == "$HOME/.zsh_history" ]] && [[ "$HISTSIZE" -ge 50000 ]] && [[ "$SAVEHIST" -ge 50000 ]] && [[ -o sharehistory ]] && [[ -o histignorespace ]]' >/dev/null 2>&1
zsh -ic 'fc -R "$HISTFILE"; fc -l 1' > "$TMP/existing-history-output" 2>&1
grep -Fq HJ_OLD_HISTORY_FIXTURE "$TMP/existing-history-output"
# Verify a real interactive shell imports existing history automatically.
printf 'fc -l 1\nexit\n' | zsh -i > "$TMP/interactive-old" 2>&1
grep -Fq HJ_OLD_HISTORY_FIXTURE "$TMP/interactive-old"
test -f "$oldhome/.zsh_history"

# On a fresh machine create a private persistent fallback, without touching ~/.zsh_history.
fresh="$TMP/fresh-home"
setup_profile "$fresh"
zsh -ic '[[ "$HISTFILE" == "${XDG_STATE_HOME}/ghostty-hackjitsu/zsh_history" ]] && [[ -f "$HISTFILE" ]]' >/dev/null 2>&1
test ! -e "$fresh/.zsh_history"
test "$(stat -f %Lp "$fresh/.local/state/ghostty-hackjitsu/zsh_history")" = 600
zsh -ic 'print -s "echo HJ_NEW_HISTORY_FIXTURE"; fc -A "$HISTFILE"' >/dev/null 2>&1
grep -Fq HJ_NEW_HISTORY_FIXTURE "$fresh/.local/state/ghostty-hackjitsu/zsh_history"
zsh -ic 'fc -R "$HISTFILE"; fc -l 1' > "$TMP/persisted-history-output" 2>&1
grep -Fq HJ_NEW_HISTORY_FIXTURE "$TMP/persisted-history-output"
printf 'fc -l 1\nexit\n' | zsh -i > "$TMP/interactive-new" 2>&1
grep -Fq HJ_NEW_HISTORY_FIXTURE "$TMP/interactive-new"
echo 'PASS: interactive old history restored, new history persists, private fallback has 0600 permissions'
