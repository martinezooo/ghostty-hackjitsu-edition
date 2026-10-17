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
      printf '#!/bin/sh\nexit 0\n' > "$HJ_TEST_BIN/tree-sitter"
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
  +show-config) printf '%s\n' 'theme = hack-jitsu' \
    'font-family = JetBrainsMono Nerd Font Mono' \
    'quick-terminal-size = 400px,1728px' \
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
for name in fzf zellij; do
  printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/$name"
done
chmod +x "$TMP/bin"/*
export HJ_TEST_PREFIX="$TMP/prefix"
export HJ_TEST_BIN="$TMP/bin"
export HJ_TEST_READY="$TMP/tree-sitter.installed"
: > "$HJ_TEST_BREW_LOG"
bash "$ROOT/install.sh" --no-nvim --no-shell >"$TMP/first.log"
test ! -s "$HJ_TEST_BREW_LOG"
grep -Fq 'SKIP ghostty:' "$TMP/first.log"
grep -Fq 'SKIP font-jetbrains-mono-nerd-font:' "$TMP/first.log"
grep -Fq 'SKIP navi:' "$TMP/first.log"
grep -q 'Summary: .* 0 FAIL' "$TMP/first.log"
bash "$ROOT/install.sh" --no-nvim --no-shell >"$TMP/second.log"
test ! -s "$HJ_TEST_BREW_LOG"
grep -Fq 'OK unchanged:' "$TMP/second.log"
# "Check" never calls Homebrew install even when a file is missing.
rm "$XDG_CONFIG_HOME/ghostty/themes/hack-jitsu"
if bash "$ROOT/install.sh" --check --no-nvim --no-shell >"$TMP/check.log" 2>&1; then
  echo 'Expected failed check for missing theme' >&2; exit 1
fi
test ! -s "$HJ_TEST_BREW_LOG"
grep -Fq '[FAIL] Ghostty asset: themes/hack-jitsu' "$TMP/check.log"
# A missing CLI component is installed once, without sudo on the mock staff account.
export HJ_TEST_MISSING=tree-sitter-cli
bash "$ROOT/install.sh" --no-shell >"$TMP/missing-installed.log"
grep -Fq 'install tree-sitter-cli (no_sudo=1)' "$HJ_TEST_BREW_LOG"
grep -Fq 'SKIP ghostty:' "$TMP/missing-installed.log"
bash "$ROOT/install.sh" --no-shell >"$TMP/missing-second.log"
test "$(wc -l < "$HJ_TEST_BREW_LOG" | tr -d ' ')" -eq 1
grep -Fq 'SKIP tree-sitter-cli:' "$TMP/missing-second.log"
echo 'PASS: existing packages skipped, one missing tool installed once without sudo, diagnostic read-only'
