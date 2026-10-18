#!/usr/bin/env bash
# Verify Hack-Jitsu prompt, styling, and strict Ghostty-only isolation.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/prefix/share/zsh-syntax-highlighting" \
  "$TMP/prefix/share/zsh-autosuggestions"
printf '_zsh_highlight() { :; }\n' > \
  "$TMP/prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
printf '_zsh_autosuggest_start() { :; }\n' > \
  "$TMP/prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
export HOME="$TMP/home" ZDOTDIR="$TMP/home" XDG_STATE_HOME="$TMP/state"
export HOMEBREW_PREFIX="$TMP/prefix"
export HJ_TEST_SHELL="$ROOT/shell/hj.zsh" HJ_TEST_REPO="$ROOT"
TERM_PROGRAM=ghostty TERM=xterm-ghostty zsh -fic '
  source "$HJ_TEST_SHELL"
  [[ "$PROMPT" == *"#ec1313"* ]] || exit 10
  [[ "$PROMPT" == *"❯"* && "$PROMPT" != *"%n"* && "$PROMPT" != *"%~"* ]] || exit 11
  [[ "$ZSH_HIGHLIGHT_STYLES[command]" == "fg=cyan,bold" ]] || exit 12
  [[ "$ZSH_HIGHLIGHT_STYLES[path]" == "fg=cyan,underline" ]] || exit 13
  [[ "$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE" == "fg=242" ]] || exit 14
  (( $+functions[_zsh_highlight] )) || exit 15
  (( $+functions[_zsh_autosuggest_start] )) || exit 16
  [[ "$RPROMPT" == "" ]] || exit 17
  source "$HJ_TEST_SHELL"
  [[ "$PROMPT" == *"#ec1313"* ]] || exit 18
'
TERM_PROGRAM=Apple_Terminal TERM=xterm-256color zsh -fic '
  source "$HJ_TEST_SHELL"
  [[ "$PROMPT" != *"#ec1313"* ]] || exit 20
'
TERM_PROGRAM=ghostty TERM=xterm-ghostty SSH_CONNECTION="dummy" zsh -fic '
  source "$HJ_TEST_SHELL"
  [[ "$PROMPT" != *"#ec1313"* ]] || exit 21
'
echo 'PASS: minimal prompt, command highlighting, autosuggestions, SSH/Terminal isolation'
