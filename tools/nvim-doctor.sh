#!/usr/bin/env bash
# Diagnose the *current shell's* Neovim. Never remove caches or user plugins.
# Run INSIDE the Ghostty pane that actually shows the Tree-sitter failure.
set -euo pipefail
MODE=diagnose
TARGET=''
usage() {
  cat <<'HELP'
Usage: hjdoctor nvim [--file path] [--repair]
       bash tools/nvim-doctor.sh [--file path] [--repair]
Run inside the affected Ghostty/Zellij shell.
--file path   Open that file read-only in a headless Neovim reproduction.
--repair      For Hack-Jitsu-managed LazyVim ONLY, compile/verify parsers.
Defaults to diagnostics only; never deletes caches or changes user dotfiles.
Full logs stay LOCAL in ~/.local/state/ghostty-hackjitsu/ (0600).
HELP
}
while (($#)); do
  case "$1" in
    --repair) MODE=repair; shift;;
    --file) (($# >= 2)) || { usage >&2; exit 2; }; TARGET="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2;;
  esac
done
if [[ -n "$TARGET" && ( ! -f "$TARGET" || ! -r "$TARGET" ) ]]; then
  echo "Not a readable file: $TARGET" >&2
  exit 2
fi
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
LOG_DIR="$STATE_HOME/ghostty-hackjitsu"
( umask 077; mkdir -p "$LOG_DIR" )
[[ ! -L "$LOG_DIR" ]] || { echo 'Refusing symlinked diagnostic directory' >&2; exit 2; }
LOG="$(umask 077; mktemp "$LOG_DIR/nvim-doctor.XXXXXXXX")"
chmod 600 "$LOG"
say() { printf '%s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }

# Neovim --clean ignores startup code but retains the SAME XDG/NVIM_APPNAME
# context as the failing shell. It is used only to resolve real stdpaths.
{
  echo '=== Ghostty Hack-Jitsu Neovim diagnostic (LOCAL ONLY) ==='
  date
  echo "mode=$MODE"
  printf 'TERM_PROGRAM=%s\nTERM=%s\n' "${TERM_PROGRAM:-unset}" "${TERM:-unset}"
  printf 'NVIM_APPNAME=%s\n' "${NVIM_APPNAME:-unset}"
  printf 'XDG_CONFIG_HOME=%s\n' "${XDG_CONFIG_HOME:-unset}"
  printf 'XDG_DATA_HOME=%s\n' "${XDG_DATA_HOME:-unset}"
  printf 'XDG_CACHE_HOME=%s\n' "${XDG_CACHE_HOME:-unset}"
  printf 'ZDOTDIR=%s\n' "${ZDOTDIR:-unset}"
  if has nvim; then
    command -v nvim
    nvim --version | head -4
  else echo 'NVIM_COMMAND_NOT_FOUND'; fi
  for binary in tree-sitter cc clang make git; do
    if has "$binary"; then
      printf '%s: %s\n' "$binary" "$(command -v "$binary")"
      "$binary" --version 2>&1 | head -1 || true
    else
      echo "MISSING: $binary"
    fi
  done
} >"$LOG" 2>&1
if ! has nvim; then
  say "FAIL: nvim unavailable. Diagnostic log: $LOG"
  exit 1
fi

PATHS="$(
  nvim --clean --headless -i NONE \
    -c 'lua for _,k in ipairs({"config","data","state","cache"}) do print("HJ_PATH_"..string.upper(k).."="..vim.fn.stdpath(k)) end' \
    -c 'qa!' 2>&1 | tr -d '\r'
)" || PATHS=''
printf '\n=== Effective Neovim paths ===\n%s\n' "$PATHS" >>"$LOG"
getpath() { printf '%s\n' "$PATHS" | sed -n "s/^HJ_PATH_$1=//p" | tail -1; }
CONFIG="$(getpath CONFIG)"
DATA="$(getpath DATA)"
NVIM_STATE="$(getpath STATE)"
if [[ -z "$CONFIG" || -z "$DATA" ]]; then
  say "FAIL: Could not resolve Neovim paths. Log: $LOG"
  exit 1
fi

MANAGED=0
if [[ -f "$CONFIG/init.lua" ]]; then
  if grep -Fq 'Portable LazyVim configuration for Ghostty Hack-Jitsu Edition' "$CONFIG/init.lua"; then
    MANAGED=1
  fi
else
  echo "NO_INIT_CONFIG: $CONFIG/init.lua" >>"$LOG"
fi
{
  echo
  echo '=== Config ownership and parsers ==='
  echo "active_init_present=$([[ -f "$CONFIG/init.lua" ]] && echo yes || echo no)"
  echo "hackjitsu_managed=$MANAGED"
  echo "init_path=$CONFIG/init.lua"
  echo "tree-sitter-cli=$({ tree-sitter --version 2>/dev/null || echo missing; } | head -1)"
  parser_dir="$DATA/site/parser"
  if [[ -d "$parser_dir" ]]; then
    find "$parser_dir" -maxdepth 1 -name '*.so' -type f -print | head -80
  else
    echo "NO_COMPILED_PARSERS_AT: $parser_dir"
  fi
} >>"$LOG" 2>&1

# Only an opt-in repair may change Tree-sitter parser files.
# Never repair a personal/non-Hack-Jitsu profile.
if [[ "$MODE" == repair ]]; then
  if [[ "$MANAGED" != 1 || ! -r "$CONFIG/lua/config/bootstrap.lua" ]]; then
    echo "REPAIR_REFUSED: active profile is not Hack-Jitsu-managed or bootstrap missing" >>"$LOG"
    say "WARN: No repair performed; active config is not managed Hack-Jitsu."
    say "Log: $LOG"
    exit 2
  fi
  {
    echo '=== Managed parser compilation/verification (user requested) ==='
    # Existing partially downloaded plugins may need a new Neovim process.
    if [[ ! -d "$DATA/lazy/nvim-treesitter" ]]; then
      nvim --headless -i NONE '+Lazy! sync' '+qa!'
    fi
    HJ_TS_BUILD_ONLY=1 nvim --headless -i NONE -c "luafile $CONFIG/lua/config/bootstrap.lua"
    HJ_TS_VERIFY_ONLY=1 nvim --headless -i NONE -c "luafile $CONFIG/lua/config/bootstrap.lua"
  } >>"$LOG" 2>&1 || {
    say "WARN: Managed parser repair failed; complete output: $LOG"
    grep -E -i 'failed to compile|tree-sitter build|error|HJ_NVIM' "$LOG" | tail -18 || true
    exit 1
  }
  if ! grep -Fq 'HJ_NVIM_BOOTSTRAP_READY:' "$LOG" ||
      grep -Eiq 'HJ_NVIM_BOOTSTRAP_FAILED|Failed to compile parser|ENOTEMPTY' "$LOG"; then
    say "WARN: Tree-sitter build/verification was incomplete. Log: $LOG"
    exit 1
  fi
  say "PASS: Parsers compiled and loaded in a fresh Neovim session."
fi

if [[ -f "$CONFIG/init.lua" ]]; then
  {
    echo
    echo '=== Read-only startup reproduction in the actual profile ==='
    if [[ -n "$TARGET" ]]; then
      echo "target=$TARGET"
      nvim --headless -R -i NONE \
        -c 'lua print("HJ_ACTIVE_CONFIG="..vim.fn.stdpath("config"))' \
        -c 'sleep 3' -c 'messages' -c 'qa!' -- "$TARGET"
    else
      nvim --headless -R -i NONE \
        -c 'lua print("HJ_ACTIVE_CONFIG="..vim.fn.stdpath("config"))' \
        -c 'sleep 3' -c 'messages' -c 'qa!'
    fi
  } >>"$LOG" 2>&1 || true
fi
{
  for previous in "$NVIM_STATE/log" "$STATE_HOME/ghostty-hackjitsu/nvim-bootstrap.log"; do
    if [[ -r "$previous" && ! -L "$previous" ]]; then
      echo "=== Previous diagnostics from $previous ==="
      tail -n 100 "$previous"
    fi
  done
} >>"$LOG" 2>&1
say "Neovim config: $CONFIG"
say "Managed Hack-Jitsu: $([[ "$MANAGED" = 1 ]] && echo yes || echo no)"
say "tree-sitter-cli: $(tree-sitter --version 2>/dev/null || echo missing)"
if [[ ! -f "$CONFIG/init.lua" ]]; then
  say "WARN: This shell has no Neovim init.lua; cannot reproduce a LazyVim build error here."
fi
if grep -Eiq 'Error during tree-sitter build|Failed to compile parser|HJ_NVIM_BOOTSTRAP_FAILED|error:.*(tree-sitter|parser)' "$LOG"; then
  say 'MATCHED BUILD ERROR (last lines):'
  grep -Ei -A 3 'Error during tree-sitter build|Failed to compile parser|HJ_NVIM_BOOTSTRAP_FAILED|error:.*(tree-sitter|parser)' "$LOG" | tail -23 || true
else
  say 'No parser build failure was captured in this diagnostic session.'
fi
say "Complete local log (0600): $LOG"
say 'This tool never uploads or deletes Neovim configurations, parsers or logs.'
