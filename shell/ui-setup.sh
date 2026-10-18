#!/usr/bin/env bash
# Isolated Hack-Jitsu first-run configurator (no private data in Git).
set -euo pipefail
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
HJ="$CONFIG_HOME/ghostty-hackjitsu"
PREF="$HJ/ui.conf"
TITLE="$(id -un)"
BAR=classic
OPTION=left
ACTION=wizard
usage() {
  cat <<'HELP'
hjsetup                          Interactive setup wizard
hjsetup --show                   Print current preferences
hjsetup --apply                  Re-render installed files after update
hjsetup --title USERNAME --bar classic|compact --option left|right|both|off
  Classic: full Zellij help; compact: one-line tab/status bar.
  Left Option is Alt in Zellij; right Option remains useful for Polish typing.
HELP
}
valid_title() { [[ -n "$TITLE" && ${#TITLE} -le 48 && "$TITLE" =~ ^[a-zA-Z0-9_.\ -]+$ ]]; }
validate() {
  valid_title || { echo "Invalid title (ASCII letters/digits/space/._-, max 48)." >&2; return 2; }
  case "$BAR" in classic|compact) ;; *) echo "Invalid bar: $BAR" >&2; return 2;; esac
  case "$OPTION" in left|right|both|off) ;; *) echo "Invalid Option mode: $OPTION" >&2; return 2;; esac
}
if [[ -e "$PREF" ]]; then
  [[ -f "$PREF" && ! -L "$PREF" ]] || { echo "Unsafe preference file: $PREF" >&2; exit 2; }
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    case "$key" in
      title) TITLE="$value";; bar) BAR="$value";; option) OPTION="$value";;
      ''|\#*) ;; *) echo "Unknown preference: $key" >&2; exit 2;;
    esac
  done < "$PREF"
fi
validate
case "${1:-}" in
  --help|-h) usage; exit 0;;
  --show)
    printf 'Title: %s\nBar: %s\nOption -> Alt: %s\n' "$TITLE" "$BAR" "$OPTION"
    exit 0;;
  --apply) ACTION=apply; shift;;
  --title|--bar|--option) ACTION=set;;
  '') ;;
  *) usage >&2; exit 2;;
esac
while (( $# )); do
  case "$1" in
    --title|--bar|--option)
      (( $# >= 2 )) || { echo "Missing value for $1" >&2; exit 2; }
      case "$1" in --title) TITLE="$2";; --bar) BAR="$2";; --option) OPTION="$2";; esac
      shift 2;;
    *) echo "Unexpected argument: $1" >&2; exit 2;;
  esac
done
ask() {
  local reply=""
  printf '%s [%s]: ' "$1" "$2" >&2
  IFS= read -r reply || true
  printf '%s' "${reply:-$2}"
}
if [[ "$ACTION" == wizard ]]; then
  [[ -t 0 ]] || { echo "TTY required; use --title/--bar/--option" >&2; exit 2; }
  echo "HACK-JITSU | Personal terminal setup"
  echo "Zellij shows Alt, which is Option (⌥) on Mac."
  TITLE="$(ask 'Window title' "$TITLE")"
  echo "Zellij bottom: [1] full shortcut help [2] compact single line"
  reply="$(ask 'Choose 1 or 2' "$([[ "$BAR" == compact ]] && echo 2 || echo 1)")"
  case "$reply" in 1) BAR=classic;;2) BAR=compact;;*) echo 'Invalid selection' >&2; exit 2;;esac
  echo "Mac keyboard: [1] left Option = Alt; right Option types Polish characters"
  echo "              [2] both Options = Alt; [3] Option behaves like macOS"
  reply="$(ask 'Choose 1, 2, 3' 1)"
  case "$reply" in 1) OPTION=left;;2) OPTION=both;;3) OPTION=off;;*) echo 'Invalid selection' >&2;exit 2;;esac
fi
validate
[[ -f "$HJ/ghostty-template.conf" && -f "$HJ/zellij/template.kdl" ]] || {
  echo "Missing bundled templates; run ./install.sh first." >&2; exit 2;
}
[[ ! -L "$HJ/ghostty-template.conf" && ! -L "$HJ/zellij/template.kdl" ]] || exit 2
[[ ! -L "$CONFIG_HOME/ghostty/config" && ! -L "$HJ/zellij/config.kdl" && ! -L "$PREF" ]] || {
  echo 'Refusing symlinked config or preferences' >&2; exit 2;
}
mkdir -p "$CONFIG_HOME/ghostty" "$HJ/zellij"
gt="$(mktemp "$CONFIG_HOME/ghostty/.hj-temp.XXXXXX")"
zt="$(mktemp "$HJ/zellij/.hj-temp.XXXXXX")"
pt="$(mktemp "$HJ/.hj-prefs.XXXXXX")"
trap 'rm -f "$gt" "$zt" "$pt"' EXIT
option_value="$OPTION"
[[ "$OPTION" == both ]] && option_value=true
[[ "$OPTION" == off ]] && option_value=false
{
  cat "$HJ/ghostty-template.conf"
  printf '\n# Generated locally by hjsetup. Do not commit account details.\n'
  printf 'title = %s\nmacos-option-as-alt = %s\n' "$TITLE" "$option_value"
} > "$gt"
layout=default
[[ "$BAR" == compact ]] && layout=compact
sed "s/^default_layout \"default\"$/default_layout \"$layout\"/" "$HJ/zellij/template.kdl" > "$zt"
grep -Fqx "default_layout \"$layout\"" "$zt" || { echo "Unexpected Zellij template" >&2;exit 2; }
if command -v zellij >/dev/null 2>&1; then
  zellij --config "$zt" setup --check | grep -Fq '[CONFIG FILE]: Well defined.' || {
    echo 'Zellij config validation failed' >&2; exit 2;
  }
fi
printf 'title=%s\nbar=%s\noption=%s\n' "$TITLE" "$BAR" "$OPTION" > "$pt"
copy_if_changed() {
  local from="$1" to="$2" name="$3" back
  [[ ! -L "$to" ]] || { echo "Refusing symlink: $to" >&2; return 2; }
  [[ ! -e "$to" || -f "$to" ]] || return 2
  if [[ -f "$to" ]] && cmp -s "$from" "$to"; then return 0; fi
  if [[ -f "$to" ]]; then
    back="$STATE_HOME/ghostty-hackjitsu/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$back"
    cp -p "$to" "$back/$name"
  fi
  chmod 600 "$from"
  mv "$from" "$to"
  echo "Updated: $to"
}
# Candidate configs are validated before any destination is modified.
copy_if_changed "$zt" "$HJ/zellij/config.kdl" zellij-ui
copy_if_changed "$gt" "$CONFIG_HOME/ghostty/config" ghostty-ui
if [[ "$ACTION" != apply ]]; then
  copy_if_changed "$pt" "$PREF" preferences
fi
echo "Title: $TITLE | Zellij bar: $BAR | Mac Option: $OPTION"
echo 'A new Zellij session is needed for the new bar layout. Existing sessions are not touched.'
