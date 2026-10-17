#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
mkdir -p "$HOME"
# Dry-run must not write anything.
bash "$ROOT/install.sh" --dry-run --no-brew >"$TMP/dry-run.log"
test ! -e "$HOME/.config"
test ! -e "$HOME/.zshrc"
# Package plans respect the Neovim opt-out.
bash "$ROOT/install.sh" --dry-run >"$TMP/full-plan.log"
grep -q 'PLAN brew install neovim' "$TMP/full-plan.log"
bash "$ROOT/install.sh" --dry-run --no-nvim >"$TMP/no-nvim-plan.log"
if grep -q 'PLAN brew install neovim' "$TMP/no-nvim-plan.log"; then
  echo "Unexpected Neovim package installation with --no-nvim" >&2; exit 1
fi
# Simulate pre-existing user settings, ensure backups.
mkdir -p "$HOME/.config/ghostty"
printf 'old config\n' > "$HOME/.config/ghostty/config"
printf '# existing profile\n' > "$HOME/.zshrc"
bash "$ROOT/install.sh" --no-brew >"$TMP/install.log"
cmp -s "$ROOT/ghostty/config" "$HOME/.config/ghostty/config"
test -f "$HOME/.config/ghostty/hack-jitsu-watermark.png"
test -f "$HOME/.config/ghostty-hackjitsu/cheats/pentest.cheat"
test -f "$HOME/.config/ghostty-hackjitsu/cheats/network.cheat"
test -f "$HOME/.config/ghostty-hackjitsu/shell.zsh"
test -f "$HOME/.config/nvim/init.lua"
test -f "$HOME/.config/nvim/lua/config/lazy.lua"
test -f "$HOME/.config/nvim/LICENSE"
test "$(grep -c '# >>> Ghostty Hack-Jitsu Edition >>>' "$HOME/.zshrc")" -eq 1
test "$(find "$HOME/.local/state/ghostty-hackjitsu/backups" -name ghostty-config | wc -l | tr -d ' ')" -eq 1
grep -qx 'old config' "$(find "$HOME/.local/state/ghostty-hackjitsu/backups" -name ghostty-config | head -1)"
# Re-running must not duplicate shell hooks or write unnecessary backups.
before="$(find "$HOME/.local/state/ghostty-hackjitsu/backups" -type f | wc -l)"
bash "$ROOT/install.sh" --no-brew >"$TMP/reinstall.log"
after="$(find "$HOME/.local/state/ghostty-hackjitsu/backups" -type f | wc -l)"
test "$before" -eq "$after"
test "$(grep -c '# >>> Ghostty Hack-Jitsu Edition >>>' "$HOME/.zshrc")" -eq 1
# Existing symlinks must not be overwritten.
mv "$HOME/.config/ghostty/config" "$TMP/config-previous"
ln -s "$TMP/config-previous" "$HOME/.config/ghostty/config"
if bash "$ROOT/install.sh" --no-brew >"$TMP/symlink.log" 2>&1; then
  echo "Expected symlink refusal" >&2; exit 1
fi
test -L "$HOME/.config/ghostty/config"
# Existing Neovim configuration is never overwritten.
mkdir -p "$TMP/existing-home/.config/nvim"
printf 'private user config\n' > "$TMP/existing-home/.config/nvim/init.lua"
HOME="$TMP/existing-home" XDG_CONFIG_HOME="$TMP/existing-home/.config" \
  XDG_STATE_HOME="$TMP/existing-home/.local/state" \
  bash "$ROOT/install.sh" --no-brew --no-shell >"$TMP/existing.log"
grep -qx 'private user config' "$TMP/existing-home/.config/nvim/init.lua"
test ! -e "$TMP/existing-home/.config/nvim/lua/config/lazy.lua"
# --no-nvim installs other assets but never creates Neovim's config.
mkdir -p "$TMP/skip-home"
HOME="$TMP/skip-home" XDG_CONFIG_HOME="$TMP/skip-home/.config" \
  XDG_STATE_HOME="$TMP/skip-home/.local/state" \
  bash "$ROOT/install.sh" --no-brew --no-shell --no-nvim >"$TMP/skip.log"
test ! -e "$TMP/skip-home/.config/nvim"
echo "PASS: dry run, install, backup, idempotency, symlink refusal, LazyVim preservation and opt-out"
