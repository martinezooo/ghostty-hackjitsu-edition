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
SKIP_LAZY_SYNC=0
SETUP_UI=0
CHECK_ONLY=0
STRICT_CHECK=0
USER_INSTALL=-1
QUIT_GHOSTTY=1
RELAUNCH_GHOSTTY=1

# Color is enabled only for an interactive terminal (or an explicit test
# override). Redirected logs and CI output stay plain and grep-friendly.
if [[ -z "${NO_COLOR:-}" && "${HJ_INSTALL_COLOR:-auto}" != never ]] &&
   { [[ -t 1 ]] || [[ "${HJ_INSTALL_COLOR:-auto}" == always ]]; }; then
  HJ_GREEN=$'\033[1;32m'
  HJ_YELLOW=$'\033[1;33m'
  HJ_RED=$'\033[1;31m'
  HJ_BLUE=$'\033[1;36m'
  HJ_RESET=$'\033[0m'
else
  HJ_GREEN='' HJ_YELLOW='' HJ_RED='' HJ_BLUE='' HJ_RESET=''
fi
status() {
  local label="$1" message="$2" color=''
  case "$label" in
    PASS|COPY|READY) color="$HJ_GREEN" ;;
    WARN|SKIP|BACKUP) color="$HJ_YELLOW" ;;
    FAIL|ERROR) color="$HJ_RED" ;;
    INFO|PLAN|INSTALL) color="$HJ_BLUE" ;;
  esac
  case "$label" in
    PASS|WARN|FAIL|ERROR|INFO) printf '%s[%s]%s %s\n' "$color" "$label" "$HJ_RESET" "$message" ;;
    *) printf '%s%s%s %s\n' "$color" "$label" "$HJ_RESET" "$message" ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--check] [--no-quit] [--user] [--system] [--no-brew] [--no-shell] [--no-nvim] [--no-lazy-sync] [--setup] [--no-relaunch] [--tools] [--strict]
  --dry-run   Show intended changes without writing or installing anything
  --check     Verify installed packages and settings without changing anything
  --no-quit   Leave Ghostty running; skip restart (safe for active sessions)
  --no-relaunch Stop Ghostty after installation instead of reopening it
  --user      Force per-user mode: no sudo; use ~/Applications for Ghostty
  --system    Force system-wide casks (needs administrator rights)
  --strict    Treat verification warnings as errors
  --no-brew   Install configuration only (skip Homebrew package installation)
  --no-shell  Skip optional Zsh plugins (isolated Ghostty shell still installed)
  --no-nvim   Skip Neovim, LazyVim, and their dependencies
  --no-lazy-sync Defer first LazyVim plugin download until starting nvim
  --setup     Run interactive title/Zellij/Option wizard during installation
  --tools     Also install nmap, jq, ripgrep, and yq for command-line work
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --check) CHECK_ONLY=1 ;;
    --no-quit) QUIT_GHOSTTY=0 ;;
    --launch|--no-launch|--restart|--no-restart)
      echo "ERROR: $arg is obsolete. Installation restarts Ghostty by default." >&2
      echo "       Run ./install.sh, --no-quit to retain it, or --no-relaunch to stop it." >&2
      exit 2 ;;
    --no-relaunch) RELAUNCH_GHOSTTY=0 ;;
    --user) USER_INSTALL=1 ;;
    --system) USER_INSTALL=0 ;;
    --strict) STRICT_CHECK=1 ;;
    --no-brew) NO_BREW=1 ;;
    --no-shell) NO_SHELL=1 ;;
    --no-nvim) NO_NVIM=1 ;;
    --no-lazy-sync) SKIP_LAZY_SYNC=1 ;;
    --setup) SETUP_UI=1 ;;
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
check_pass() { status PASS "$*"; PASSES=$((PASSES + 1)); }
check_warn() { status WARN "$*"; WARNS=$((WARNS + 1)); }
check_fail() { status FAIL "$*"; FAILS=$((FAILS + 1)); }
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
  if grep -Fq 'macos-hidden = always' <<< "$effective" &&
     grep -Fq 'initial-window = false' <<< "$effective" &&
     grep -Fq 'window-save-state = never' <<< "$effective" &&
     grep -Fq 'theme = hack-jitsu' <<< "$effective" &&
     grep -Fq 'font-family = JetBrainsMono Nerd Font Mono' <<< "$effective" &&
     grep -Fq 'quick-terminal-size = 55%,85%' <<< "$effective" &&
     grep -Fq 'ZDOTDIR=' <<< "$effective" &&
     grep -Fq 'hack-jitsu-cursor.glsl' <<< "$effective" &&
     grep -Fq 'hack-jitsu-watermark.png' <<< "$effective"; then
    check_pass "Ghostty headless mode, theme, font, dropdown, shader and watermark"
  else
    check_fail "Ghostty effective configuration does not match Hack-Jitsu headless profile"
    check_fail "Review ~/.config/ghostty/config and any overrides in ~/Library/Application Support/com.mitchellh.ghostty/"
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
    check_warn "Additional Ghostty config exists and may override this profile: $legacy"
  fi
done

check_formula "Navi cheats UI" navi navi
check_formula "fzf selector" fzf fzf
check_formula "Zellij multiplexer" zellij zellij
check_file_exists "$HJ_CONFIG/shell.zsh" "Shell helpers installed"
check_file_exists "$HJ_CONFIG/ui-setup.sh" "Interactive terminal appearance wizard installed"
check_file_exists "$HJ_CONFIG/restart-ghostty.sh" "Controlled Ghostty app relaunch helper installed"
check_file_exists "$HJ_CONFIG/ghostty-template.conf" "Portable Ghostty base preserved"
check_file_exists "$HJ_CONFIG/zellij/template.kdl" "Portable Zellij base preserved"
check_file_exists "$HJ_CONFIG/zellij/config.kdl" "User Zellij layout installed"
check_file_exists "$HJ_CONFIG/completion.zsh" "Isolated completion and file-listing module"
check_file_exists "$HJ_CONFIG/logo.txt" "Hack-Jitsu ASCII logo"
if [ "$CHECK_SHELL" -eq 1 ]; then
  for ux_bin in eza fastfetch; do
    if check_available "$ux_bin"; then check_pass "$ux_bin available"
    else check_warn "$ux_bin is missing (brew install $ux_bin)"; fi
  done
  if check_available brew && brew list --formula fzf-tab >/dev/null 2>&1; then
    check_pass "fzf-tab installed for interactive completions"
  else
    check_warn "fzf-tab not installed; standard Zsh completion will be used"
  fi
fi
check_file_exists "$HJ_CONFIG/zellij/config.kdl" "Isolated Zellij config installed"
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
  check_file_exists "$HJ_CONFIG/zsh/.zshrc" "Isolated Ghostty ZDOTDIR/.zshrc"
  if [ -f "$HJ_CONFIG/zsh/.zshrc" ] && check_available zsh; then
    if zsh -n "$HJ_CONFIG/zsh/.zshrc" >/dev/null 2>&1; then
      check_pass "Dedicated Ghostty Zsh startup valid"
    else
      check_fail "Dedicated Ghostty Zsh startup invalid"
    fi
  fi
  if [ -f "$HOME/.zshrc" ] && grep -Fq '# >>> Ghostty Hack-Jitsu Edition >>>' "$HOME/.zshrc"; then
    check_fail "Obsolete Hack-Jitsu block remains in ~/.zshrc; installer must migrate it"
  else
    check_pass "No Hack-Jitsu modification in personal ~/.zshrc"
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

printf '\nSummary: %s%d PASS%s | %s%d WARN%s | %s%d FAIL%s\n' \
  "$HJ_GREEN" "$PASSES" "$HJ_RESET" \
  "$HJ_YELLOW" "$WARNS" "$HJ_RESET" \
  "$HJ_RED" "$FAILS" "$HJ_RESET"
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
    status SKIP "$formula: executable already available ($exe)"
    return 0
  fi
  if command -v brew >/dev/null 2>&1 &&
     brew list --formula "$formula" >/dev/null 2>&1; then
    status SKIP "$formula: Homebrew reports installed"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then echo "PLAN brew install $formula"; return 0; fi
  ensure_brew_writable || exit 2
  status INSTALL "formula: $formula"
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
    status SKIP "ghostty: application already available"
    return 0
  fi
  if [ "$cask" = font-jetbrains-mono-nerd-font ] && installed_nerd_font; then
    status SKIP "$cask: font already available"
    return 0
  fi
  if command -v brew >/dev/null 2>&1 &&
     brew list --cask "$cask" >/dev/null 2>&1; then
    status SKIP "$cask: Homebrew reports installed"
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
  status INSTALL "cask: $cask"
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
    status PASS "OK unchanged: $dest"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then echo "PLAN copy $source -> $dest"; return; fi
  if [ -e "$dest" ]; then
    mkdir -p "$BACKUP"
    cp -p "$dest" "$BACKUP/$label"
    status BACKUP "$dest -> $BACKUP/$label"
  fi
  mkdir -p "$(dirname "$dest")"
  cp -p "$source" "$dest"
  status COPY "$dest"
}

install_neovim_config() {
  local dest="$CONFIG_HOME/nvim"
  if [ -L "$dest" ]; then
    echo "SKIP symlinked Neovim config: $dest (left untouched)"
    return
  fi
  if [ -e "$dest" ]; then
    # Upgrade ONLY configurations originally supplied by Hack-Jitsu.
    # Never alter other Neovim/LazyVim profiles or a user's private setup.
    if [ ! -d "$dest" ] || [ ! -f "$dest/init.lua" ] ||
       [ -L "$dest/init.lua" ] || [ -L "$dest/lua" ] ||
       [ -L "$dest/lua/config" ] ||
       ! grep -Fq 'Portable LazyVim configuration for Ghostty Hack-Jitsu Edition' "$dest/init.lua" ||
       ! grep -Fxq 'require("config.lazy")' "$dest/init.lua"; then
      echo "SKIP existing Neovim config: $dest (left untouched)"
      return
    fi
    if ! grep -Fq 'require("config.ansi").setup()' "$dest/init.lua"; then
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "PLAN enable native ANSI log view in managed $dest/init.lua (with backup)"
      else
        local temp_init
        mkdir -p "$BACKUP"
        cp -p "$dest/init.lua" "$BACKUP/nvim-init-before-ansi"
        temp_init="$(mktemp "$dest/init.lua.hj.XXXXXX")"
        awk '
          $0 == "require(\"config.lazy\")" && !installed {
            print "-- Hide ANSI color codes in logs without altering original files."
            print "require(\"config.ansi\").setup()"
            installed = 1
          }
          {print}
        ' "$dest/init.lua" > "$temp_init"
        chmod "$(stat -f %Lp "$dest/init.lua")" "$temp_init" 2>/dev/null || chmod 600 "$temp_init"
        mv "$temp_init" "$dest/init.lua"
        echo "UPDATED managed Neovim ANSI log view (init.lua backup in $BACKUP)"
      fi
    fi
    copy_asset "$ROOT/nvim/lua/config/ansi.lua" "$dest/lua/config/ansi.lua" nvim-ansi
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
# Complete the initial Neovim/LazyVim download during installation,
# not unexpectedly when the first real log file is opened in the editor.
prepare_lazyvim() {
  local nvim_config="$CONFIG_HOME/nvim/init.lua"
  local lazy_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/LazyVim"
  if [ "$NO_NVIM" -eq 1 ] || [ "$NO_BREW" -eq 1 ] ||
     [ "$SKIP_LAZY_SYNC" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  # A preexisting or unrelated nvim profile is never bootstrapped by us.
  if [ ! -f "$nvim_config" ] ||
     ! grep -Fq 'Portable LazyVim configuration for Ghostty Hack-Jitsu Edition' "$nvim_config"; then
    return 0
  fi
  if [ -d "$lazy_dir" ]; then
    echo "SKIP LazyVim: plugins already initialized"
    return 0
  fi
  if ! command -v nvim >/dev/null 2>&1 ||
     ! command -v git >/dev/null 2>&1; then
    echo "WARNING: Neovim/git unavailable; first nvim start may install LazyVim plugins." >&2
    return 0
  fi
  echo "Preparing LazyVim plugins now (first setup may take a few minutes)..."
  local log
  log="$(mktemp)"
  if nvim --headless '+Lazy! sync' '+qa!' >"$log" 2>&1 &&
     [ -d "$lazy_dir" ] &&
     ! grep -Eq 'Error detected|Failed to run .config.|E5108|FATAL' "$log"; then
    echo "OK LazyVim plugins initialized; opening a file should not trigger a first-time sync."
  else
    echo "WARNING: LazyVim plugin setup failed. Review the last output below:" >&2
    tail -n 12 "$log" >&2
    echo "         Try again later from Neovim: :Lazy sync" >&2
  fi
  rm -f "$log"
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
    brew_formula zsh-completions
    brew_formula fzf-tab
    brew_formula eza
    brew_formula fastfetch
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
prepare_lazyvim

# Ghostty loads the macOS application-support config after XDG config.
# An existing file in that location can silently override this profile.
for legacy in "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
              "$HOME/Library/Application Support/com.mitchellh.ghostty/config"; do
  if [ -f "$legacy" ]; then
    echo "WARNING: Ghostty may override this profile with: $legacy" >&2
    echo "         Review that file separately; this installer will not modify it." >&2
  fi
done

# Use pristine templates to generate user-specific local title/status settings.
copy_asset "$ROOT/ghostty/config" "$HJ_DEST/ghostty-template.conf" ghostty-template
copy_asset "$ROOT/zellij/config.kdl" "$HJ_DEST/zellij/template.kdl" zellij-template
copy_asset "$ROOT/shell/ui-setup.sh" "$HJ_DEST/ui-setup.sh" ui-setup
copy_asset "$ROOT/shell/restart-ghostty.sh" "$HJ_DEST/restart-ghostty.sh" ghostty-restart
copy_asset "$ROOT/ghostty/themes/hack-jitsu" "$GHOSTTY_DEST/themes/hack-jitsu" ghostty-theme
copy_asset "$ROOT/ghostty/shaders/hack-jitsu-cursor.glsl" "$GHOSTTY_DEST/shaders/hack-jitsu-cursor.glsl" ghostty-shader
copy_asset "$ROOT/ghostty/hack-jitsu-watermark.png" "$GHOSTTY_DEST/hack-jitsu-watermark.png" ghostty-watermark
copy_asset "$ROOT/shell/hj.zsh" "$HJ_DEST/shell.zsh" hj-shell
copy_asset "$ROOT/shell/hj-completion.zsh" "$HJ_DEST/completion.zsh" hj-completion
copy_asset "$ROOT/shell/hj-logo.txt" "$HJ_DEST/logo.txt" hj-logo
if [ "$DRY_RUN" -eq 1 ]; then
  echo "PLAN generate private Ghostty title and user-selected Zellij status bar"
else
  if [ "$SETUP_UI" -eq 1 ]; then
    if [ -t 0 ] && [ -t 1 ]; then
      bash "$HJ_DEST/ui-setup.sh"
    else
      echo "ERROR: --setup needs a terminal; run hjsetup after Ghostty starts." >&2
      exit 2
    fi
  else
    bash "$HJ_DEST/ui-setup.sh" --apply
  fi
fi

for file in "$ROOT"/cheats/*.cheat; do
  [ -f "$file" ] || continue
  copy_asset "$file" "$HJ_DEST/cheats/$(basename "$file")" "cheat-$(basename "$file")"
done

# Dedicated Ghostty Zsh is always provisioned even with --no-shell.
copy_asset "$ROOT/shell/isolated.zshrc" "$HJ_DEST/zsh/.zshrc" isolated-zshrc

# Upgrade from earlier releases: undo ONLY the exact fragment we previously
# appended to ~/.zshrc. Back it up. Leave all unrelated lines unchanged.
RC="$HOME/.zshrc"
if [ -f "$RC" ] && [ ! -L "$RC" ] &&
   grep -Fq '# >>> Ghostty Hack-Jitsu Edition >>>' "$RC"; then
  previous_block=$(cat <<'LEGACY'
# >>> Ghostty Hack-Jitsu Edition >>>
if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/shell.zsh" ]; then
  source "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty-hackjitsu/shell.zsh"
fi
# <<< Ghostty Hack-Jitsu Edition <<<
LEGACY
)
  if [[ $(cat "$RC") == *"$previous_block"* ]]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "PLAN remove old Hack-Jitsu block from ~/.zshrc (after backing up)"
    else
      mkdir -p "$BACKUP"
      cp -p "$RC" "$BACKUP/zshrc-before-hackjitsu-migration"
      temp_rc="$(mktemp "${RC}.hj.XXXXXX")"
      awk '
        /^# >>> Ghostty Hack-Jitsu Edition >>>$/ { skip=1; next }
        /^# <<< Ghostty Hack-Jitsu Edition <<<$/{ skip=0; next }
        !skip { print }
      ' "$RC" > "$temp_rc"
      chmod "$(stat -f %Lp "$RC")" "$temp_rc" 2>/dev/null || chmod 600 "$temp_rc"
      mv "$temp_rc" "$RC"
      echo "MIGRATED old Hack-Jitsu ~/.zshrc block; original backed up"
    fi
  else
    echo "WARNING: Custom Hack-Jitsu block in ~/.zshrc: leaving untouched. Remove manually." >&2
  fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "DRY RUN COMPLETE: no applications, settings, or files were changed."
  echo "Run ./install.sh to install and restart Ghostty automatically."
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
if [ "$QUIT_GHOSTTY" -eq 0 ]; then
  echo " AFTER INSTALLATION: Ghostty stays running; no restart requested."
elif [ "$RELAUNCH_GHOSTTY" -eq 0 ]; then
  echo " AFTER INSTALLATION: Ghostty will close without relaunching."
else
  echo " AFTER INSTALLATION: Ghostty will close, then restart automatically."
fi
echo " Save active terminal jobs before any full restart."
echo " Press Option (Alt) + Tab to show/hide the dropdown after relaunch."
echo " If the shortcut fails, grant Ghostty access in:"
echo "      System Settings > Privacy & Security > Accessibility"
echo
echo " IN YOUR TERMINAL"
echo "   hj       Show Hack-Jitsu quick-start guide"
echo "   hjhelp   Search interactive pentest/admin/network cheats"
echo "   hjfetch  Show HACK JITSU system dashboard"
echo "   ls/ll    Colorful file listings with Nerd Font icons"
echo "   Tab      Fuzzy completion menu with argument descriptions"
echo "   Zellij   Starts in a fresh shell session"
echo "   hjsetup  Configure title, Zellij bar and Mac Option key"
echo "   hjkeys   Show Mac-oriented Zellij shortcuts"
echo "   wave     Manually reattach an older Zellij session"
if [ "$NO_NVIM" -eq 0 ]; then
  echo "   nvim     Start LazyVim (plugins prepared by installer when online)"
else
  echo "   nvim     Skipped during installation (--no-nvim)"
fi
echo
echo " DIAGNOSTICS"
echo "   ./install.sh --check    Read-only validation"
echo "   ./install.sh --dry-run  Preview changes"
echo "   Re-run ./install.sh safely: existing packages are skipped."
echo "   After installation Ghostty runs in the background (headless dropdown)."
echo "   Use --no-quit to keep the current app/sessions running."
echo "   Use --no-relaunch to close the app without restarting."
echo "   Isolated Zsh: your existing ~/.zshrc is not loaded in Ghostty."
echo "   Disable auto Zellij: touch ~/.config/ghostty-hackjitsu/zsh/no-auto-zellij"
echo "============================================================"

if [ "$verify_status" -ne 0 ]; then
  echo "ERROR: Some installation checks failed. Review [FAIL] above." >&2
  echo "       Ghostty will still be restarted to use the newly installed profile." >&2
  echo "       Fix those items and rerun ./install.sh --check." >&2
fi

# Ghostty geometry and macOS accessory-app settings require a true app
# restart, not config reload. The helper waits for process exit before open.
# --check and --dry-run already returned before reaching this block.
if [ "$QUIT_GHOSTTY" -eq 0 ]; then
  status INFO "--no-quit: Ghostty left running. No restart attempted."
else
  restart_args=()
  if [ "$RELAUNCH_GHOSTTY" -eq 0 ]; then
    restart_args+=(--no-relaunch)
    status INFO "--no-relaunch: Ghostty will stop without reopening."
  fi
  if [ "${TERM_PROGRAM:-}" = ghostty ]; then
    # Ghostty's subprocess cannot synchronously kill its hosting app.
    # Let a detached helper wait and restart after this shell disappears.
    HJ_RESTART_LOG="$STATE_HOME/ghostty-hackjitsu/restart.log"
    ( umask 077; mkdir -p -m 700 "$(dirname "$HJ_RESTART_LOG")" )
    if [ -L "$HJ_RESTART_LOG" ]; then
      status FAIL "Refusing symlinked restart log: $HJ_RESTART_LOG" >&2
      exit 2
    fi
    ( umask 077; : > "$HJ_RESTART_LOG" )
    chmod 600 "$HJ_RESTART_LOG"
    status INFO "Scheduling Ghostty shutdown after this installer exits..."
    status INFO "Restart status: $HJ_RESTART_LOG"
    nohup /bin/bash "$HJ_DEST/restart-ghostty.sh" --deferred "${restart_args[@]}" >"$HJ_RESTART_LOG" 2>&1 </dev/null &
    status PASS "Restart helper started; Ghostty will close and restart unless --no-relaunch was used."
  else
    bash "$HJ_DEST/restart-ghostty.sh" --foreground "${restart_args[@]}"
  fi
fi

exit "$verify_status"
