#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export HJ_GHOSTTY_BINARY="$TMP/bin/ghostty"
mkdir -p "$TMP/bin" "$HOME"
export PATH="$TMP/bin:$PATH"

cat > "$TMP/bin/brew" <<'EOF'
#!/bin/sh
case "$1" in
  list|install) exit 0 ;;
  *) exit 1 ;;
esac
EOF
cat > "$TMP/bin/ghostty" <<'EOF'
#!/bin/sh
case "$1" in
  +validate-config) exit 0 ;;
  +show-config)
    printf '%s\n' 'macos-hidden = always' \
      'initial-window = false' \
      'window-save-state = never' \
      'theme = hack-jitsu' \
      'macos-icon = custom' \
      'macos-custom-icon = /fixture/hack-jitsu-red-icon.png' \
      'font-family = JetBrainsMono Nerd Font Mono' \
      'quick-terminal-size = 55%,85%' \
      'command = /bin/sh -c ZDOTDIR=somewhere' \
      'custom-shader = shaders/hack-jitsu-cursor.glsl' \
      'background-image = hack-jitsu-watermark.png'
    ;;
  +list-keybinds) echo 'keybind = alt+tab=toggle_quick_terminal' ;;
  +list-fonts) echo 'JetBrainsMono Nerd Font Mono' ;;
  +show-face) echo 'U+41 found in face “JetBrainsMono Nerd Font Mono”.' ;;
  *) exit 1 ;;
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

bash "$ROOT/install.sh" --no-quit --no-brew --no-shell --no-nvim >"$TMP/config-only.log"
bash "$ROOT/install.sh" --no-quit --check --no-nvim --no-shell >"$TMP/pass.log"
grep -Fq '[PASS] Navi reads Hack-Jitsu cheats' "$TMP/pass.log"
grep -Eq 'Summary: [0-9]+ PASS \| 0 WARN \| 0 FAIL' "$TMP/pass.log"

# Full installer invokes doctor automatically after the package stage.
bash "$ROOT/install.sh" --no-quit --no-nvim --no-shell >"$TMP/automatic.log"
grep -Fq '=== Installation verification ===' "$TMP/automatic.log"
grep -Fq 'HACK-JITSU EDITION | SETUP FINISHED' "$TMP/automatic.log"
grep -Fq 'Press Option (Alt) + Tab' "$TMP/automatic.log"
grep -Eq 'Summary: [0-9]+ PASS \| 0 WARN \| 0 FAIL' "$TMP/automatic.log"

# Missing file must be a failing diagnosis, not a false success.
mv "$XDG_CONFIG_HOME/ghostty-hackjitsu/cheats/network.cheat" "$TMP/network.cheat"
if bash "$ROOT/install.sh" --no-quit --check --no-nvim --no-shell >"$TMP/fail.log" 2>&1; then
  echo "Expected doctor to fail when cheats are missing" >&2
  exit 1
fi
grep -Fq '[FAIL] Cheat sheet: network' "$TMP/fail.log"
mv "$TMP/network.cheat" "$XDG_CONFIG_HOME/ghostty-hackjitsu/cheats/network.cheat"

# Warnings are informational unless explicitly made strict.
legacy="$HOME/Library/Application Support/com.mitchellh.ghostty"
mkdir -p "$legacy"
echo 'window-padding-x = 1' > "$legacy/config.ghostty"
bash "$ROOT/install.sh" --no-quit --check --no-nvim --no-shell >"$TMP/warn.log"
grep -Fq '[WARN] Additional Ghostty config exists' "$TMP/warn.log"
if bash "$ROOT/install.sh" --no-quit --check --no-nvim --no-shell --strict >"$TMP/strict.log" 2>&1; then
  echo "Expected strict doctor to fail when warnings exist" >&2
  exit 1
fi
# CI log stays plain; forced ANSI mode is test-only.
HJ_INSTALL_COLOR=always bash "$ROOT/install.sh" --no-quit --check --no-nvim --no-shell >"$TMP/color-pass-warn.log"
grep -Fq $'\033[1;32m[PASS]\033[0m' "$TMP/color-pass-warn.log"
grep -Fq $'\033[1;33m[WARN]\033[0m' "$TMP/color-pass-warn.log"
NO_COLOR=1 HJ_INSTALL_COLOR=always bash "$ROOT/install.sh" --no-quit --check --no-nvim --no-shell >"$TMP/no-color.log"
if grep -Fq $'\033' "$TMP/no-color.log"; then
  echo 'NO_COLOR was ignored' >&2; exit 1
fi
mv "$XDG_CONFIG_HOME/ghostty-hackjitsu/cheats/network.cheat" "$TMP/network.color.cheat"
if HJ_INSTALL_COLOR=always bash "$ROOT/install.sh" --no-quit --check --no-nvim --no-shell >"$TMP/color-fail.log" 2>&1; then
  echo 'Missing network cheat did not fail' >&2; exit 1
fi
grep -Fq $'\033[1;31m[FAIL]\033[0m' "$TMP/color-fail.log"
mv "$TMP/network.color.cheat" "$XDG_CONFIG_HOME/ghostty-hackjitsu/cheats/network.cheat"
echo "PASS: doctor healthy, automatic verification, missing file, colored statuses and strict warnings"
