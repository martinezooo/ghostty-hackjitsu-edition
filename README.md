# Ghostty Hack-Jitsu Edition

A portable macOS terminal profile: Ghostty dropdown, Hack-Jitsu theme and watermark, animated cursor, Zellij sessions, and a self-contained command cheat library. No personal shell history, SSH inventory, local machine settings, or credentials are included.

## Install

Homebrew is required (https://brew.sh). Clone this repository on the Mac where you want to use it:

```bash
git clone https://github.com/martinezooo/ghostty-hackjitsu-edition.git
cd ghostty-hackjitsu-edition
./install.sh --dry-run
./install.sh
```

The installer uses Homebrew to install Ghostty, JetBrains Mono Nerd Font, Navi, fzf, and Zellij. Existing files are backed up under `~/.local/state/ghostty-hackjitsu/backups/` before replacement. It never replaces the entire shell or SSH configuration.

Optional flags: `--no-brew` (configuration only), `--no-shell` (do not append to `~/.zshrc`), `--tools` (nmap, jq, ripgrep, yq), and `--dry-run` (no changes).

If your company manages application installations, check its software policy before using Homebrew.

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

## Changes and reinstallation

The installer copies files, not symlinks. Make changes in this repository and rerun `./install.sh --no-brew` to deploy them. It leaves unrelated personal files intact and does not modify `~/.ssh/config`, Git identity or existing tool profiles. No background synchronization or automatic package upgrades.

Run `bash tests/test-install.sh` to verify that dry-run is inert, backups work and installation is idempotent. The source tree is also checked for personal identifiers. No installation is performed on your current Mac by creating this repository.
