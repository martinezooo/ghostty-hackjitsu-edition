# Dedicated Hack-Jitsu Ghostty startup: $ZDOTDIR/.zshrc
# Do not import ~/.zshrc, ~/.zprofile, oh-my-zsh, tmux, or work tooling.
if [[ -x /opt/homebrew/bin/brew ]] && [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
  path=(/opt/homebrew/bin /opt/homebrew/sbin $path)
elif [[ -x /usr/local/bin/brew ]] && [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
  path=(/usr/local/bin /usr/local/sbin $path)
fi
export PATH
# Restore Ghostty's shell integration without ZDOTDIR auto-injection.
if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" && -r "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration" ]]; then
  source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
fi
_hj_core="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/shell.zsh"
if [[ -r "$_hj_core" ]]; then
  source "$_hj_core"
else
  print -u2 'Hack-Jitsu: missing shell.zsh; rerun installer.'
fi
unset _hj_core


# Use our own small Zellij config; avoid the first-run keybinding wizard and
# preserve the user's unrelated ~/.config/zellij configuration.
_hj_zellij_config="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/zellij/config.kdl"
if [[ -r "$_hj_zellij_config" ]]; then
  export ZELLIJ_CONFIG_FILE="$_hj_zellij_config"
fi
unset _hj_zellij_config

# Default LOCAL Ghostty workspace: attach to one persistent Zellij session.
# No nesting in Zellij/tmux, no remote SSH auto-start, and no recursion.
# Disable with: touch ~/.config/ghostty-hackjitsu/zsh/no-auto-zellij
# or export HJ_AUTO_ZELLIJ=0 before launching Ghostty.
if [[ -o interactive && -t 0 && -t 1 ]] &&
   [[ "${TERM_PROGRAM:-}" == ghostty || "${TERM:-}" == xterm-ghostty ]] &&
   [[ -z "${ZELLIJ:-}" && -z "${TMUX:-}" ]] &&
   [[ -z "${SSH_CONNECTION:-}" && -z "${SSH_TTY:-}" ]] &&
   [[ "${HJ_AUTO_ZELLIJ:-1}" != 0 ]] &&
   [[ ! -e "${ZDOTDIR:-$HOME}/no-auto-zellij" ]]; then
  if (( $+commands[zellij] )); then
    zellij attach -c hackjitsu
  else
    print -u2 'Hack-Jitsu: Zellij not installed; opening standard shell.'
  fi
fi
