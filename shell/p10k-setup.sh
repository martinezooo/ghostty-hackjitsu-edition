#!/usr/bin/env bash
# Run ORIGINAL Powerlevel10k preview wizard in a disposable ZDOTDIR.
# Never modify ~/.zshrc, ~/.p10k.zsh, or the installed isolated startup.
set -euo pipefail
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
DEST="$CONFIG_HOME/ghostty-hackjitsu/zsh"
if [[ "${1:-}" == --help ]]; then
  echo 'hjp10k: original Powerlevel10k wizard, isolated to Hack-Jitsu.'
  exit 0
fi
if [[ ! -t 0 || ! -t 1 ]]; then
  echo 'Powerlevel10k wizard requires an interactive terminal.' >&2
  exit 2
fi
theme=''
for path in /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme \
            /usr/local/share/powerlevel10k/powerlevel10k.zsh-theme; do
  if [[ -r "$path" ]]; then theme="$path"; break; fi
done
if [[ -z "$theme" ]] && command -v brew >/dev/null 2>&1; then
  bp="$(brew --prefix powerlevel10k 2>/dev/null || true)"
  if [[ -r "$bp/share/powerlevel10k/powerlevel10k.zsh-theme" ]]; then
    theme="$bp/share/powerlevel10k/powerlevel10k.zsh-theme"
  fi
fi
if [[ -z "$theme" ]]; then
  echo 'Powerlevel10k missing. Install: brew install powerlevel10k' >&2
  exit 2
fi
[[ -f "$DEST/.zshrc" && ! -L "$DEST/.zshrc" ]] || {
  echo "Missing isolated Hack-Jitsu Zsh profile, run install.sh first" >&2
  exit 2
}
mkdir -p -m 700 "$STATE_HOME/ghostty-hackjitsu"
tmp="$(mktemp -d "$STATE_HOME/ghostty-hackjitsu/p10k-wizard.XXXXXXXX")"
trap 'rm -rf "$tmp"' EXIT
printf 'source %q\n' "$theme" > "$tmp/.zshrc"
chmod 600 "$tmp/.zshrc"
echo 'Powerlevel10k wizard — configure Hack-Jitsu prompt only.'
echo 'Your personal ~/.zshrc and ~/.p10k.zsh will NOT be changed.'
ZDOTDIR="$tmp" HJ_AUTO_ZELLIJ=0 POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true \
  zsh -fic 'source "$ZDOTDIR/.zshrc"; p10k configure'
config="$tmp/.p10k.zsh"
if [[ ! -s "$config" ]]; then
  echo 'Powerlevel10k wizard cancelled; previous prompt preserved.'
  exit 0
fi
destination="$DEST/.p10k.zsh"
if [[ -L "$destination" || -L "$DEST/enable-p10k" ]]; then
  echo 'Refusing symlinked Powerlevel10k files.' >&2; exit 2
fi
if [[ -f "$destination" ]]; then
  backup="$STATE_HOME/ghostty-hackjitsu/backups/$(date +%Y%m%d-%H%M%S)-p10k"
  mkdir -p -m 700 "$backup"
  cp -p "$destination" "$backup/.p10k.zsh"
fi
install -m 600 "$config" "$destination"
( umask 077; : > "$DEST/enable-p10k" )
echo '[PASS] Powerlevel10k prompt stored inside Hack-Jitsu.'
echo 'Rerun later with: hjp10k'
