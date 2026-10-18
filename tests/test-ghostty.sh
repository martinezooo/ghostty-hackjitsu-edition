#!/usr/bin/env bash
# Validate Ghostty Hack-Jitsu assets without touching live macOS preferences.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]; then
  GHOSTTY=/Applications/Ghostty.app/Contents/MacOS/ghostty
elif command -v ghostty >/dev/null 2>&1; then
  GHOSTTY="$(command -v ghostty)"
else
  echo "SKIP: Ghostty not installed (run installer first)"
  exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.config"
cp -R "$ROOT/ghostty" "$TMP/.config/ghostty"
export HOME="$TMP"
export XDG_CONFIG_HOME="$TMP/.config"
"$GHOSTTY" +validate-config
output="$("$GHOSTTY" +show-config)"
grep -Fq 'theme = hack-jitsu' <<< "$output"
grep -Fq 'font-family = JetBrainsMono Nerd Font Mono' <<< "$output"
grep -Fq 'quick-terminal-size = 55%,55%' <<< "$output"
grep -Fq 'hack-jitsu-cursor.glsl' <<< "$output"
grep -Fq 'hack-jitsu-watermark.png' <<< "$output"
grep -Eq 'alt\+tab=toggle_quick_terminal' <<< "$("$GHOSTTY" +list-keybinds)"
if grep -Fq 'JetBrainsMono Nerd Font Mono' <<< "$("$GHOSTTY" +list-fonts)"; then
  face="$("$GHOSTTY" +show-face --cp=65)"
  if ! grep -Fq 'JetBrainsMono Nerd Font Mono' <<< "$face"; then
    echo "FAIL: Nerd Font configured but Ghostty falls back to another face: $face" >&2
    exit 1
  fi
  echo "PASS: font resolves to JetBrainsMono Nerd Font Mono"
else
  echo "SKIP: Nerd Font is not installed, cannot test actual font rendering"
fi
echo "PASS: Ghostty config, theme, shader, watermark, dropdown binding"
