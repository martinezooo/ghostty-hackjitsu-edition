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
NO_NVIM=0
CHECK_ONLY=0
STRICT_CHECK=0
USER_INSTALL=-1
LAUNCH_GHOSTTY=auto
RESTART_GHOSTTY=auto

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--check] [--launch|--no-launch] [--restart|--no-restart] [--user] [--system] [--no-brew] [--no-shell] [--no-nvim] [--tools] [--strict]
  --dry-run   Show intended changes without writing or installing anything
  --check     Verify installed packages and settings without changing anything
  --launch    Open Ghostty after installation, even without an interactive TTY
  --no-launch Do not start Ghostty automatically
  --restart   Restart an existing Ghostty session (closes its tabs)
  --no-restart Preserve running Ghostty sessions; reload manually
  --user      Force per-user mode: no sudo; use ~/Applications for Ghostty
  --system    Force system-wide casks (needs administrator rights)
  --strict    Treat verification warnings as errors
  --no-brew   Install configuration only (skip Homebrew package installation)
  --no-shell  Do not add the optional shell integration to ~/.zshrc
  --no-nvim   Skip Neovim, LazyVim, and their dependencies
  --tools     Also install nmap, jq, ripgrep, and yq for command-line work
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --check) CHECK_ONLY=1 ;;
    --launch) LAUNCH_GHOSTTY=yes ;;
    --no-launch) LAUNCH_GHOSTTY=no ;;
    --restart) RESTART_GHOSTTY=yes; LAUNCH_GHOSTTY=yes ;;
    --no-restart) RESTART_GHOSTTY=no ;;
    --user) USER_INSTALL=1 ;;
    --system) USER_INSTALL=0 ;;
    --strict) STRICT_CHECK=1 ;;
    --no-brew) NO_BREW=1 ;;
    --no-shell) NO_SHELL=1 ;;
    --no-nvim) NO_NVIM=1 ;;
    --tools) TOOLS=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 2 ;;
  esac
done

verify_installation() {
  local DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
  local GHOSTTY_CONFIG="$CONFIG_HOME/ghostty"
  local HJ_CONFIG="$CONFIG_HOME/ghostty-hackjitsu"
  local NVIM_CONFIG="$CONFIG_HOME/nvim"
  local CHECK_NVIM=$((1 - NO_NVIM)) CHECK_SHELL=$((1 - NO_SHELL)) CHECK_TOOLS="$TOOLS"
  local STRICT="$STRICT_CHECK" PASSES=0 WARNS=0 FAILS=0
check_pass() { printf '[PASS] %s\n' "$*"; PASSES=$((PASSES + 1)); }
check_warn() { printf '[WARN] %s\n' "$*"; WARNS=$((WARNS + 1)); }
check_fail() { printf '[FAIL] %s\n' "$*"; FAILS=$((FAILS + 1)); }
check_available() { command -v "$1" >/dev/null 2>&1; }
check_formula() {
  local label="$1" executable="$2" formula="$3"
  if check_available "$executable"; then
    check_pass "$label available ($executable)"
    if check_available brew && ! brew list --formula "$formula" >/dev/null 2>&1; then
      check_warn "$label exists but is not registered as Homebrew formula $formula"
    fi
  else
    check_fail "$label missing. Fix: brew install $formula"
  fi
}
check_file_exists() {
  if [ -f "$1" ]; then check_pass "$2"; else check_fail "$2 missing: $1"; fi
}

printf 'Ghostty Hack-Jitsu Edition — installation diagnostics\n\n'
if [ "$(uname -s)" = Darwin ]; then check_pass "macOS supported"; else check_fail "macOS required"; fi
if check_available brew; then
  check_pass "Homebrew available"
else
  check_fail "Homebrew missing (https://brew.sh)"
fi

# macOS app bundles may not put the ghostty CLI into PATH.
GHOSTTY="${HJ_GHOSTTY_BINARY:-}"
if [ -z "$GHOSTTY" ]; then
  for candidate in /Applications/Ghostty.app/Contents/MacOS/ghostty \
                   "$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty"; do
    if [ -x "$candidate" ]; then GHOSTTY="$candidate"; break; fi
  done
fi
if [ -z "$GHOSTTY" ] && check_available ghostty; then GHOSTTY="$(command -v ghostty)"; fi
if [ -n "$GHOSTTY" ] && [ -x "$GHOSTTY" ]; then
  check_pass "Ghostty executable: $GHOSTTY"
  if check_available brew && ! brew list --cask ghostty >/dev/null 2>&1; then
    check_warn "Ghostty not registered as Homebrew cask (application may be installed manually)"
  fi
  if "$GHOSTTY" +validate-config >/dev/null 2>&1; then
    check_pass "Ghostty configuration syntax valid"
  else
    check_fail "Ghostty configuration validation failed: ghostty +validate-config"
  fi
  effective="$("$GHOSTTY" +show-config 2>/dev/null)" || effective=""
  if grep -Fq 'theme = hack-jitsu' <<< "$effective" &&
     grep -Fq 'font-family = JetBrainsMono Nerd Font Mono' <<< "$effective" &&
     grep -Fq 'quick-terminal-size = 40%,90%' <<< "$effective" &&
     grep -Fq 'hack-jitsu-cursor.glsl' <<< "$effective" &&
     grep -Fq 'hack-jitsu-watermark.png' <<< "$effective"; then
    check_pass "Ghostty active theme, font, dropdown, shader and watermark"
  else
    check_fail "Ghostty effective configuration does not match Hack-Jitsu profile"
  fi
  bindings="$("$GHOSTTY" +list-keybinds 2>/dev/null)" || bindings=""
  if grep -Eq 'alt\+tab=toggle_quick_terminal' <<< "$bindings"; then
    check_pass "Dropdown Option+Tab binding active"
  else
    check_fail "Dropdown Option+Tab binding missing"
  fi
  fonts="$("$GHOSTTY" +list-fonts 2>/dev/null)" || fonts=""
  if grep -Fq 'JetBrainsMono Nerd Font Mono' <<< "$fonts"; then
    face="$("$GHOSTTY" +show-face --cp=65 2>/dev/null)" || face=""
    if grep -Fq 'JetBrainsMono Nerd Font Mono' <<< "$face"; then
      check_pass "JetBrainsMono Nerd Font Mono actually rendered"
    else
      check_fail "Nerd Font installed but Ghostty renders a fallback face"
    fi
  else
    check_fail "Nerd Font not available. Fix: brew install --cask font-jetbrains-mono-nerd-font"
  fi
  if check_available brew && ! brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
    check_warn "Nerd Font is not recorded as a Homebrew cask"
  fi
else
  check_fail "Ghostty executable missing. Fix: brew install --cask ghostty"
fi

for asset in config themes/hack-jitsu shaders/hack-jitsu-cursor.glsl hack-jitsu-watermark.png; do
  check_file_exists "$GHOSTTY_CONFIG/$asset" "Ghostty asset: $asset"
done
for legacy in "$HOME/Library/Application Support/com.mitchellh.ghostty/config" \
              "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
  if [ -f "$legacy" ]; then
    check_warn "Additional Ghostty config exists; review potential overrides: $legacy"
  fi
done

check_formula "Navi cheats UI" navi navi
check_formula "fzf selector" fzf fzf
check_formula "Zellij multiplexer" zellij zellij
check_file_exists "$HJ_CONFIG/shell.zsh" "Shell helpers installed"
if [ -f "$HJ_CONFIG/shell.zsh" ] && check_available zsh &&
   zsh -n "$HJ_CONFIG/shell.zsh" >/dev/null 2>&1; then
  check_pass "Shell helpers parse as zsh"
else
  check_fail "Shell helpers invalid or zsh missing"
fi
for name in pentest network admin android terminal; do
  check_file_exists "$HJ_CONFIG/cheats/$name.cheat" "Cheat sheet: $name"
done
if check_available navi && [ -d "$HJ_CONFIG/cheats" ]; then
  snippet="$(navi --path "$HJ_CONFIG/cheats" --query 'Git: status repo' --best-match --print 2>/dev/null)" || snippet=""
  if [ "$snippet" = 'git status --short --branch' ]; then
    check_pass "Navi reads Hack-Jitsu cheats"
  else
    check_fail "Navi cannot resolve bundled cheat sheet"
  fi
fi
if [ "$CHECK_SHELL" -eq 1 ]; then
  if [ "${SHELL##*/}" != zsh ]; then
    check_warn "Default login shell is ${SHELL##*/}, not zsh; Hack-Jitsu prompt requires zsh"
  fi
  for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if check_available brew && brew list --formula "$plugin" >/dev/null 2>&1; then
      check_pass "$plugin installed"
    else
      found=0
      for prefix in "${HOMEBREW_PREFIX:-}" /opt/homebrew /usr/local; do
        [ -n "$prefix" ] || continue
        if [ -f "$prefix/share/$plugin/$plugin.zsh" ]; then found=1; break; fi
      done
      if [ "$found" -eq 1 ]; then
        check_pass "$plugin script available"
      else
        check_fail "$plugin missing. Fix: brew install $plugin"
      fi
    fi
  done
  if [ -f "$HOME/.zshrc" ] && grep -Fq '# >>> Ghostty Hack-Jitsu Edition >>>' "$HOME/.zshrc"; then
    check_pass "Shell integration present in ~/.zshrc"
  else
    check_fail "Shell integration missing in ~/.zshrc (review README)"
  fi
else
  check_pass "Shell integration intentionally skipped"
fi

if [ "$CHECK_NVIM" -eq 1 ]; then
  check_formula "Neovim" nvim neovim
  check_formula "lazygit" lazygit lazygit
  check_formula "ripgrep" rg ripgrep
  check_formula "fd" fd fd
  check_formula "Tree-sitter CLI" tree-sitter tree-sitter-cli
  if check_available nvim; then
    if nvim --headless -u NONE -c 'lua if vim.fn.has("nvim-0.11.2") == 0 then vim.cmd("cq") end' -c 'qa!' >/dev/null 2>&1; then
      check_pass "Neovim version meets LazyVim minimum (0.11.2)"
    else
      check_fail "Neovim version too old for current LazyVim"
    fi
  fi
  check_file_exists "$NVIM_CONFIG/init.lua" "Neovim entry point"
  check_file_exists "$NVIM_CONFIG/lua/config/lazy.lua" "LazyVim bootstrap config"
  if [ -d "$DATA_HOME/nvim/lazy/LazyVim" ]; then
    check_pass "LazyVim plugins initialized"
  else
    check_warn "LazyVim plugins not initialized yet: run nvim once, then ./install.sh --check"
  fi
  if ! check_available cc; then check_warn "C compiler missing; install Xcode Command Line Tools if needed"; fi
  if ! check_available curl; then check_warn "curl missing; required for LazyVim bootstrap"; fi
else
  check_pass "Neovim checks intentionally skipped"
fi
if [ "$CHECK_TOOLS" -eq 1 ]; then
  check_formula "nmap" nmap nmap
  check_formula "jq" jq jq
  check_formula "ripgrep" rg ripgrep
  check_formula "yq" yq yq
fi

printf '\nSummary: %d PASS | %d WARN | %d FAIL\n' "$PASSES" "$WARNS" "$FAILS"
if [ "$FAILS" -gt 0 ]; then return 1; fi
if [ "$STRICT" -eq 1 ] && [ "$WARNS" -gt 0 ]; then return 1; fi
return 0
}

if [ "$(uname -s)" != Darwin ]; then
  echo "Only macOS is supported." >&2
  exit 2
fi
if [ "$CHECK_ONLY" -eq 1 ]; then
  verify_installation
  exit $?
fi

# Choose the smallest privilege level that can do the work.
# Admin users keep normal Homebrew behavior; non-admin users avoid sudo.
if [ "$USER_INSTALL" -eq -1 ]; then
  if id -Gn | tr ' ' '\n' | grep -qx admin; then
    USER_INSTALL=0
  else
    USER_INSTALL=1
  fi
fi
if [ "$USER_INSTALL" -eq 0 ] && ! id -Gn | tr ' ' '\n' | grep -qx admin; then
  echo "ERROR: --system requires an administrator account." >&2
  echo "       Retry without --system; standard-user installation is supported when Homebrew is writable." >&2
  exit 2
fi
if [ "$USER_INSTALL" -eq 1 ]; then
  export HOMEBREW_NO_SUDO=1
  echo "INFO: Standard-user mode; Homebrew will not call sudo."
fi
if [ "$NO_BREW" -eq 0 ] && [ "$DRY_RUN" -eq 0 ] && ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew is not available. See https://brew.sh (or use --no-brew)." >&2
  exit 2
fi

# Homebrew can install formulas without sudo only when its prefix is writable
# by the current account; verify only when an actual install is required.
ensure_brew_writable() {
  if [ "$USER_INSTALL" -ne 1 ]; then return 0; fi
  local prefix
  prefix="$(brew --prefix 2>/dev/null || true)"
  if [ -n "$prefix" ] && [ -w "$prefix" ]; then return 0; fi
  echo "ERROR: This account cannot write to Homebrew prefix: ${prefix:-unknown}." >&2
  echo "       Ask IT to provision Homebrew for this account; do not use sudo brew." >&2
  echo "       Other installed packages can be checked with: ./install.sh --check" >&2
  return 1
}

installed_ghostty() {
  [ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ] ||
  [ -x "$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty" ] ||
  command -v ghostty >/dev/null 2>&1
}
installed_nerd_font() {
  if command -v brew >/dev/null 2>&1 &&
     brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
    return 0
  fi
  local exe=''
  if [ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]; then
    exe=/Applications/Ghostty.app/Contents/MacOS/ghostty
  elif [ -x "$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty" ]; then
    exe="$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty"
  elif command -v ghostty >/dev/null 2>&1; then
    exe="$(command -v ghostty)"
  fi
  if [ -n "$exe" ] &&
     grep -Fq 'JetBrainsMono Nerd Font Mono' <<< "$("$exe" +list-fonts 2>/dev/null)"; then
    return 0
  fi
  for dir in "$HOME/Library/Fonts" /Library/Fonts; do
    if [ -d "$dir" ] &&
       find "$dir" -maxdepth 1 -iname '*JetBrainsMono*Nerd*' -print -quit 2>/dev/null | grep -q .; then
      return 0
    fi
  done
  return 1
}
formula_executable() {
  case "$1" in
    ripgrep) echo rg ;;
    fd) echo fd ;;
    tree-sitter-cli) echo tree-sitter ;;
    *) echo "$1" ;;
  esac
}
brew_formula() {
  local formula="$1" exe
  exe="$(formula_executable "$formula")"
  if command -v "$exe" >/dev/null 2>&1; then
    echo "SKIP $formula: executable already available ($exe)"
    return 0
  fi
  if command -v brew >/dev/null 2>&1 &&
     brew list --formula "$formula" >/dev/null 2>&1; then
    echo "SKIP $formula: Homebrew reports installed"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then echo "PLAN brew install $formula"; return 0; fi
  ensure_brew_writable || exit 2
  echo "INSTALL formula: $formula"
  if ! brew install "$formula"; then
    echo "ERROR: Homebrew could not install $formula." >&2
    echo "       If sudo reports 'not in the sudoers file', contact IT for permissions." >&2
    echo "       Run ./install.sh --check to see remaining missing components." >&2
    exit 2
  fi
}
brew_cask() {
  local cask="$1"
  if [ "$cask" = ghostty ] && installed_ghostty; then
    echo "SKIP ghostty: application already available"
    return 0
  fi
  if [ "$cask" = font-jetbrains-mono-nerd-font ] && installed_nerd_font; then
    echo "SKIP $cask: font already available"
    return 0
  fi
  if command -v brew >/dev/null 2>&1 &&
     brew list --cask "$cask" >/dev/null 2>&1; then
    echo "SKIP $cask: Homebrew reports installed"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$USER_INSTALL" -eq 1 ] && [ "$cask" = ghostty ]; then
      echo "PLAN brew install --cask --appdir=$HOME/Applications ghostty"
    else
      echo "PLAN brew install --cask $cask"
    fi
    return 0
  fi
  ensure_brew_writable || exit 2
  echo "INSTALL cask: $cask"
  if [ "$USER_INSTALL" -eq 1 ] && [ "$cask" = ghostty ]; then
    mkdir -p "$HOME/Applications"
    if ! brew install --cask --appdir="$HOME/Applications" "$cask"; then
      echo "ERROR: Ghostty could not be installed in ~/Applications." >&2
      echo "       Your Mac or Homebrew may require IT provisioning." >&2
      exit 2
    fi
  elif ! brew install --cask "$cask"; then
    echo "ERROR: Homebrew could not install $cask." >&2
    echo "       If you see 'not in the sudoers file', use IT-approved installation." >&2
    echo "       A standard-user account cannot bypass that restriction." >&2
    exit 2
  fi
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

install_neovim_config() {
  local dest="$CONFIG_HOME/nvim"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    echo "SKIP existing Neovim config: $dest (left untouched)"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "PLAN install bundled LazyVim starter -> $dest"
    return
  fi
  mkdir -p "$CONFIG_HOME"
  cp -R "$ROOT/nvim" "$dest"
  echo "COPY bundled LazyVim starter -> $dest"
}

if [ "$NO_BREW" -eq 0 ]; then
  brew_cask ghostty
  brew_cask font-jetbrains-mono-nerd-font
  brew_formula navi
  brew_formula fzf
  brew_formula zellij
  if [ "$NO_SHELL" -eq 0 ]; then
    brew_formula zsh-autosuggestions
    brew_formula zsh-syntax-highlighting
  fi
  if [ "$NO_NVIM" -eq 0 ]; then
    for pkg in neovim lazygit ripgrep fd tree-sitter-cli; do brew_formula "$pkg"; done
  fi
  if [ "$TOOLS" -eq 1 ]; then
    for pkg in nmap jq ripgrep yq; do brew_formula "$pkg"; done
  fi
fi

if [ "$NO_NVIM" -eq 0 ]; then
  install_neovim_config
fi

# Ghostty loads the macOS application-support config after XDG config.
# An existing file in that location can silently override this profile.
for legacy in "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
              "$HOME/Library/Application Support/com.mitchellh.ghostty/config"; do
  if [ -f "$legacy" ]; then
    echo "WARNING: Ghostty may override this profile with: $legacy" >&2
    echo "         Review that file separately; this installer will not modify it." >&2
  fi
done

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

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "DRY RUN COMPLETE: no applications, settings, or files were changed."
  echo "Run ./install.sh to install, then press Option+Tab after Ghostty starts."
  exit 0
fi

verify_status=0
if [ "$NO_BREW" -eq 0 ]; then
  echo
  echo "=== Installation verification ==="
  verify_installation || verify_status=$?
else
  echo "INFO: Package verification skipped (--no-brew). Run ./install.sh --check when ready."
fi

echo
echo "============================================================"
if [ "$verify_status" -eq 0 ]; then
  echo " HACK-JITSU EDITION | SETUP FINISHED"
else
  echo " HACK-JITSU EDITION | SETUP NEEDS ATTENTION"
fi
echo "============================================================"
echo " Ghostty is a HIDDEN dropdown terminal:"
echo "   1. Start Ghostty once (it will not appear in the Dock)."
echo "   2. Press Option (Alt) + Tab to show/hide it."
echo "   3. If the shortcut fails, grant Ghostty access in:"
echo "      System Settings > Privacy & Security > Accessibility"
echo
echo " IN YOUR TERMINAL"
echo "   hj       Show Hack-Jitsu quick-start guide"
echo "   hjhelp   Search interactive pentest/admin/network cheats"
echo "   wave     Start or attach to Zellij session"
if [ "$NO_NVIM" -eq 0 ]; then
  echo "   nvim     Start LazyVim (first start downloads plugins)"
else
  echo "   nvim     Skipped during installation (--no-nvim)"
fi
echo
echo " DIAGNOSTICS"
echo "   ./install.sh --check    Read-only validation"
echo "   ./install.sh --dry-run  Preview changes"
echo "   Re-run ./install.sh safely: existing packages are skipped."
echo "============================================================"

if [ "$verify_status" -ne 0 ]; then
  echo "ERROR: Some installation checks failed. Review [FAIL] above." >&2
  echo "       Fix those items and rerun ./install.sh --check." >&2
  exit "$verify_status"
fi

# macOS Quick Terminal position/geometry can require a FULL app restart.
# Do not blindly kill existing sessions, as tabs may contain running commands.
ghostty_running() { pgrep -ix ghostty >/dev/null 2>&1; }
app=""
if [ -d "$HOME/Applications/Ghostty.app" ]; then
  app="$HOME/Applications/Ghostty.app"
elif [ -d /Applications/Ghostty.app ]; then
  app=/Applications/Ghostty.app
fi

open_ghostty() {
  if ! command -v open >/dev/null 2>&1; then return 1; fi
  if [ -n "$app" ]; then
    open "$app" >/dev/null 2>&1
  else
    open -a Ghostty >/dev/null 2>&1
  fi
}

# Deferral is important if the installer itself is running INSIDE Ghostty:
# the terminal session must first return so the summary can be read.
restart_ghostty() {
  if ! command -v osascript >/dev/null 2>&1; then
    echo "WARNING: osascript unavailable; quit and reopen Ghostty manually."
    return 1
  fi
  if [ "${TERM_PROGRAM:-}" = ghostty ]; then
    echo "Restarting Ghostty after this installer finishes; active Ghostty tabs will close."
    echo "After restart, press Option + Tab to open the responsive dropdown."
    nohup /bin/bash -c '
      sleep 3
      osascript -e '\''tell application "Ghostty" to quit'\'' >/dev/null 2>&1 || exit 1
      for i in {1..30}; do
        pgrep -ix ghostty >/dev/null 2>&1 || break
        sleep 0.2
      done
      if pgrep -ix ghostty >/dev/null 2>&1; then exit 1; fi
      if [ -n "$1" ]; then open "$1" >/dev/null 2>&1; else open -a Ghostty >/dev/null 2>&1; fi
    ' _ "$app" >/dev/null 2>&1 </dev/null &
    return 0
  fi
  if ! osascript -e 'tell application "Ghostty" to quit' >/dev/null 2>&1; then
    echo "WARNING: macOS refused the graceful Ghostty quit. Restart it manually."
    return 1
  fi
  for i in {1..30}; do
    ghostty_running || break
    sleep 0.2
  done
  if ghostty_running; then
    echo "WARNING: Ghostty is still running (maybe close confirmation). Restart manually."
    return 1
  fi
  if open_ghostty; then
    echo "Ghostty restarted with the updated display-relative dropdown size."
    return 0
  fi
  echo "WARNING: Ghostty quit, but could not be reopened. Use: open -a Ghostty"
  return 1
}

if [ "$LAUNCH_GHOSTTY" = auto ]; then
  LAUNCH_GHOSTTY=no
  if [ -t 0 ] && [ -t 1 ]; then LAUNCH_GHOSTTY=yes; fi
fi
if [ "$LAUNCH_GHOSTTY" != yes ]; then
  echo "Start Ghostty: open -a Ghostty (then Option + Tab)."
elif ghostty_running; then
  if [ "$RESTART_GHOSTTY" = auto ]; then
    RESTART_GHOSTTY=no
    if [ -t 0 ] && [ -t 1 ]; then
      printf 'Ghostty is running. Restart to apply new dropdown size? Existing tabs will close. [Y/n] '
      answer=''
      IFS= read -r answer || true
      case "$answer" in ""|y|Y|yes|YES) RESTART_GHOSTTY=yes ;; esac
    fi
  fi
  if [ "$RESTART_GHOSTTY" = yes ]; then
    restart_ghostty || true
  else
    echo "Ghostty is running; did not close existing tabs."
    echo "To apply the new window geometry, quit Ghostty fully and reopen it."
    echo "Or run ./install.sh --restart to perform a graceful restart."
  fi
elif open_ghostty; then
  echo "Ghostty launched. Its Dock icon is intentionally hidden. Press Option + Tab."
else
  echo "WARNING: Could not start Ghostty. Start it manually via Applications."
fi
