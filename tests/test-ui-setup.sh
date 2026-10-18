#!/usr/bin/env bash
# User-local UI preferences: no hard-coded identity and no changes to actual home.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_STATE_HOME="$TMP/home/.local/state"
mkdir -p "$HOME"
# No package installs, no running Ghostty instances touched.
bash "$ROOT/install.sh" --no-brew --no-quit --no-nvim >/dev/null
SETUP="$XDG_CONFIG_HOME/ghostty-hackjitsu/ui-setup.sh"
GC="$XDG_CONFIG_HOME/ghostty/config"
ZC="$XDG_CONFIG_HOME/ghostty-hackjitsu/zellij/config.kdl"
PREF="$XDG_CONFIG_HOME/ghostty-hackjitsu/ui.conf"
test -x "$SETUP" || test -r "$SETUP"
test ! -e "$PREF"
grep -Fqx "title = $(id -un)" "$GC"
grep -Fqx 'macos-option-as-alt = left' "$GC"
grep -Fqx 'default_layout "default"' "$ZC"
bash "$SETUP" --show | grep -Fq 'Bar: classic'
# The wizard should fail gracefully in non-interactive mode, without changes.
if bash "$SETUP" </dev/null >"$TMP/wizard.out" 2>&1; then
  echo 'Wizard must require a TTY' >&2
  exit 1
fi
test ! -e "$PREF"
# Programmatic wizard choices act exactly like interactive choices.
bash "$SETUP" --title 'analyst' --bar compact --option both >"$TMP/compact.out"
grep -Fqx 'title = analyst' "$GC"
grep -Fqx 'macos-option-as-alt = true' "$GC"
grep -Fqx 'default_layout "compact"' "$ZC"
grep -Fqx 'title=analyst' "$PREF"
grep -Fqx 'bar=compact' "$PREF"
grep -Fqx 'option=both' "$PREF"
test "$(stat -f %Lp "$PREF")" = "600" || test "$(stat -c %a "$PREF")" = "600"
bash "$SETUP" --show | grep -Fq 'Title: analyst'
# Check the configured layout against the real Zellij bundled layouts.
# A detached session has no UI client and does not instantiate status plugins,
# so list-panes would be misleading; native layout validation is authoritative.
if command -v zellij >/dev/null; then
  zellij --config "$ZC" setup --check | grep -Fq '[CONFIG FILE]: Well defined.'
  zellij setup --dump-layout compact | grep -Fq 'plugin location="compact-bar"'
  zellij setup --dump-layout default | grep -Fq 'plugin location="status-bar"'
fi
if [[ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]]; then
  /Applications/Ghostty.app/Contents/MacOS/ghostty +validate-config >/dev/null
  /Applications/Ghostty.app/Contents/MacOS/ghostty +show-config 2>/dev/null | grep -Fq 'title = analyst'
fi
# Identical choices do not write new backup files.
before="$(find "$XDG_STATE_HOME/ghostty-hackjitsu/backups" -type f | wc -l)"
bash "$SETUP" --apply >/dev/null
after="$(find "$XDG_STATE_HOME/ghostty-hackjitsu/backups" -type f | wc -l)"
test "$before" -eq "$after"
# Reinstall keeps choices and does not create backups just due to local footer.
bash "$ROOT/install.sh" --no-brew --no-quit --no-nvim >"$TMP/reinstall.log"
grep -Fqx 'title = analyst' "$GC"
grep -Fqx 'default_layout "compact"' "$ZC"
test "$(find "$XDG_STATE_HOME/ghostty-hackjitsu/backups" -type f | wc -l)" -eq "$after"
# Switch back to original username + normal bar, left Option for Polish input.
bash "$SETUP" --title "$(id -un)" --bar classic --option left >/dev/null
grep -Fqx 'default_layout "default"' "$ZC"
grep -Fqx 'macos-option-as-alt = left' "$GC"
# User-controlled title must not be used to inject Ghostty directives.
if bash "$SETUP" --title 'admin
theme = insecure' >/dev/null 2>&1; then
  echo 'Unsafe title injection accepted' >&2
  exit 1
fi
grep -Fqx "title = $(id -un)" "$GC"
# Symlink safety also extends to user prefs.
mv "$PREF" "$TMP/preferences-backup"
ln -s "$TMP/preferences-backup" "$PREF"
if bash "$SETUP" --apply >/dev/null 2>&1; then
  echo 'Preferences symlink was accepted' >&2
  exit 1
fi
test -L "$PREF"
# Shell integration is scoped to Hack-Jitsu, not ~/.zshrc.
ZDOTDIR="$XDG_CONFIG_HOME/ghostty-hackjitsu/zsh" TERM_PROGRAM=ghostty HJ_AUTO_ZELLIJ=0 zsh -ic '
  (( $+functions[hjsetup] )) || exit 13
  (( $+functions[hjkeys] )) || exit 14
  hjkeys
  hj
' >"$TMP/keys.log" 2>&1
grep -Fq 'Option = Alt' "$TMP/keys.log"
grep -Fq 'hjsetup            Configure title' "$TMP/keys.log"
grep -Fq 'Starts a new, clean session' "$TMP/keys.log"
echo 'PASS: username title, both Zellij status layouts, Mac Option mapping, stable reinstall and safe preferences'
