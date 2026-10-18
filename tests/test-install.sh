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
bash "$ROOT/install.sh" --no-quit --dry-run --no-brew >"$TMP/dry-run.log"
test ! -e "$HOME/.config"
test ! -e "$HOME/.zshrc"
# A macOS application-support configuration takes precedence: warn, never overwrite.
legacy="$HOME/Library/Application Support/com.mitchellh.ghostty"
mkdir -p "$legacy"
printf 'font-size = 21\n' > "$legacy/config.ghostty"
bash "$ROOT/install.sh" --no-quit --dry-run --no-brew >"$TMP/legacy-plan.log" 2>"$TMP/legacy-warning.log"
grep -Fq 'WARNING: Ghostty may override this profile' "$TMP/legacy-warning.log"
grep -qx 'font-size = 21' "$legacy/config.ghostty"
# Package plans respect the Neovim opt-out.
bash "$ROOT/install.sh" --no-quit --dry-run >"$TMP/full-plan.log"
grep -Eq '(PLAN brew install neovim|SKIP neovim:)' "$TMP/full-plan.log"
bash "$ROOT/install.sh" --no-quit --dry-run --no-nvim >"$TMP/no-nvim-plan.log"
if grep -Eq '(PLAN brew install neovim|SKIP neovim:)' "$TMP/no-nvim-plan.log"; then
  echo "Unexpected Neovim package installation with --no-nvim" >&2; exit 1
fi
# Simulate pre-existing user settings, ensure backups.
mkdir -p "$HOME/.config/ghostty"
printf 'old config\n' > "$HOME/.config/ghostty/config"
printf '# existing profile\n' > "$HOME/.zshrc"
bash "$ROOT/install.sh" --no-quit --no-brew >"$TMP/install.log"
# The portable base is rendered with local username and Mac Option mapping.
grep -Fq 'macos-option-as-alt = left' "$HOME/.config/ghostty/config"
grep -Fq "title = $(id -un)" "$HOME/.config/ghostty/config"
test -f "$HOME/.config/ghostty-hackjitsu/ghostty-template.conf"
test -f "$HOME/.config/ghostty-hackjitsu/zellij/template.kdl"
test -f "$HOME/.config/ghostty-hackjitsu/ui-setup.sh"
test -f "$HOME/.config/ghostty/hack-jitsu-watermark.png"
test -f "$HOME/.config/ghostty-hackjitsu/cheats/pentest.cheat"
test -f "$HOME/.config/ghostty-hackjitsu/cheats/network.cheat"
test -f "$HOME/.config/ghostty-hackjitsu/shell.zsh"
grep -Fqx 'default_layout "default"' "$HOME/.config/ghostty-hackjitsu/zellij/config.kdl"
test -f "$HOME/.config/nvim/init.lua"
test -f "$HOME/.config/nvim/lua/config/lazy.lua"
test -f "$HOME/.config/nvim/LICENSE"
test -f "$HOME/.config/nvim/lua/config/ansi.lua"
grep -Fq 'require("config.ansi").setup()' "$HOME/.config/nvim/init.lua"
grep -qx '# existing profile' "$HOME/.zshrc"
test -f "$HOME/.config/ghostty-hackjitsu/zsh/.zshrc"
ZDOTDIR="$HOME/.config/ghostty-hackjitsu/zsh" zsh -ic 'whence -w wave hjhelp hj' >"$TMP/zsh-functions.log" 2>&1
grep -Fq 'hjhelp: function' "$TMP/zsh-functions.log"
grep -Fq 'wave: function' "$TMP/zsh-functions.log"
if command -v navi >/dev/null 2>&1; then
  ZDOTDIR="$HOME/.config/ghostty-hackjitsu/zsh" zsh -ic 'hjhelp --query "Git: status repo" --best-match --print' >"$TMP/hjhelp.log" 2>&1
  grep -Fq 'git status --short --branch' "$TMP/hjhelp.log"
fi
test "$(find "$HOME/.local/state/ghostty-hackjitsu/backups" -name ghostty-ui | wc -l | tr -d ' ')" -eq 1
grep -qx 'old config' "$(find "$HOME/.local/state/ghostty-hackjitsu/backups" -name ghostty-ui | head -1)"
# Re-running must not duplicate shell hooks or write unnecessary backups.
before="$(find "$HOME/.local/state/ghostty-hackjitsu/backups" -type f | wc -l)"
bash "$ROOT/install.sh" --no-quit --no-brew >"$TMP/reinstall.log"
after="$(find "$HOME/.local/state/ghostty-hackjitsu/backups" -type f | wc -l)"
test "$before" -eq "$after"
grep -qx '# existing profile' "$HOME/.zshrc"
# Existing symlinks must not be overwritten.
mv "$HOME/.config/ghostty/config" "$TMP/config-previous"
ln -s "$TMP/config-previous" "$HOME/.config/ghostty/config"
if bash "$ROOT/install.sh" --no-quit --no-brew >"$TMP/symlink.log" 2>&1; then
  echo "Expected symlink refusal" >&2; exit 1
fi
test -L "$HOME/.config/ghostty/config"
# Existing Neovim configuration is never overwritten.
mkdir -p "$TMP/existing-home/.config/nvim"
printf 'private user config\n' > "$TMP/existing-home/.config/nvim/init.lua"
HOME="$TMP/existing-home" XDG_CONFIG_HOME="$TMP/existing-home/.config" \
  XDG_STATE_HOME="$TMP/existing-home/.local/state" \
  bash "$ROOT/install.sh" --no-quit --no-brew --no-shell >"$TMP/existing.log"
grep -qx 'private user config' "$TMP/existing-home/.config/nvim/init.lua"
test ! -e "$TMP/existing-home/.config/nvim/lua/config/lazy.lua"
# An existing Hack-Jitsu managed profile is safely upgraded, without
# clobbering additional user settings, and exactly one init.lua backup.
managed="$TMP/managed-home"
mkdir -p "$managed/.config/nvim/lua/config"
printf '%s\n' '-- Portable LazyVim configuration for Ghostty Hack-Jitsu Edition.' \
  'require("config.lazy")' '-- extra personal managed option' > "$managed/.config/nvim/init.lua"
printf '%s\n' '-- preserved plugin' > "$managed/.config/nvim/lua/config/lazy.lua"
HOME="$managed" XDG_CONFIG_HOME="$managed/.config" XDG_STATE_HOME="$managed/.local/state" \
  bash "$ROOT/install.sh" --no-quit --no-brew --no-shell >"$TMP/managed-first.log"
grep -Fq 'require("config.ansi").setup()' "$managed/.config/nvim/init.lua"
cmp -s "$ROOT/nvim/lua/config/ansi.lua" "$managed/.config/nvim/lua/config/ansi.lua"
grep -Fq 'extra personal managed option' "$managed/.config/nvim/init.lua"
grep -Fq 'preserved plugin' "$managed/.config/nvim/lua/config/lazy.lua"
test "$(grep -Fc 'require("config.ansi").setup()' "$managed/.config/nvim/init.lua")" -eq 1
test -f "$(find "$managed/.local/state/ghostty-hackjitsu/backups" -name nvim-init-before-ansi | head -1)"
HOME="$managed" XDG_CONFIG_HOME="$managed/.config" XDG_STATE_HOME="$managed/.local/state" \
  bash "$ROOT/install.sh" --no-quit --no-brew --no-shell >"$TMP/managed-again.log"
test "$(grep -Fc 'require("config.ansi").setup()' "$managed/.config/nvim/init.lua")" -eq 1
test "$(find "$managed/.local/state/ghostty-hackjitsu/backups" -name nvim-init-before-ansi | wc -l | tr -d ' ')" -eq 1
# A third-party editor, even with an init.lua, stays untouched (above).
# --no-nvim installs other assets but never creates Neovim's config.
mkdir -p "$TMP/skip-home"
HOME="$TMP/skip-home" XDG_CONFIG_HOME="$TMP/skip-home/.config" \
  XDG_STATE_HOME="$TMP/skip-home/.local/state" \
  bash "$ROOT/install.sh" --no-quit --no-brew --no-shell --no-nvim >"$TMP/skip.log"
test ! -e "$TMP/skip-home/.config/nvim"
# Upgrade previous release: remove ONLY our old hook, with backup.
migrate="$TMP/migration-home"
mkdir -p "$migrate"
cat > "$migrate/.zshrc" <<'LEGACY'
# Corporate user profile
# Personal SSH aliases (must survive)
tmux attach

# >>> Ghostty Hack-Jitsu Edition >>>
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/shell.zsh" ]; then
  source "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/shell.zsh"
fi
# <<< Ghostty Hack-Jitsu Edition <<<

alias work='echo work'
LEGACY
HOME="$migrate" XDG_CONFIG_HOME="$migrate/.config" XDG_STATE_HOME="$migrate/.local/state" \
  bash "$ROOT/install.sh" --no-quit --no-brew --no-shell >"$TMP/migrate.log"
grep -Fq 'tmux attach' "$migrate/.zshrc"
grep -Fq "alias work=" "$migrate/.zshrc"
if grep -Fq '# >>> Ghostty Hack-Jitsu Edition >>>' "$migrate/.zshrc"; then
  echo "Old Hack-Jitsu integration was not removed" >&2; exit 1
fi
grep -Fq 'MIGRATED old Hack-Jitsu ~/.zshrc block' "$TMP/migrate.log"
find "$migrate/.local/state/ghostty-hackjitsu/backups" -name zshrc-before-hackjitsu-migration | grep -q .
HOME="$migrate" XDG_CONFIG_HOME="$migrate/.config" XDG_STATE_HOME="$migrate/.local/state" \
  bash "$ROOT/install.sh" --no-quit --no-brew --no-shell >"$TMP/migrate-again.log"
grep -Fq 'tmux attach' "$migrate/.zshrc"
echo "PASS: dry run, install, backup, idempotency, symlink refusal, LazyVim preservation and opt-out"
