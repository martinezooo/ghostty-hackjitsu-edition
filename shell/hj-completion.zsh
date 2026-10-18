# Hack-Jitsu interactive shell UX. Loaded only by our isolated ZDOTDIR.
# Never touches the personal ~/.zshrc or global completion configuration.
if [[ ! -o interactive ]]; then
  return 0
fi

# Rich listings with a sane fallback. "command ls" bypasses this local alias.
if (( $+commands[eza] )); then
  alias ls='eza --icons=auto --color=auto --group-directories-first'
  alias ll='eza -lah --icons=auto --color=auto --group-directories-first --git'
  alias la='eza -la --icons=auto --color=auto --group-directories-first'
  alias lt='eza --tree --level=2 --icons=auto --color=auto --group-directories-first'
fi

# fzf-tab MUST load after compinit, before zsh-autosuggestions and highlighting.
# The standard Zsh completion system is still usable if fzf-tab is absent.
_hj_brew_prefix="${HOMEBREW_PREFIX:-}"
if [[ -z "$_hj_brew_prefix" ]] && (( $+commands[brew] )); then
  _hj_brew_prefix="$(brew --prefix 2>/dev/null)"
fi
for _hj_prefix in "$_hj_brew_prefix" /opt/homebrew /usr/local; do
  [[ -n "$_hj_prefix" ]] || continue
  if [[ -d "$_hj_prefix/share/zsh-completions" ]]; then
    fpath=("$_hj_prefix/share/zsh-completions" $fpath)
    break
  fi
done
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' menu no
zstyle ':completion:*' group-name ''
autoload -Uz compinit
# Isolated profile -> isolated compilation cache; no ~/.zcompdump changes.
_hj_compdump="${XDG_CACHE_HOME:-$HOME/.cache}/ghostty-hackjitsu/zcompdump"
mkdir -p "${_hj_compdump:h}" 2>/dev/null || true
compinit -d "$_hj_compdump" 2>/dev/null || compinit -D
for _hj_prefix in "$_hj_brew_prefix" /opt/homebrew /usr/local; do
  [[ -n "$_hj_prefix" ]] || continue
  _hj_fzf_tab="$_hj_prefix/opt/fzf-tab/share/fzf-tab/fzf-tab.zsh"
  [[ -r "$_hj_fzf_tab" ]] || _hj_fzf_tab="$_hj_prefix/share/fzf-tab/fzf-tab.zsh"
  if [[ -r "$_hj_fzf_tab" ]] && (( $+commands[fzf] )); then
    source "$_hj_fzf_tab"
    break
  fi
done
unset _hj_brew_prefix _hj_prefix _hj_compdump _hj_fzf_tab

# Does not run on every command; use `hjfetch` to show system details on demand.
hjfetch() {
  if (( ! $+commands[fastfetch] )); then
    print -u2 'hjfetch: install fastfetch to display system information'
    return 127
  fi
  local _hj_logo="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/logo.txt"
  if [[ -r "$_hj_logo" ]]; then
    command fastfetch --file "$_hj_logo" --structure OS:Kernel:Uptime:Packages:Shell:Terminal:CPU:GPU:Memory:Disk:Battery
  else
    command fastfetch --logo none --structure OS:Kernel:Uptime:Packages:Shell:Terminal:CPU:GPU:Memory:Disk:Battery
  fi
}

# Startup banner once per interactive terminal when wide enough; opt out via
# HJ_NO_BANNER=1. Narrow Zellij panes remain clean.
if [[ "${HJ_NO_BANNER:-0}" != 1 && -t 1 && ${COLUMNS:-0} -ge 108 ]] &&
   [[ -n "${ZELLIJ:-}" || "${HJ_AUTO_ZELLIJ:-1}" == 0 ]]; then
  hjfetch 2>/dev/null || true
fi
