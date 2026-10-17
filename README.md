# Ghostty Hack-Jitsu Edition

A portable macOS terminal profile: Ghostty dropdown, Hack-Jitsu theme and watermark, animated cursor, Zellij sessions, Neovim + LazyVim, and a self-contained command cheat library. No personal shell history, SSH inventory, local machine settings, or credentials are included.

## Install

Homebrew is required (https://brew.sh). Clone this repository on the Mac where you want to use it:

```bash
git clone https://github.com/martinezooo/ghostty-hackjitsu-edition.git
cd ghostty-hackjitsu-edition
./install.sh --dry-run
./install.sh
./install.sh --check
```

The installer **skips components that are already installed** (Ghostty app, Nerd Font, or existing Homebrew formulas / CLI executables). Otherwise it uses Homebrew to install Ghostty, JetBrains Mono Nerd Font, Navi, fzf, Zellij, Neovim, lazygit, ripgrep, fd, and tree-sitter-cli. Ghostty is configured to use the actual font family `JetBrainsMono Nerd Font Mono`; using the font's package name as its family name can silently fall back to the bundled font. Existing files are backed up under `~/.local/state/ghostty-hackjitsu/backups/` before replacement. It never replaces the entire shell or SSH configuration.

Optional flags: `--check` (read-only verification built into `install.sh`), `--strict` (warnings fail verification), `--no-brew` (configuration only), `--no-shell` (do not append to `~/.zshrc`), `--no-nvim` (do not install Neovim/LazyVim), `--tools` (nmap, jq, ripgrep, yq), and `--dry-run` (no changes).

**Administrator permissions:** The installer uses regular Homebrew operations for an admin account, including `sudo` if Homebrew needs it. On a non-admin account it disables Homebrew sudo requests and, when Ghostty is missing, targets `~/Applications`; formula installation still requires a writable Homebrew prefix. If you receive `not in the sudoers file` or a prefix-permissions error, your company's IT team must provision the required rights or software. Do **not** run `sudo brew install` or modify the sudoers file. You may explicitly select `--user` or `--system` (the latter requires an admin account). Follow your company's software installation policy.

## Post-install verification

A built-in diagnostic runs automatically at the end of a normal installation and displays `[PASS]`, `[WARN]` and `[FAIL]` results for applications, CLI tools, fonts, configuration, shortcuts and cheat sheets. Run `./install.sh --check` at any time to verify the machine **without changing anything**; it returns exit code 1 for missing required components. Use `./install.sh --check --strict` to also fail on warnings. The first Neovim startup downloads LazyVim plugins, so an initial warning about uninitialized plugins is expected until you start `nvim` once.

## Keyboard and commands

| Shortcut / command | Action |
|---|---|
| Option + Tab | Show / hide the top dropdown |
| Cmd + T | New tab |
| Cmd + Shift + D | Vertical split |
| Cmd + Shift + Enter | Horizontal split |
| Cmd + Shift + , | Reload Ghostty configuration |
| Cmd + Shift + G | Open `wave` Zellij session |
| `hjhelp` | Open Navi with the bundled cheats only |
| `hj` | Print Hack-Jitsu greeting |
| `wave` | Attach/start a Zellij session |

The copied Ghostty config retains the original dropdown size (400px high, up to 1728px wide). Adjust `quick-terminal-size` locally for your display. Global Option + Tab may conflict with other shortcuts.

## Cheats

Plain `.cheat` files are browsed with `hjhelp`. Categories: pentest, network/macos, admin/ssh/docker/proxmox, Android/ADB, and terminal. Entries are templates with placeholders. Some commands require extra tools (e.g. ffuf, sqlmap, netexec, adb, scrcpy) that are **not** installed automatically.

Pentesting examples are intended for systems you are authorized to assess. Nothing runs until you choose a command and supply a target.

## Neovim + LazyVim

The `nvim/` directory contains a portable starter configuration based on the official [LazyVim starter](https://github.com/LazyVim/starter) (Apache-2.0; license in `nvim/LICENSE`). The installer copies it to `~/.config/nvim` **only when that path does not already exist**. Existing editor configurations (including symlinks) are left untouched; use `--no-nvim` to skip this feature entirely.

Run `nvim` after installation. On first launch, `lazy.nvim` downloads LazyVim and its plugins from GitHub, so network access is required. Use `:LazyHealth` to verify your setup, `:Lazy` for plugin management and `:LazyExtras` to activate optional language modules. LazyVim currently requires Neovim 0.11.2+, Git, curl, a C compiler, and tree-sitter-cli; the installed Nerd Font, fzf, fd, ripgrep and lazygit improve the experience. If your Mac does not have Xcode Command Line Tools, install them via your company-approved method.

Quick start: `nvim .` opens the current project, `Space ff` finds files, and `Space /` searches text (LazyVim defaults). Configuration can be changed in `~/.config/nvim/lua/config/` without touching the repository source. The installer **does not update an existing `~/.config/nvim`**: to deploy later changes to the starter, review and merge them manually (do not delete your working editor configuration).

## Changes and reinstallation

The installer copies files, not symlinks. Make changes in this repository and rerun `./install.sh --no-brew` to deploy them. It leaves unrelated personal files intact and does not modify `~/.ssh/config`, Git identity or existing Neovim profiles. No background synchronization or automatic package upgrades.

Run `bash tests/test-install.sh`, `bash tests/test-check.sh` and `bash tests/test-packages.sh` to verify dry runs, backups, package detection, embedded diagnostics and idempotency. Run `bash tests/test-ghostty.sh` on a Mac with Ghostty installed to validate the isolated Ghostty configuration, shortcuts and effective font. Run `bash tests/test-nvim.sh` after dependencies are installed to download plugins in a temporary directory and detect LazyVim errors that might be hidden behind a successful Neovim exit code. That optional test requires GitHub access, skips if `nvim` or `tree-sitter` is unavailable, and leaves existing Neovim data untouched. Ghostty may also load `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` or `config` *after* the XDG configuration, so the installer warns about either file but deliberately does not alter it. The source tree is also checked for personal identifiers. No installation is performed on your current Mac by creating this repository.
