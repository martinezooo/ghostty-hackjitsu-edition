# Dedicated Hack-Jitsu Ghostty startup: $ZDOTDIR/.zshrc
# Do not import ~/.zshrc, ~/.zprofile, oh-my-zsh, tmux, or work tooling.
if [[ -x /opt/homebrew/bin/brew ]] && [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
  path=(/opt/homebrew/bin /opt/homebrew/sbin $path)
elif [[ -x /usr/local/bin/brew ]] && [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
  path=(/usr/local/bin /usr/local/sbin $path)
fi
export PATH

# Persistent shell history. ZDOTDIR isolates startup files, but should not
# discard a user's command history when moving from regular Zsh to Ghostty.
# Reuse existing ~/.zsh_history when writable; otherwise keep a private
# Hack-Jitsu history in XDG state. Neither file is included in this repo.
HISTSIZE=50000
SAVEHIST=50000
if [[ -f "$HOME/.zsh_history" && -r "$HOME/.zsh_history" && -w "$HOME/.zsh_history" ]]; then
  HISTFILE="$HOME/.zsh_history"
else
  _hj_history_dir="${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-hackjitsu"
  ( umask 077; mkdir -p -m 700 "$_hj_history_dir" ) 2>/dev/null || true
  if [[ -d "$_hj_history_dir" && -w "$_hj_history_dir" ]]; then
    HISTFILE="$_hj_history_dir/zsh_history"
    ( umask 077; touch "$HISTFILE" ) 2>/dev/null || true
  fi
  unset _hj_history_dir
fi
setopt SHARE_HISTORY EXTENDED_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

# Restore Ghostty's shell integration without ZDOTDIR auto-injection.
if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" && -r "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration" ]]; then
  source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
fi
_hj_completion="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/completion.zsh"
if [[ -r "$_hj_completion" ]]; then
  source "$_hj_completion"
fi
unset _hj_completion
_hj_core="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/shell.zsh"
if [[ -r "$_hj_core" ]]; then
  source "$_hj_core"
else
  print -u2 'Hack-Jitsu: missing shell.zsh; rerun installer.'
fi
unset _hj_core
# Powerlevel10k is opt-in: the standalone Hack-Jitsu wizard enables it only
# after generating an isolated config. Never read personal ~/.p10k.zsh.
_hj_p10k_zd="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/zsh"
if [[ -f "$_hj_p10k_zd/enable-p10k" && -r "$_hj_p10k_zd/.p10k.zsh" ]]; then
  for _hj_p10k_root in /opt/homebrew/share/powerlevel10k                       /usr/local/share/powerlevel10k; do
    if [[ -r "$_hj_p10k_root/powerlevel10k.zsh-theme" ]]; then
      source "$_hj_p10k_root/powerlevel10k.zsh-theme"
      source "$_hj_p10k_zd/.p10k.zsh"
      break
    fi
  done
fi
unset _hj_p10k_zd _hj_p10k_root



# Use our own small Zellij config; avoid the first-run keybinding wizard and
# preserve the user's unrelated ~/.config/zellij configuration.
_hj_zellij_config="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/zellij/config.kdl"
if [[ -r "$_hj_zellij_config" ]]; then
  export ZELLIJ_CONFIG_FILE="$_hj_zellij_config"
fi
unset _hj_zellij_config

# Default LOCAL Ghostty workspace: a NEW Zellij session with a real shell.
# Never auto-attach/resurrect an old session (which may contain a running
# editor or a no-longer-existing pane). Previous sessions remain untouched
# and may be resumed manually with wave <session-name> when desired.
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
    # Keep name SHORT: macOS has a ~104-byte UNIX socket path limit and
    # Zellij appends the name to the already-long macOS TMPDIR path.
    # This shell's PID is unique among currently running terminals.
    # A full close quits this disposable Zellij session (on_force_close).
    _hj_session="hj-$$"
    zellij --session "$_hj_session"
    unset _hj_session
  else
    print -u2 'Hack-Jitsu: Zellij not installed; opening standard shell.'
  fi
fi
