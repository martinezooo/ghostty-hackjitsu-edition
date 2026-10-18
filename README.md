# Ghostty Hack-Jitsu Edition

A portable macOS terminal profile: Ghostty dropdown, Hack-Jitsu theme and watermark, animated cursor, Zellij sessions, Neovim + LazyVim, and a self-contained command cheat library. No personal shell history, SSH inventory, local machine settings, or credentials are included.

## Install

Homebrew is required (https://brew.sh). Clone this repository on the Mac where you want to use it:

```bash
git clone https://github.com/martinezooo/ghostty-hackjitsu-edition.git
cd ghostty-hackjitsu-edition
./install.sh --dry-run
./install.sh            # installs, verifies, and completely quits Ghostty
./install.sh --check    # checks without any changes or quitting Ghostty
```

The installer **skips components that are already installed** (Ghostty app, Nerd Font, or existing Homebrew formulas / CLI executables). Otherwise it uses Homebrew to install Ghostty, JetBrains Mono Nerd Font, Navi, fzf, Zellij, Neovim, lazygit, ripgrep, fd, and tree-sitter-cli. Ghostty is configured to use the actual font family `JetBrainsMono Nerd Font Mono`; using the font's package name as its family name can silently fall back to the bundled font. Existing files are backed up under `~/.local/state/ghostty-hackjitsu/backups/` before replacement. It never replaces the entire shell or SSH configuration.

Optional flags: `--check` (read-only verification built into `install.sh`), `--strict` (warnings fail verification), `--no-brew` (configuration only), `--no-shell` (skip optional Zsh plugins; isolated Zsh is still installed), `--no-nvim` (do not install Neovim/LazyVim), `--tools` (nmap, jq, ripgrep, yq), and `--dry-run` (no changes).

**Administrator permissions:** The installer uses regular Homebrew operations for an admin account, including `sudo` if Homebrew needs it. On a non-admin account it disables Homebrew sudo requests and, when Ghostty is missing, targets `~/Applications`; formula installation still requires a writable Homebrew prefix. If you receive `not in the sudoers file` or a prefix-permissions error, your company's IT team must provision the required rights or software. Do **not** run `sudo brew install` or modify the sudoers file. You may explicitly select `--user` or `--system` (the latter requires an admin account). Follow your company's software installation policy.

## Post-install verification

A built-in diagnostic runs automatically at the end of a normal installation and displays `[PASS]`, `[WARN]` and `[FAIL]` results for applications, CLI tools, fonts, configuration, shortcuts and cheat sheets. Run `./install.sh --check` at any time to verify the machine **without changing anything**; it returns exit code 1 for missing required components. Use `./install.sh --check --strict` to also fail on warnings. The first Neovim startup downloads LazyVim plugins, so an initial warning about uninitialized plugins is expected until you start `nvim` once.

## First launch and clean shutdown

**On every successful installation or reinstall, Ghostty is shut down completely and is NOT relaunched.** The installer prints a Quick Start summary before quitting. Existing Ghostty tabs/shell sessions will close; save your work first. From another terminal, it requests a normal macOS quit, then sends SIGTERM only if the app remains running. From inside Ghostty, the quit is deferred briefly until the installer finishes printing.

When you later want the dropdown, manually start Ghostty **once** using `open -a Ghostty` or from Applications. Its intended settings (`macos-hidden = always`, `initial-window = false`, `window-save-state = never`) hide the Dock icon and normal window. Once the app is running, use **Option + Tab**. The shortcut cannot work while Ghostty is fully shut down. If a standard window or Dock icon still appears, run `./install.sh --check` to inspect the **effective configuration**: files in `~/Library/Application Support/com.mitchellh.ghostty/` can override our XDG settings.

The installer provides `--no-quit` to preserve active sessions when deliberately needed; `--dry-run` and `--check` never close Ghostty. The old `--launch` and `--restart` flags are removed because they caused unwanted windows/restarts.

## Hack-Jitsu shell prompt

Inside **local Ghostty Zsh sessions**, our isolated shell integration now themes the **prompt** as well as Ghostty itself: red username and prompt arrow, grey hostname, white working directory, and red Git branch (when present). Typing commands is highlighted in cyan, unknown commands in red, command-line options in yellow, and file paths in underlined cyan. Optional history suggestions appear in grey. The installer installs `zsh-syntax-highlighting` and `zsh-autosuggestions` when absent; both are automatically loaded from Homebrew. No private hostnames or usernames are committed, and Terminal.app, SSH and noninteractive shells are unchanged. Open a **new Ghostty shell** after updating; its standalone Zsh profile loads everything automatically.

## Isolated Zsh (no personal `~/.zshrc`)

Ghostty launches `/bin/zsh` with `ZDOTDIR` set to `~/.config/ghostty-hackjitsu/zsh`. Its own `.zshrc` loads the bundled `shell.zsh`, not the user's `~/.zshrc`. This eliminates conflicts with personal hooks such as an auto-starting `tmux` that may be missing on the work computer. Terminal.app, login scripts, and remote SSH accounts are unchanged. System-wide `/etc/zsh*` scripts are still read normally.

Upgrades remove **only** the exact old Hack-Jitsu hook we used to append to personal `~/.zshrc`, after backing it up. Other lines are preserved. For a custom-modified hook, the installer warns and leaves it alone. Running the installer again is safe.

**SSH + tmux:** Ghostty's manually loaded shell integration enables `ssh-env`, which uses an `xterm-256color` fallback for SSH hosts that lack Ghostty terminfo; it doesn't globally downgrade Ghostty. If already on a remote server and tmux says 'missing or unsuitable terminal: xterm-ghostty', run `TERM=xterm-256color tmux attach` once and reconnect later. See [Ghostty SSH docs](https://ghostty.org/docs/features/ssh).

## Persistent command history

Ghostty's isolated Zsh no longer depends on your personal `~/.zshrc`, but it **reuses your existing command history** when a readable/writable `~/.zsh_history` exists. New commands go to the same file, and Zsh shares recent commands across shells (`SHARE_HISTORY`). If the Mac has no existing history file, Hack-Jitsu creates a private `~/.local/state/ghostty-hackjitsu/zsh_history` with 0600 permissions. History keeps up to 50,000 entries and skips commands prefixed with a space.

History files are **never included in the repository** or copied to other machines. Commands that were never written to disk by earlier broken sessions cannot be recovered automatically. In Ghostty, press Up or use `history 20` to browse commands.

## Default Zellij workspace

When you open the **local Ghostty dropdown**, its isolated Zsh profile automatically attaches to the persistent Zellij session named `hackjitsu`. You can use Zellij tabs and panes immediately; no `wave`, tmux or additional terminal setup is required. `wave` remains as an optional compatibility command to reattach after leaving the session. There is **no auto-launch over SSH, inside another Zellij/tmux session, or in noninteractive shells**.

To temporarily disable automatic Zellij startup for your user, run `touch ~/.config/ghostty-hackjitsu/zsh/no-auto-zellij` and open a new Ghostty shell. Remove that file to re-enable the default behavior. Missing Zellij falls back to ordinary Zsh with a warning instead of breaking the terminal.

## Keyboard and commands

| Shortcut / command | Action |
|---|---|
| Option + Tab | Show / hide the top dropdown |
| Cmd + T | New tab |
| Cmd + Shift + D | Vertical split |
| Cmd + Shift + Enter | Horizontal split |
| Cmd + Shift + , | Reload Ghostty configuration |
| `hjhelp` | Open Navi with the bundled cheats only |
| `hj` | Print Hack-Jitsu greeting |
| `wave` | Reattach to the default Zellij session after leaving it |

The dropdown uses **55% of the selected display height and 85% of its width**, rather than the previous hard-coded 1728px width that overflowed smaller monitors. Ghostty chooses the display under your mouse (`quick-terminal-screen = mouse`). Option + Tab requires Ghostty to be running and macOS Accessibility permission; conflicts with other global shortcuts are possible.

## Cheats

Plain `.cheat` files are browsed with `hjhelp`. Categories: pentest, network/macos, admin/ssh/docker/proxmox, Android/ADB, and terminal. Entries are templates with placeholders. Some commands require extra tools (e.g. ffuf, sqlmap, netexec, adb, scrcpy) that are **not** installed automatically.

Pentesting examples are intended for systems you are authorized to assess. Nothing runs until you choose a command and supply a target.

## Neovim + LazyVim

The `nvim/` directory contains a portable starter configuration based on the official [LazyVim starter](https://github.com/LazyVim/starter) (Apache-2.0; license in `nvim/LICENSE`). The installer copies it to `~/.config/nvim` **only when that path does not already exist**. Existing editor configurations (including symlinks) are left untouched; use `--no-nvim` to skip this feature entirely.

Run `nvim` after installation. On first launch, `lazy.nvim` downloads LazyVim and its plugins from GitHub, so network access is required. Use `:LazyHealth` to verify your setup, `:Lazy` for plugin management and `:LazyExtras` to activate optional language modules. LazyVim currently requires Neovim 0.11.2+, Git, curl, a C compiler, and tree-sitter-cli; the installed Nerd Font, fzf, fd, ripgrep and lazygit improve the experience. If your Mac does not have Xcode Command Line Tools, install them via your company-approved method.

Quick start: `nvim .` opens the current project, `Space ff` finds files, and `Space /` searches text (LazyVim defaults). Configuration can be changed in `~/.config/nvim/lua/config/` without touching the repository source. The installer **does not update an existing `~/.config/nvim`**: to deploy later changes to the starter, review and merge them manually (do not delete your working editor configuration).

## Changes and reinstallation

The installer copies files, not symlinks. Make changes in this repository and rerun `./install.sh --no-brew` to deploy them. It leaves unrelated personal files intact and does not modify `~/.ssh/config`, Git identity or existing Neovim profiles. On upgrade from older versions, the installer backs up `~/.zshrc` and removes only the exact Hack-Jitsu block it previously inserted. No background synchronization or automatic package upgrades.

Run `bash tests/test-install.sh`, `bash tests/test-check.sh` and `bash tests/test-packages.sh`, `bash tests/test-shell.sh`, `bash tests/test-isolated-zsh.sh`, `bash tests/test-history.sh`, and `bash tests/test-launch.sh` to verify dry runs, backups, package detection, embedded diagnostics and idempotency. Run `bash tests/test-ghostty.sh` on a Mac with Ghostty installed to validate the isolated Ghostty configuration, shortcuts and effective font. Run `bash tests/test-nvim.sh` after dependencies are installed to download plugins in a temporary directory and detect LazyVim errors that might be hidden behind a successful Neovim exit code. That optional test requires GitHub access, skips if `nvim` or `tree-sitter` is unavailable, and leaves existing Neovim data untouched. Ghostty may also load `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` or `config` *after* the XDG configuration, so the installer warns about either file but deliberately does not alter it. The source tree is also checked for personal identifiers. No installation is performed on your current Mac by creating this repository.
