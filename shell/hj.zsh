# Self-contained shell helpers sourced ONLY by the Hack-Jitsu ZDOTDIR/.zshrc.
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
    if [[ -n "${ZELLIJ:-}" ]]; then
      print "Already inside a Zellij session"
      return 0
    fi
    zellij attach -c hackjitsu
  }
fi

hj() {
  printf '\033[1;31mHACK\033[0;1m-JITSU\033[0m  |  Ghostty Edition\n'
  printf '\n'
  printf '  Option + Tab       Toggle the dropdown terminal\n'
  printf '  hj                 Show this guide again\n'
  printf '  hjhelp             Interactive pentest, network, admin and terminal cheats\n'
  printf '  hjfetch            HACK JITSU system dashboard\n'
  printf '  ls / ll / la / lt  File lists with colors and icons\n'
  printf '  Tab                Interactive argument completion\n'
  printf '  Zellij             Starts automatically in Ghostty (session: hackjitsu)
  wave               Reattach to hackjitsu after leaving Zellij\n'
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

  autoload -Uz vcs_info add-zsh-hook
  zstyle ':vcs_info:git:*' formats ' %%F{red}[%b]%%f'
  zstyle ':vcs_info:git:*' actionformats ' %%F{red}[%b:%a]%%f'
  _hj_precmd() { vcs_info; }
  if (( ${precmd_functions[(Ie)_hj_precmd]:-0} == 0 )); then
    add-zsh-hook precmd _hj_precmd
  fi
  setopt prompt_subst
  # Red username / grey hostname / white directory / red Git branch.
  # %n, %m and %~ are expanded by Zsh, never stored as personal data in Git.
  PROMPT='%F{242}╭─%f %B%F{white}%~%f%b${vcs_info_msg_0_}\n%B%F{#ec1313}❯%f%b '
  RPROMPT='%F{242}%D{%H:%M}%f'

  # In Zellij, single-file "nvim filename" opens the editor in-place and
  # restores the ORIGINAL shell pane when :q! closes the editor.
  # Complex Neovim invocations keep their normal CLI semantics.
  if [[ -n "${ZELLIJ:-}" ]] && (( $+commands[nvim] && $+commands[zellij] )); then
    nvim() {
      if (( $# == 1 )) && [[ "$1" != -* ]] && [[ "${HJ_NVIM_DIRECT:-0}" != 1 ]]; then
        command env EDITOR=nvim VISUAL=nvim zellij edit --in-place "$1"
      else
        command nvim "$@"
      fi
    }
  fi
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
