#!/usr/bin/env bash
# Package detection tests with mocked Homebrew. Does not install system software.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export HJ_GHOSTTY_BINARY="$TMP/bin/ghostty"
export HJ_TEST_BREW_LOG="$TMP/brew.log"
mkdir -p "$TMP/bin" "$HOME" "$TMP/prefix"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/id" <<'EOF'
#!/bin/sh
if [ "$1" = '-Gn' ]; then echo staff; else /usr/bin/id "$@"; fi
EOF
cat > "$TMP/bin/brew" <<'EOF'
#!/bin/sh
case "$1" in
  --prefix) printf '%s\n' "$HJ_TEST_PREFIX"; exit 0 ;;
  list)
    if [ "${HJ_TEST_MISSING:-}" = tree-sitter-cli ] &&
       [ "$2" = --formula ] && [ "$3" = tree-sitter-cli ] &&
       [ ! -e "$HJ_TEST_READY" ]; then exit 1; fi
    exit 0 ;;
  install)
    printf '%s (no_sudo=%s)\n' "$*" "${HOMEBREW_NO_SUDO:-unset}" >> "$HJ_TEST_BREW_LOG"
    if [ "${2:-}" = tree-sitter-cli ]; then
      cat > "$HJ_TEST_BIN/tree-sitter" <<'TSCLI'
#!/bin/sh
if [ "$1" = --version ]; then
  if [ "${HJ_TEST_TS_OLD:-0}" = 1 ]; then
    echo 'tree-sitter 0.25.0'
  else
    echo 'tree-sitter 0.27.1'
  fi
fi
exit 0
TSCLI
      chmod +x "$HJ_TEST_BIN/tree-sitter"
      : > "$HJ_TEST_READY"
    fi
    exit 0 ;;
esac
exit 3
EOF
cat > "$TMP/bin/ghostty" <<'EOF'
#!/bin/sh
case "$1" in
  +validate-config) exit 0 ;;
  +show-config) printf '%s\n' 'macos-hidden = always' \
      'initial-window = false' \
      'window-save-state = never' \
      'theme = hack-jitsu' \
    'font-family = JetBrainsMono Nerd Font Mono' \
    'quick-terminal-size = 55%,85%' \
    'command = /bin/sh -c ZDOTDIR=somewhere' \
    'hack-jitsu-cursor.glsl' 'hack-jitsu-watermark.png';;
  +list-keybinds) echo 'keybind = alt+tab=toggle_quick_terminal';;
  +list-fonts) echo 'JetBrainsMono Nerd Font Mono';;
  +show-face) echo 'JetBrainsMono Nerd Font Mono';;
  *) exit 3 ;;
esac
EOF
cat > "$TMP/bin/navi" <<'EOF'
#!/bin/sh
echo 'git status --short --branch'
EOF
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/fzf"
cat > "$TMP/bin/zellij" <<'MOCK_ZELLIJ'
#!/bin/sh
if [ "$1" = --config ] && [ "$3" = setup ] && [ "$4" = --check ]; then
  echo '[CONFIG FILE]: Well defined.'
fi
exit 0
MOCK_ZELLIJ
chmod +x "$TMP/bin"/*
export HJ_TEST_PREFIX="$TMP/prefix"
export HJ_TEST_BIN="$TMP/bin"
export HJ_TEST_READY="$TMP/tree-sitter.installed"
: > "$HJ_TEST_BREW_LOG"
bash "$ROOT/install.sh" --no-quit --no-nvim --no-shell >"$TMP/first.log"
test ! -s "$HJ_TEST_BREW_LOG"
grep -Fq 'SKIP ghostty:' "$TMP/first.log"
grep -Fq 'SKIP font-jetbrains-mono-nerd-font:' "$TMP/first.log"
grep -Fq 'SKIP navi:' "$TMP/first.log"
grep -q 'Summary: .* 0 FAIL' "$TMP/first.log"
bash "$ROOT/install.sh" --no-quit --no-nvim --no-shell >"$TMP/second.log"
test ! -s "$HJ_TEST_BREW_LOG"
grep -Fq 'OK unchanged:' "$TMP/second.log"
# "Check" never calls Homebrew install even when a file is missing.
rm "$XDG_CONFIG_HOME/ghostty/themes/hack-jitsu"
if bash "$ROOT/install.sh" --no-quit --check --no-nvim --no-shell >"$TMP/check.log" 2>&1; then
  echo 'Expected failed check for missing theme' >&2; exit 1
fi
test ! -s "$HJ_TEST_BREW_LOG"
grep -Fq '[FAIL] Ghostty asset: themes/hack-jitsu' "$TMP/check.log"
# The test runs both on hosts with and without a globally installed CLI.
# When unavailable, the mock Brew installs it once; when available already,
# the installer must not reinstall it. Both paths preserve no-sudo behavior.
export HJ_TEST_MISSING=tree-sitter-cli
if command -v tree-sitter >/dev/null 2>&1; then
  expected_brew_installs=0
else
  expected_brew_installs=1
fi
bash "$ROOT/install.sh" --no-quit --no-shell --no-lazy-sync >"$TMP/missing-installed.log"
if [ "$expected_brew_installs" -eq 1 ]; then
  grep -Fq 'install tree-sitter-cli (no_sudo=1)' "$HJ_TEST_BREW_LOG"
fi
grep -Fq 'SKIP ghostty:' "$TMP/missing-installed.log"
bash "$ROOT/install.sh" --no-quit --no-shell --no-lazy-sync >"$TMP/missing-second.log"
test "$(wc -l < "$HJ_TEST_BREW_LOG" | tr -d ' ')" -eq "$expected_brew_installs"
grep -Fq 'SKIP tree-sitter-cli:' "$TMP/missing-second.log"
# First-run LazyVim sync must happen once, during installation, not on file open.
cat > "$TMP/bin/nvim" <<'MOCK_NVIM'
#!/bin/sh
printf '%s\n' "$*" >> "$HJ_TEST_NVIM_LOG"
case "$*" in
  *'+Lazy! sync'*) mkdir -p "$XDG_DATA_HOME/nvim/lazy/LazyVim" "$XDG_DATA_HOME/nvim/lazy/nvim-treesitter" ;;
esac
case "$*" in
  *'+luafile '*)
    if [ "${HJ_TEST_NVIM_FAIL:-0}" = 1 ]; then
      echo 'Failed to compile parser: fixture' >&2
      exit 0  # simulate the actual Neovim failure: exit 0 with printed error
    fi
    mkdir -p "$XDG_DATA_HOME/nvim/site/parser"
    touch "$XDG_DATA_HOME/nvim/site/parser/lua.so"
    if [ "${HJ_TS_BUILD_ONLY:-0}" = 1 ]; then
      echo 'HJ_NVIM_BOOTSTRAP_BUILT: compiled 23 parsers'
    elif [ "${HJ_TS_VERIFY_ONLY:-0}" = 1 ]; then
      echo 'HJ_NVIM_BOOTSTRAP_READY: verified 23 parsers in fresh Neovim process'
    else
      echo 'ERROR: missing verification phase' >&2
      exit 1
    fi
    ;;
esac
exit 0
MOCK_NVIM
chmod +x "$TMP/bin/nvim"
export HJ_TEST_NVIM_LOG="$TMP/nvim.log"
: > "$HJ_TEST_NVIM_LOG"
bash "$ROOT/install.sh" --no-quit --no-shell >"$TMP/lazy-initial.log"
grep -Fq 'Validating LazyVim parser compilation' "$TMP/lazy-initial.log"
if ! grep -Fq 'LazyVim parsers compiled and loaded in separate Neovim processes' "$TMP/lazy-initial.log"; then
  echo "FAIL: bootstrap reported no complete parser verification" >&2
  tail -n 32 "$TMP/lazy-initial.log" >&2
  echo "COMPILER_LOG + RELATED LINES:" >&2
  grep -Ei 'Validating Lazy|LazyVim|HJ_NVIM|parser|tree-sitter|nvim-bootstrap' "$TMP/lazy-initial.log" | tail -24 >&2 || true
  wc -c "$XDG_STATE_HOME/ghostty-hackjitsu/nvim-bootstrap.log" >&2 || true
  cat "$XDG_STATE_HOME/ghostty-hackjitsu/nvim-bootstrap.log" >&2 || true
  echo "NVIM_CALLS:" >&2
  cat "$HJ_TEST_NVIM_LOG" >&2
  exit 1
fi
test -f "$XDG_STATE_HOME/ghostty-hackjitsu/nvim-bootstrap.log"
test "$(stat -f %Lp "$XDG_STATE_HOME/ghostty-hackjitsu/nvim-bootstrap.log" 2>/dev/null || stat -c %a "$XDG_STATE_HOME/ghostty-hackjitsu/nvim-bootstrap.log")" = 600
test "$(grep -Fc -- '--headless +Lazy! sync' "$HJ_TEST_NVIM_LOG")" -eq 1
test "$(grep -Fc -- '--headless +luafile ' "$HJ_TEST_NVIM_LOG")" -ge 2
bash "$ROOT/install.sh" --no-quit --no-shell >"$TMP/lazy-repeat.log"
grep -Fq 'LazyVim parsers compiled and loaded in separate Neovim processes' "$TMP/lazy-repeat.log"
test "$(grep -Fc -- '--headless +Lazy! sync' "$HJ_TEST_NVIM_LOG")" -eq 1
test "$(grep -Fc -- '--headless +luafile ' "$HJ_TEST_NVIM_LOG")" -ge 2
# Plugin sources can exist while parsers fail. A zero exit code from nvim
# MUST NOT trigger a false success message.
HJ_TEST_NVIM_FAIL=1 bash "$ROOT/install.sh" --no-quit --no-shell >"$TMP/lazy-failure.log" 2>&1
grep -Fq '[WARN] LazyVim is not fully ready' "$TMP/lazy-failure.log"
grep -Fq '[WARN] Neovim parser bootstrap incomplete' "$TMP/lazy-failure.log"
grep -Eq 'Summary: .* [1-9][0-9]* WARN ' "$TMP/lazy-failure.log"
grep -Fq 'Failed to compile parser: fixture' "$XDG_STATE_HOME/ghostty-hackjitsu/nvim-bootstrap.log"
grep -Fq 'Full diagnostic log:' "$TMP/lazy-failure.log"
! grep -Fq '[PASS] LazyVim parsers compiled' "$TMP/lazy-failure.log"
# Ensure the test can emulate an old CLI even when actual Homebrew CLI exists.
cat > "$TMP/bin/tree-sitter" <<'MOCK_OLD_TS'
#!/bin/sh
if [ "$1" = --version ]; then echo tree-sitter 0.25.0; fi
MOCK_OLD_TS
chmod +x "$TMP/bin/tree-sitter"
# Existing too-old CLI is a hard diagnostic failure, even if it is executable.
if bash "$ROOT/install.sh" --no-quit --check --no-shell >"$TMP/tree-old.log" 2>&1; then
  echo 'Old tree-sitter-cli was not rejected' >&2; exit 1
fi
grep -Fq '[FAIL] Tree-sitter CLI version unknown/too old' "$TMP/tree-old.log"
echo 'PASS: existing packages skipped, one missing tool installed once without sudo, diagnostic read-only'
