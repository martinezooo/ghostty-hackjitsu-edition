#!/usr/bin/env bash
# Verify rich shell UX without installing packages or altering personal dotfiles.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_STATE_HOME="$TMP/home/.local/state"
export XDG_CACHE_HOME="$TMP/home/.cache" HOMEBREW_PREFIX="$TMP/prefix"
export PATH="$TMP/bin:$PATH"
export HJ_TEST_EDIT_LOG="$TMP/zellij-edit.log"
mkdir -p "$TMP/bin" "$TMP/prefix/opt/fzf-tab/share/fzf-tab" \
  "$TMP/prefix/share/zsh-autosuggestions" "$TMP/prefix/share/zsh-syntax-highlighting" "$HOME"
cat > "$TMP/bin/eza" <<'STUB'
#!/bin/sh
echo "FAKE_EZA $*"
STUB
cat > "$TMP/bin/fastfetch" <<'STUB'
#!/bin/sh
echo "FAKE_FETCH $*"
STUB
cat > "$TMP/bin/fzf" <<'STUB'
#!/bin/sh
exit 0
STUB
cat > "$TMP/bin/zellij" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$HJ_TEST_EDIT_LOG"
if [ "$1" = --config ] && [ "$3" = setup ] && [ "$4" = --check ]; then
  echo '[CONFIG FILE]: Well defined.'
fi
STUB
chmod +x "$TMP/bin"/*
cat > "$TMP/prefix/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh" <<'STUB'
[[ $+functions[compdef] -eq 1 ]] || return 4
HJ_FZF_TAB_LOADED=1
STUB
cat > "$TMP/prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh" <<'STUB'
[[ "${HJ_FZF_TAB_LOADED:-0}" == 1 ]] || return 4
_zsh_autosuggest_start() { :; }
STUB
cat > "$TMP/prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" <<'STUB'
[[ "${HJ_FZF_TAB_LOADED:-0}" == 1 ]] || return 4
_zsh_highlight() { :; }
STUB
printf '%s\n' 'alias private="not shared"' > "$HOME/.zshrc"
bash "$ROOT/install.sh" --no-brew --no-quit --no-nvim >/dev/null
export ZDOTDIR="$XDG_CONFIG_HOME/ghostty-hackjitsu/zsh"
TERM_PROGRAM=ghostty TERM=xterm-ghostty HJ_AUTO_ZELLIJ=0 zsh -ic '
  [[ "${HJ_FZF_TAB_LOADED:-0}" == 1 ]] || exit 11
  # Built-in Zsh completes dozens of commands; fzf-tab is just the UI.
  [[ -n "${_comps[git]:-}" && -n "${_comps[ssh]:-}" ]] || exit 18
  [[ -n "${_comps[rsync]:-}" && -n "${_comps[grep]:-}" ]] || exit 19
  [[ -n "${_comps[eza]:-}" && "${_comps[ls]}" == "${_comps[eza]}" ]] || exit 20
  [[ "${_comps[ll]}" == "${_comps[eza]}" && "${_comps[la]}" == "${_comps[eza]}" ]] || exit 21
  [[ "$(bindkey "^I")" == *"expand-or-complete"* ]] || exit 22
  [[ "$(alias ls)" == *"eza --icons=auto"* ]] || exit 12
  [[ "$(alias ll)" == *"eza -lah"* ]] || exit 13
  (( $+functions[hjfetch] )) || exit 14
  (( $+functions[_zsh_highlight] )) || exit 15
  [[ -z "$RPROMPT" ]] || exit 16
  [[ "$PROMPT" == *"#ec1313"* && "$PROMPT" != *"%~"* ]] || exit 17
  hjfetch
' >"$TMP/local.log" 2>&1
cat "$TMP/local.log" | grep -Fq FAKE_FETCH
cat "$TMP/local.log" | grep -Fq 'logo.txt'
# Standard Neovim must be a child of the real Zsh pane and must return there
# on exit. A custom Zellij edit --in-place call can create an editor-only pane.
cat > "$TMP/bin/nvim" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$HJ_TEST_EDIT_LOG"
if [ "$1" = --config ] && [ "$3" = setup ] && [ "$4" = --check ]; then
  echo '[CONFIG FILE]: Well defined.'
fi
STUB
chmod +x "$TMP/bin/nvim"
ZELLIJ=1 TERM_PROGRAM=ghostty TERM=xterm-ghostty HJ_AUTO_ZELLIJ=0 zsh -ic '
  (( $+functions[nvim] )) && exit 31
  nvim /tmp/example.log || exit 32
  print -r -- RETURNED_TO_SHELL
' >"$TMP/zellij.log" 2>&1
grep -Fxq '/tmp/example.log' "$HJ_TEST_EDIT_LOG"
grep -Fq 'RETURNED_TO_SHELL' "$TMP/zellij.log"
! grep -Fq 'edit --in-place' "$HJ_TEST_EDIT_LOG"
grep -qx 'alias private="not shared"' "$HOME/.zshrc"
# Regular macOS shells are untouched, including their aliases and prompt.
ZDOTDIR="$HOME" TERM_PROGRAM=Apple_Terminal TERM=xterm-256color zsh -ic '
  [[ "${HJ_FZF_TAB_LOADED:-0}" == 1 ]] && exit 23
  (( $+functions[hjfetch] )) && exit 24
  true
' >"$TMP/other.log" 2>&1 || { cat "$TMP/other.log"; exit 1; }
echo 'PASS: eza aliases, Fastfetch logo, fzf-tab ordered before highlighting, private Zsh isolation'
