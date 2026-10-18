#!/usr/bin/env bash
# Finder-visible branded launcher for external Hack-Jitsu installs.
# Ghostty's own signed bundle is NEVER patched: macos-icon=custom only changes
# its Dock/runtime icon, whereas modifying Finder's app icon breaks signing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/ghostty/hack-jitsu-red-icon.png"
OUT_DIR="${HJ_BRANDED_APP_DIR:-$HOME/Applications}"
TARGET="$OUT_DIR/Hack-Jitsu Ghostty.app"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
MARKER='.hackjitsu-managed-launcher'
MODE="${1:-install}"
say() { printf '%s\n' "$*"; }

case "$MODE" in install|--check|--dry-run) ;; *) echo '[FAIL] Usage: install-app-launcher.sh [--check|--dry-run]' >&2; exit 2;; esac
if [[ "$(uname -s)" != Darwin ]]; then
  say '[WARN] Finder launcher is supported only on macOS.'
  exit 0
fi

APP="${HJ_GHOSTTY_APP_PATH:-}"
if [[ -z "$APP" ]]; then
  for candidate in "$HOME/Applications/Ghostty.app" /Applications/Ghostty.app; do
    if [[ -x "$candidate/Contents/MacOS/ghostty" ]]; then
      APP="$candidate"
      break
    fi
  done
fi
if [[ -z "$APP" || ! -x "$APP/Contents/MacOS/ghostty" ]]; then
  say '[WARN] Ghostty.app not found; cannot create branded Finder launcher.'
  [[ "$MODE" != --check ]]
  exit $?
fi

managed_target() {
  [[ -d "$TARGET" && ! -L "$TARGET" &&
     -f "$TARGET/Contents/Resources/$MARKER" &&
     -f "$TARGET/Contents/Info.plist" &&
     -x "$TARGET/Contents/MacOS/applet" ]] &&
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null)" == com.hackjitsu.ghostty.launcher ]] &&
  /usr/bin/codesign --verify --deep --strict "$TARGET" >/dev/null 2>&1
}
valid_target() {
  managed_target &&
  [[ -f "$TARGET/Contents/Resources/applet.icns" &&
     ! -e "$TARGET/Contents/Resources/Assets.car" ]] &&
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$TARGET/Contents/Info.plist" 2>/dev/null)" == applet ]]
}
if [[ "$MODE" == --check ]]; then
  if valid_target; then
    say "[PASS] Signed Hack-Jitsu Ghostty Finder launcher: $TARGET"
    say "[INFO] Original signed Ghostty untouched: $APP"
  else
    say "[WARN] Branded Finder launcher missing or invalid: $TARGET"
    exit 1
  fi
  exit 0
fi
if [[ "$MODE" == --dry-run ]]; then
  say "[PLAN] Create/update red Finder launcher: $TARGET"
  say "[PLAN] Original signed Ghostty remains untouched: $APP"
  exit 0
fi

[[ -f "$SOURCE" && ! -L "$SOURCE" ]] || { say "[FAIL] Missing red icon: $SOURCE" >&2; exit 2; }
for tool in /usr/bin/sips /usr/bin/iconutil /usr/bin/osacompile /usr/bin/codesign /usr/libexec/PlistBuddy; do
  [[ -x "$tool" ]] || { say "[WARN] Missing macOS icon builder: $tool"; exit 0; }
done
if [[ -e "$TARGET" || -L "$TARGET" ]] && ! managed_target; then
  say "[WARN] Unrecognized existing launcher preserved: $TARGET"
  exit 0
fi
[[ ! -L "$OUT_DIR" ]] || { say "[WARN] Refusing symlinked applications folder: $OUT_DIR"; exit 0; }
mkdir -p "$OUT_DIR"
TMP="$(mktemp -d "$OUT_DIR/.hj-launcher.XXXXXXXX")"
BACKUP=''
DONE=0
cleanup() {
  local rc=$?
  if (( ! DONE )) && [[ -n "$BACKUP" && -d "$BACKUP" && ! -e "$TARGET" ]]; then
    mv "$BACKUP" "$TARGET" || true
  fi
  rm -rf "$TMP"
  return "$rc"
}
trap cleanup EXIT

iconset="$TMP/HackJitsu.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  /usr/bin/sips -s format png -z "$size" "$size" "$SOURCE" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  /usr/bin/sips -s format png -z "$double" "$double" "$SOURCE" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$TMP/HackJitsu.icns"
NEW="$TMP/Hack-Jitsu Ghostty.app"
if ! /usr/bin/osacompile -o "$NEW" -e 'do shell script "/usr/bin/open -a Ghostty"' >"$TMP/compile.log" 2>&1; then
  say '[WARN] Failed to build Finder launcher; original Ghostty unchanged.' >&2
  tail -n 4 "$TMP/compile.log" >&2
  exit 0
fi
# AppleScript apps include *both* applet.icns and an Assets.car icon catalog.
# On macOS 26 the catalog wins over CFBundleIconFile, making the Finder icon
# GREY even with a red HackJitsu.icns resource! Apple DTS recommends replacing
# applet.icns AND removing Assets.car, then signing the resulting bundle.
cp "$TMP/HackJitsu.icns" "$NEW/Contents/Resources/applet.icns"
rm -f "$NEW/Contents/Resources/Assets.car"
printf '%s\n' 'hack-jitsu-ghostty-launcher/v2' > "$NEW/Contents/Resources/$MARKER"
plist="$NEW/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile applet' "$plist"
if ! /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.hackjitsu.ghostty.launcher' "$plist" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.hackjitsu.ghostty.launcher' "$plist"
fi
if ! /usr/libexec/PlistBuddy -c 'Set :CFBundleName Hack-Jitsu Ghostty' "$plist" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c 'Add :CFBundleName string Hack-Jitsu Ghostty' "$plist"
fi
if ! /usr/libexec/PlistBuddy -c 'Set :LSUIElement true' "$plist" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$plist"
fi
/usr/bin/codesign --force --deep --sign - "$NEW" >/dev/null 2>&1
/usr/bin/codesign --verify --deep --strict "$NEW" >/dev/null 2>&1 || {
  say '[WARN] Generated launcher signature is invalid; leaving original app untouched.' >&2
  exit 0
}

if valid_target && cmp -s "$TMP/HackJitsu.icns" "$TARGET/Contents/Resources/applet.icns"; then
  say "[PASS] Branded Finder launcher already current: $TARGET"
  DONE=1
  exit 0
fi
if [[ -d "$TARGET" ]]; then
  mkdir -p "$STATE_HOME/ghostty-hackjitsu/backups"
  backupbase="$(mktemp -d "$STATE_HOME/ghostty-hackjitsu/backups/launcher-XXXXXXXX")"
  BACKUP="$backupbase/Hack-Jitsu Ghostty.app"
  mv "$TARGET" "$BACKUP"
fi
mv "$NEW" "$TARGET"
DONE=1
say "[PASS] Red Hack-Jitsu Finder launcher installed: $TARGET"
say "[INFO] Ghostty.app is not modified: $APP"
say '[INFO] Open Hack-Jitsu Ghostty.app, then press Option+Tab for the dropdown.'
