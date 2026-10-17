#!/usr/bin/env bash
# Optional live LazyVim smoke test. Requires Neovim, tree-sitter CLI, and network access.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v nvim >/dev/null 2>&1 || ! command -v tree-sitter >/dev/null 2>&1; then
  echo "SKIP: install Neovim and tree-sitter-cli first (./install.sh)"
  exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/config"
cp -R "$ROOT/nvim" "$TMP/config/nvim"
export XDG_CONFIG_HOME="$TMP/config"
export XDG_DATA_HOME="$TMP/data"
export XDG_CACHE_HOME="$TMP/cache"
export XDG_STATE_HOME="$TMP/state"
if ! nvim --headless '+Lazy! sync' '+qa!' >"$TMP/first-launch.log" 2>&1; then
  echo "FAIL: initial LazyVim sync exited with an error" >&2
  tail -n 25 "$TMP/first-launch.log" >&2
  exit 1
fi
# Some plugin errors do not affect Neovim's exit code.
if grep -Eq 'Error detected|Failed to run .config.|E5108|FATAL' "$TMP/first-launch.log"; then
  echo "FAIL: LazyVim logged a plugin startup error" >&2
  grep -E -A 10 'Error detected|Failed to run .config.|E5108|FATAL' "$TMP/first-launch.log" | head -n 30 >&2
  exit 1
fi
test -d "$TMP/data/nvim/lazy/LazyVim"
if ! nvim --headless -c 'lua print("HJ_LAZY_SETUP_OK=" .. tostring(require("lazy") ~= nil))' -c 'qa!' >"$TMP/second-launch.log" 2>&1; then
  echo "FAIL: second LazyVim startup" >&2
  cat "$TMP/second-launch.log" >&2
  exit 1
fi
grep -Fq 'HJ_LAZY_SETUP_OK=true' "$TMP/second-launch.log"
echo "PASS: LazyVim downloaded plugins and restarted without startup errors"
