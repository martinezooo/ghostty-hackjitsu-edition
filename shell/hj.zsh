# Optional shell helpers, sourced by ~/.zshrc after install.
hjhelp() {
  if ! command -v navi >/dev/null 2>&1; then
    print -u2 'hjhelp: navi is not installed (brew install navi)'
    return 127
  fi
  command navi --path "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/cheats" "$@"
}

# Attach to an existing named Zellij session, or start one.
if ! typeset -f wave >/dev/null 2>&1; then
  wave() {
    if ! command -v zellij >/dev/null 2>&1; then
      print -u2 'wave: zellij is not installed (brew install zellij)'
      return 127
    fi
    zellij attach -c wave
  }
fi

hj() {
  printf '\033[1;31mHACK\033[0;1m-JITSU\033[0m  |  Ghostty Edition\n'
  printf 'Press Option+Tab for dropdown. Use hjhelp for command cheats.\n'
}
