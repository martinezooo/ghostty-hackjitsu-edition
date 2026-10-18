#!/usr/bin/env bash
# Real macOS integration, isolated to a temporary HOME. No real Ghostty restart.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/hj-launcher-regression.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_STATE_HOME="$TMP/home/.local/state"
export HJ_BRANDED_APP_DIR="$TMP/home/Applications"
mkdir -p "$HOME"
HELPER="$ROOT/tools/install-app-launcher.sh"
DEST="$HJ_BRANDED_APP_DIR/Hack-Jitsu Ghostty.app"
ORIGINAL=/Applications/Ghostty.app
if [[ ! -x "$ORIGINAL/Contents/MacOS/ghostty" ]]; then
  echo 'SKIP: macOS Ghostty.app unavailable for signed-app tests'
  exit 0
fi

# A dry-run and check may not mutate the directory.
bash "$HELPER" --dry-run >"$TMP/dry.log"
test ! -e "$DEST"
if bash "$HELPER" --check >"$TMP/initial-check.log" 2>&1; then
  echo 'Missing branded launcher was incorrectly reported as healthy' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$ORIGINAL" >/dev/null

# The actual macOS native icon composer and codesigner are exercised.
bash "$HELPER" >"$TMP/install.log"
test -d "$DEST"
test -f "$DEST/Contents/Resources/applet.icns"
test -f "$DEST/Contents/Resources/.hackjitsu-managed-launcher"
test -x "$DEST/Contents/MacOS/applet"
test -s "$DEST/Contents/Resources/applet.icns"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$DEST/Contents/Info.plist")" = applet
test ! -e "$DEST/Contents/Resources/Assets.car"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")" = com.hackjitsu.ghostty.launcher
/usr/bin/codesign --verify --deep --strict "$DEST" >/dev/null
/usr/bin/codesign --verify --deep --strict "$ORIGINAL" >/dev/null
# On macOS 26 the compiled applet Assets.car can secretly override ICNS
# and show a grey icon. Verify the *actual* Finder/AppKit-resolved image is
# red rather than trusting filenames or plist values alone.
if [[ -x /usr/bin/swift ]]; then
  cat > "$TMP/finder-icon.swift" <<'SWIFT'
import AppKit
import Foundation
let image = NSWorkspace.shared.icon(forFile: CommandLine.arguments[1])
guard let data = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data) else { fatalError("No Finder icon data") }
var red = 0
var blue = 0
for y in Swift.stride(from: 0, to: bitmap.pixelsHigh, by: 16) {
  for x in Swift.stride(from: 0, to: bitmap.pixelsWide, by: 16) {
    guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
          pixel.alphaComponent > 0.4 else { continue }
    let r = pixel.redComponent, g = pixel.greenComponent, b = pixel.blueComponent
    if r > g * 1.4 && r > b * 1.2 && r > 0.25 { red += 1 }
    if b > r * 1.4 && b > g * 1.15 && b > 0.25 { blue += 1 }
  }
}
print("Finder actual icon: red=\(red), blue=\(blue)")
if red < 100 || red <= blue * 2 { exit(13) }
if let corner = bitmap.colorAt(x: 0, y: 0), corner.alphaComponent > 0.15 {
  print("Opaque frame detected at Finder icon corner")
  exit(14)
}
SWIFT
  /usr/bin/swift "$TMP/finder-icon.swift" "$DEST" >"$TMP/finder-render.log"
  grep -Fq 'Finder actual icon: red=' "$TMP/finder-render.log"
fi
bash "$HELPER" --check >"$TMP/healthy-check.log"
grep -Fq '[PASS] Signed Hack-Jitsu Ghostty Finder launcher:' "$TMP/healthy-check.log"
test "$(find "$HJ_BRANDED_APP_DIR" -maxdepth 1 -name '*.app' | wc -l | tr -d ' ')" = 1

# A subsequent install is idempotent, no duplicate app or backup churn.
before="$(/usr/bin/shasum -a 256 "$DEST/Contents/Resources/applet.icns" | cut -d ' ' -f1)"
bash "$HELPER" >"$TMP/reinstall.log"
grep -Fq 'already current' "$TMP/reinstall.log"
after="$(/usr/bin/shasum -a 256 "$DEST/Contents/Resources/applet.icns" | cut -d ' ' -f1)"
test "$before" = "$after"

# An unrelated application using the same pathname must not be destroyed.
mv "$DEST" "$TMP/managed-original.app"
mkdir -p "$DEST/Contents"
printf 'PERSONAL CONTENT\n' > "$DEST/Contents/custom"
bash "$HELPER" >"$TMP/foreign.log"
grep -Fq 'Unrecognized existing launcher preserved' "$TMP/foreign.log"
grep -Fxq 'PERSONAL CONTENT' "$DEST/Contents/custom"
rm -rf "$DEST"
mv "$TMP/managed-original.app" "$DEST"

# Full installer in an external, isolated user HOME provisions both runtime
# Ghostty icon and Finder-branded launcher; no app launched or killed.
bash "$ROOT/install.sh" --no-brew --no-nvim --no-quit >"$TMP/full-install.log"
grep -Fq 'macos-icon = custom' "$XDG_CONFIG_HOME/ghostty/config"
grep -Fq 'macos-custom-icon =' "$XDG_CONFIG_HOME/ghostty/config"
grep -Fq 'Branded Finder launcher already current' "$TMP/full-install.log"
test -f "$XDG_CONFIG_HOME/ghostty-hackjitsu/ui.conf"
test -f "$XDG_CONFIG_HOME/ghostty/hack-jitsu-red-icon.png"
test -d "$DEST"
/usr/bin/codesign --verify --deep --strict "$ORIGINAL" >/dev/null
echo 'PASS: external macOS install creates red signed Finder launcher without modifying Ghostty.app'
