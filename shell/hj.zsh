# Self-contained shell helpers sourced ONLY by the Hack-Jitsu ZDOTDIR/.zshrc.
hjsetup() {
  local script="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/ui-setup.sh"
  if [[ ! -r "$script" ]]; then
    print -u2 "hjsetup: install.sh must be run first"
    return 1
  fi
  command bash "$script" "$@"
}

hjkeys() {
  print -P '%B%F{#ec1313}HACK-JITSU · macOS Zellij keys%f%b'
  print '  ⌥ Option = Alt  |  ⌃ Control = Ctrl'
  print '  ⌃ Control + P, then N  New pane'
  print '  ⌃ Control + T, then N  New tab'
  print '  ⌃ Control + G          Lock/unlock Zellij'
  print '  ⌃ Control + O, then C  Zellij keybinding configuration'
  print '  hjsetup                 Window title / full or compact status bar'
  print '  Default: left Option works as Alt; right Option keeps Polish letters.'
}

hjhelp() {
  if ! command -v navi >/dev/null 2>&1; then
    print -u2 'hjhelp: navi is not installed (brew install navi)'
    return 127
  fi
  command navi --path "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/cheats" "$@"
}

# Explicit/manual reattachment to an old named session, never on startup.
if ! typeset -f wave >/dev/null 2>&1; then
  wave() {
    if ! command -v zellij >/dev/null 2>&1; then
      print -u2 'wave: zellij is not installed (brew install zellij)'
      return 127
    fi
    if [[ -n "${ZELLIJ:-}" ]]; then
      print "Already inside a Zellij session"
      return 0
    fi
    if (( $# == 0 )); then
      zellij attach
    else
      zellij attach "$@"
    fi
  }
fi

hj() {
  printf '\033[1;31mHACK\033[0;1m-JITSU\033[0m  |  Ghostty Edition\n'
  printf '\n'
  printf '  Option + Tab       Toggle the dropdown terminal\n'
  printf '  hj                 Show this guide again\n'
  printf '  hjhelp             Interactive pentest, network, admin and terminal cheats\n'
  printf '  hjfetch            HACK JITSU system dashboard\n'
  printf '  hjsetup            Configure title / Zellij bar / Mac Option key\n'
  printf '  hjkeys             Mac key guide (Option = Alt)\n'
  printf '  ls / ll / la / lt  File lists with colors and icons\n'
  printf '  Tab                Interactive argument completion\n'
  printf '  Zellij             Starts a new, clean session in Ghostty\n'
  printf '  wave [name]        Reattach a previous session manually\n'
  printf '  nvim               Start Neovim + LazyVim\n'
  printf '  Ctrl+P then N      Open a second Zellij pane with shell\n'
  printf '\n'
  printf '  Troubleshooting: ./install.sh --check  (from the cloned repository)\n'
}

# Hack-Jitsu shell appearance is scoped to an interactive LOCAL Ghostty session.
# The macOS Terminal, SSH sessions and noninteractive scripts retain their own prompt.
if [[ -o interactive ]] &&
   [[ "${TERM_PROGRAM:-}" == ghostty || "${TERM:-}" == xterm-ghostty ]] &&
   [[ -z "${SSH_CONNECTION:-}" && -z "${SSH_TTY:-}" ]]; then
  # Resolve both Apple Silicon and Intel Homebrew installations.
  _hj_brew_prefix="${HOMEBREW_PREFIX:-}"
  if [[ -z "$_hj_brew_prefix" ]] && (( $+commands[brew] )); then
    _hj_brew_prefix="$(brew --prefix 2>/dev/null)"
  fi
  for _hj_p in "$_hj_brew_prefix" /opt/homebrew /usr/local; do
    [[ -n "$_hj_p" ]] || continue
    if [[ -f "$_hj_p/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] &&
       (( ! $+functions[_zsh_autosuggest_start] )); then
      source "$_hj_p/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    fi
    if [[ -f "$_hj_p/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] &&
       (( ! $+functions[_zsh_highlight] )); then
      source "$_hj_p/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
    fi
  done
  unset _hj_brew_prefix _hj_p

  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=242'
  if (( $+functions[_zsh_highlight] )); then
    typeset -gA ZSH_HIGHLIGHT_STYLES
    ZSH_HIGHLIGHT_STYLES[default]='fg=white'
    ZSH_HIGHLIGHT_STYLES[command]='fg=cyan,bold'
    ZSH_HIGHLIGHT_STYLES[alias]='fg=cyan,bold'
    ZSH_HIGHLIGHT_STYLES[builtin]='fg=cyan,bold'
    ZSH_HIGHLIGHT_STYLES[function]='fg=cyan,bold'
    ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=red,bold'
    ZSH_HIGHLIGHT_STYLES[path]='fg=cyan,underline'
    ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=yellow'
    ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=yellow'
    ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=magenta'
    ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=cyan'
  fi

  # Keep the prompt short and stable, regardless of the current path or repo.
  # More detailed context is available on demand through pwd/git status.
  PROMPT='%B%F{#ec1313}❯%f%b '
  RPROMPT=''

  # No nvim wrapper. Standard nvim runs as a child of the Zsh pane:
  # :q! returns to this exact shell instead of closing/restoring a Zellij pane.
fi

# Show the guide once per macOS user, in Ghostty only, never in SSH/noninteractive shells.
if [[ -o interactive && -t 1 ]] &&
   [[ "${TERM_PROGRAM:-}" == ghostty || "${TERM:-}" == xterm-ghostty ]] &&
   [[ -z "${SSH_CONNECTION:-}" && -z "${SSH_TTY:-}" ]]; then
  _hj_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-hackjitsu"
  if [[ ! -e "$_hj_state_dir/welcome-shown" ]]; then
    if mkdir -p "$_hj_state_dir" 2>/dev/null &&
       touch "$_hj_state_dir/welcome-shown" 2>/dev/null; then
      hj
    fi
  fi
  unset _hj_state_dir
fi
