#!/usr/bin/env bash
# Optional live LazyVim smoke test. Requires Neovim, tree-sitter CLI, and network access.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v nvim >/dev/null 2>&1 || ! command -v tree-sitter >/dev/null 2>&1; then
  echo "SKIP: install Neovim and tree-sitter-cli first (./install.sh)"
  exit 0
fi
TMP="$(mktemp -d)"
cleanup() {
  # Recent nvim-treesitter runs compiler children asynchronously. A build can
  # write a cache entry during rm -rf and trigger "Directory not empty".
  # Retry bounded cleanup rather than turn a successful parser test into a
  # spurious test failure (or leave temporary parser caches behind).
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    rm -rf "$TMP" 2>/dev/null || true
    [[ ! -e "$TMP" ]] && return 0
    sleep 0.25
  done
  echo "FAIL: temporary LazyVim test cache still in use: $TMP" >&2
  return 1
}
trap cleanup EXIT
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
if grep -Eiq 'Error detected|Failed to run .config.|E5108|FATAL|Error during tree-sitter build|Failed to compile parser' "$TMP/first-launch.log"; then
  echo "FAIL: LazyVim logged a plugin startup error" >&2
  grep -Ei -A 10 'Error detected|Failed to run .config.|E5108|FATAL|Error during tree-sitter build|Failed to compile parser' "$TMP/first-launch.log" | head -n 30 >&2
  exit 1
fi
test -d "$TMP/data/nvim/lazy/LazyVim"
if ! nvim --headless -c 'lua print("HJ_LAZY_SETUP_OK=" .. tostring(require("lazy") ~= nil))' -c 'qa!' >"$TMP/second-launch.log" 2>&1; then
  echo "FAIL: second LazyVim startup" >&2
  cat "$TMP/second-launch.log" >&2
  exit 1
fi
grep -Fq 'HJ_LAZY_SETUP_OK=true' "$TMP/second-launch.log"
if grep -Eiq 'Error during tree-sitter build|Failed to compile parser|HJ_NVIM_BOOTSTRAP_FAILED' "$TMP/second-launch.log"; then
  echo "FAIL: Tree-sitter parser build error after restarting Neovim" >&2
  tail -n 35 "$TMP/second-launch.log" >&2
  exit 1
fi

# Normal file reading before bootstrap must NOT start background grammar
# downloads/compilations. LazyVim policy build=false, ensure_installed={}.
printf '{"tested":true}\n' >"$TMP/read-only.json"
if ! nvim --headless -R -i NONE -c 'sleep 1' -c 'qa!' -- "$TMP/read-only.json" >"$TMP/file-open.log" 2>&1; then
  echo "FAIL: Neovim could not open a JSON document" >&2
  tail -20 "$TMP/file-open.log" >&2
  exit 1
fi
if grep -Eiq 'Installing parser|Compiling parser|tree-sitter build|Failed to compile|ENOTEMPTY' "$TMP/file-open.log"; then
  echo "FAIL: Neovim opened a file and unexpectedly started parser compilation" >&2
  tail -30 "$TMP/file-open.log" >&2
  exit 1
fi
# A successful LazyVim download is not sufficient. Verify actual compilation
# and binary loading in two separate Neovim runtimes.
if ! HJ_TS_BUILD_ONLY=1 nvim --headless -c "luafile $TMP/config/nvim/lua/config/bootstrap.lua" >"$TMP/parser-build.log" 2>&1 ||
   ! grep -Fq 'HJ_NVIM_BOOTSTRAP_BUILT:' "$TMP/parser-build.log" ||
   grep -Eiq 'HJ_NVIM_BOOTSTRAP_FAILED|Failed to compile parser|Error during tree-sitter build|ENOTEMPTY' "$TMP/parser-build.log"; then
  echo "FAIL: Tree-sitter parser compiler stage failed" >&2
  tail -n 60 "$TMP/parser-build.log" >&2
  exit 1
fi
if ! HJ_TS_VERIFY_ONLY=1 nvim --headless -c "luafile $TMP/config/nvim/lua/config/bootstrap.lua" >"$TMP/parser-verify.log" 2>&1 ||
   ! grep -Fq 'HJ_NVIM_BOOTSTRAP_READY:' "$TMP/parser-verify.log" ||
   grep -Eiq 'HJ_NVIM_BOOTSTRAP_FAILED|Failed to compile parser|Error during tree-sitter build|ENOTEMPTY' "$TMP/parser-verify.log"; then
  echo "FAIL: Compiled Tree-sitter parsers cannot load in fresh Neovim" >&2
  tail -n 60 "$TMP/parser-verify.log" >&2
  exit 1
fi
echo "PASS: LazyVim synced, Neovim restarted, Tree-sitter parsers compiled and loaded"
