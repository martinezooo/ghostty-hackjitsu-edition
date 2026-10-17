#!/usr/bin/env bash
# Ghostty Hack-Jitsu Edition installer for macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
GHOSTTY_DEST="$CONFIG_HOME/ghostty"
HJ_DEST="$CONFIG_HOME/ghostty-hackjitsu"
BACKUP="$STATE_HOME/ghostty-hackjitsu/backups/$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
NO_BREW=0
NO_SHELL=0
TOOLS=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--no-brew] [--no-shell] [--tools]
  --dry-run   Show intended changes without writing or installing anything
  --no-brew   Install configuration only (skip Homebrew package installation)
  --no-shell  Do not add the optional shell integration to ~/.zshrc
  --tools     Also install nmap, jq, ripgrep, and yq for command-line work
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --no-brew) NO_BREW=1 ;;
    --no-shell) NO_SHELL=1 ;;
    --tools) TOOLS=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 2 ;;
  esac
done

if [ "$(uname -s)" != Darwin ]; then
  echo "Only macOS is supported." >&2
  exit 2
fi
if [ "$DRY_RUN" -eq 0 ] && [ "$NO_BREW" -eq 0 ] && ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is not installed. See https://brew.sh, or use --no-brew." >&2
  exit 2
fi

brew_formula() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "PLAN brew install $1"; return; fi
  if brew list --formula "$1" >/dev/null 2>&1; then echo "OK formula $1"; return; fi
  brew install "$1"
}
brew_cask() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "PLAN brew install --cask $1"; return; fi
  if brew list --cask "$1" >/dev/null 2>&1; then echo "OK cask $1"; return; fi
  brew install --cask "$1"
}

copy_asset() {
  local source="$1" dest="$2" label="$3"
  [ -f "$source" ] || { echo "Source missing: $source" >&2; exit 2; }
  if [ -L "$dest" ]; then echo "Refusing to replace symlink: $dest" >&2; exit 2; fi
  if [ -f "$dest" ] && cmp -s "$source" "$dest"; then
    echo "OK unchanged: $dest"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then echo "PLAN copy $source -> $dest"; return; fi
  if [ -e "$dest" ]; then
    mkdir -p "$BACKUP"
    cp -p "$dest" "$BACKUP/$label"
    echo "BACKUP $dest -> $BACKUP/$label"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -p "$source" "$dest"
  echo "COPY $dest"
}

if [ "$NO_BREW" -eq 0 ]; then
  brew_cask ghostty
  brew_cask font-jetbrains-mono-nerd-font
  brew_formula navi
  brew_formula fzf
  brew_formula zellij
  if [ "$TOOLS" -eq 1 ]; then
    for pkg in nmap jq ripgrep yq; do brew_formula "$pkg"; done
  fi
fi

copy_asset "$ROOT/ghostty/config" "$GHOSTTY_DEST/config" ghostty-config
copy_asset "$ROOT/ghostty/themes/hack-jitsu" "$GHOSTTY_DEST/themes/hack-jitsu" ghostty-theme
copy_asset "$ROOT/ghostty/shaders/hack-jitsu-cursor.glsl" "$GHOSTTY_DEST/shaders/hack-jitsu-cursor.glsl" ghostty-shader
copy_asset "$ROOT/ghostty/hack-jitsu-watermark.png" "$GHOSTTY_DEST/hack-jitsu-watermark.png" ghostty-watermark
copy_asset "$ROOT/shell/hj.zsh" "$HJ_DEST/shell.zsh" hj-shell

for file in "$ROOT"/cheats/*.cheat; do
  [ -f "$file" ] || continue
  copy_asset "$file" "$HJ_DEST/cheats/$(basename "$file")" "cheat-$(basename "$file")"
done

if [ "$NO_SHELL" -eq 0 ]; then
  RC="$HOME/.zshrc"
  if [ -L "$RC" ]; then
    echo "Skipping shell integration: ~/.zshrc is a symlink. Add the snippet from README manually." >&2
  elif [ -e "$RC" ] && grep -Fq '# >>> Ghostty Hack-Jitsu Edition >>>' "$RC"; then
    echo "OK shell integration already present"
  elif [ "$DRY_RUN" -eq 1 ]; then
    echo "PLAN append source stanza to $RC (backup first)"
  else
    if [ -f "$RC" ]; then
      mkdir -p "$BACKUP"
      cp -p "$RC" "$BACKUP/zshrc"
      echo "BACKUP $RC -> $BACKUP/zshrc"
    fi
    cat >> "$RC" <<'EOF'

# >>> Ghostty Hack-Jitsu Edition >>>
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/shell.zsh" ]; then
  source "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/shell.zsh"
fi
# <<< Ghostty Hack-Jitsu Edition <<<
EOF
    echo "SHELL integration added to $RC"
  fi
fi

echo "Setup complete. Open Ghostty and press Option+Tab to toggle its dropdown."
echo "Run hjhelp for the standalone pentest, network, admin, and terminal cheats."
