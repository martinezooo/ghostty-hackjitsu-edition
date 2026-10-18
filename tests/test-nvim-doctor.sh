#!/usr/bin/env bash
# No real Neovim user profile, plugins or config are touched.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_DATA_HOME="$TMP/home/.local/share" XDG_STATE_HOME="$TMP/home/.local/state"
export XDG_CACHE_HOME="$TMP/home/.cache"
mkdir -p "$HOME" "$XDG_CONFIG_HOME/nvim" "$TMP/bin"
printf 'PRIVATE PERSONAL CONFIG\n' > "$XDG_CONFIG_HOME/nvim/init.lua"
printf 'NEVER REPLACE\n' > "$HOME/.zshrc"
printf 'test only\n' > "$TMP/sample.log"
export HJ_MOCK_NVIM_USAGE="$TMP/nvim-invocations.log"
cat > "$TMP/bin/nvim" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$HJ_MOCK_NVIM_USAGE"
case "$*" in
  *--version*) echo 'NVIM v0.11.5' ;;
  *--clean*)
    printf 'HJ_PATH_CONFIG=%s\nHJ_PATH_DATA=%s\nHJ_PATH_STATE=%s\nHJ_PATH_CACHE=%s\n' \
      "$XDG_CONFIG_HOME/nvim" "$XDG_DATA_HOME/nvim" "$XDG_STATE_HOME/nvim" "$XDG_CACHE_HOME/nvim"
    ;;
  *) echo 'Error during tree-sitter build: Failed to compile parser lua'
     echo 'cc: error: fake build broken for test'
     ;;
esac
MOCK
chmod +x "$TMP/bin/nvim"
export PATH="$TMP/bin:$PATH"
script="$ROOT/tools/nvim-doctor.sh"

# The headless read-only diagnostic sees *this* environment, not a clean
# checkout, and captures compiler messages even when Neovim exits with 0.
bash "$script" --file "$TMP/sample.log" > "$TMP/doctor-output.log"
grep -Fq 'Managed Hack-Jitsu: no' "$TMP/doctor-output.log"
grep -Fq 'Failed to compile parser lua' "$TMP/doctor-output.log"
grep -Fq 'Complete local log (0600):' "$TMP/doctor-output.log"
log="$(find "$XDG_STATE_HOME/ghostty-hackjitsu" -maxdepth 1 -name 'nvim-doctor.*' -type f | head -1)"
test -f "$log"
test "$(stat -f %Lp "$log" 2>/dev/null || stat -c %a "$log")" = 600
grep -Fq 'HJ_PATH_CONFIG=' "$log"
grep -Fq 'cc: error: fake build broken for test' "$log"
grep -Fq -- "-- $TMP/sample.log" "$HJ_MOCK_NVIM_USAGE"
grep -Fxq 'PRIVATE PERSONAL CONFIG' "$XDG_CONFIG_HOME/nvim/init.lua"
grep -Fxq 'NEVER REPLACE' "$HOME/.zshrc"

# Third-party Neovim configs must never be repaired by this tool.
if bash "$script" --repair > "$TMP/repair-denied.log" 2>&1; then
  echo 'Repair was offered for personal Neovim config' >&2; exit 1
fi
grep -Fq 'No repair performed' "$TMP/repair-denied.log"
grep -Fxq 'PRIVATE PERSONAL CONFIG' "$XDG_CONFIG_HOME/nvim/init.lua"

# No active Neovim configuration is NOT proof that any parser was fixed.
rm "$XDG_CONFIG_HOME/nvim/init.lua"
bash "$script" > "$TMP/missing.log"
grep -Fq 'This shell has no Neovim init.lua' "$TMP/missing.log"
grep -Fq 'no parser build failure' "$TMP/missing.log" || true
grep -Fxq 'NEVER REPLACE' "$HOME/.zshrc"

# Installed helper and Zsh dispatch work with no extra user setup.
bash "$ROOT/install.sh" --no-quit --no-brew --no-nvim --no-shell > "$TMP/install.log"
test -r "$XDG_CONFIG_HOME/ghostty-hackjitsu/nvim-doctor.sh"
ZDOTDIR="$XDG_CONFIG_HOME/ghostty-hackjitsu/zsh" HJ_AUTO_ZELLIJ=0 \
  zsh -ic 'whence -w hjdoctor' >"$TMP/whence.log" 2>&1
grep -Fq 'hjdoctor: function' "$TMP/whence.log"

echo 'PASS: current-shell paths, exact Tree-sitter compiler error, private 0600 log, repair refusal and Zsh command'
