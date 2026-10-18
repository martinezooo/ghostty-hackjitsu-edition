# Ghostty Hack-Jitsu Edition

A portable macOS terminal profile: Ghostty dropdown, Hack-Jitsu theme and watermark, animated cursor, Zellij sessions, Neovim + LazyVim, and a self-contained command cheat library. No personal shell history, SSH inventory, local machine settings, or credentials are included.

## Install

Homebrew is required (https://brew.sh). Clone this repository on the Mac where you want to use it:

```bash
git clone https://github.com/martinezooo/ghostty-hackjitsu-edition.git
cd ghostty-hackjitsu-edition
./install.sh --dry-run
./install.sh            # installs, verifies and automatically restarts Ghostty
./install.sh --check    # checks without any changes or quitting Ghostty
```

The installer **skips components that are already installed** (Ghostty app, Nerd Font, or existing Homebrew formulas / CLI executables). Otherwise it uses Homebrew to install Ghostty, JetBrains Mono Nerd Font, Navi, fzf, Zellij, Powerlevel10k, Neovim, lazygit, ripgrep, fd, and tree-sitter-cli. Ghostty is configured to use the actual font family `JetBrainsMono Nerd Font Mono`; using the font's package name as its family name can silently fall back to the bundled font. Existing files are backed up under `~/.local/state/ghostty-hackjitsu/backups/` before replacement. It never replaces the entire shell or SSH configuration.

Optional flags: `--check` (read-only verification built into `install.sh`), `--strict` (warnings fail verification), `--no-brew` (configuration only), `--no-shell` (skip optional Zsh plugins; isolated Zsh is still installed), `--no-nvim` (do not install Neovim/LazyVim), `--no-lazy-sync` (defer plugin download), `--no-relaunch` (stop without reopening), `--no-quit` (preserve live sessions), `--tools` (nmap, jq, ripgrep, yq), and `--dry-run` (no changes).

**Administrator permissions:** The installer uses regular Homebrew operations for an admin account, including `sudo` if Homebrew needs it. On a non-admin account it disables Homebrew sudo requests and, when Ghostty is missing, targets `~/Applications`; formula installation still requires a writable Homebrew prefix. If you receive `not in the sudoers file` or a prefix-permissions error, your company's IT team must provision the required rights or software. Do **not** run `sudo brew install` or modify the sudoers file. You may explicitly select `--user` or `--system` (the latter requires an admin account). Follow your company's software installation policy.

## Post-install verification

A built-in diagnostic runs automatically and displays colored `[PASS]` (green), `[WARN]` (yellow) and `[FAIL]` (red) results. Installation progress is colored too: `COPY` green, `SKIP` yellow, `INSTALL` blue. Colors appear in interactive terminals; redirected logs stay plain. Use `NO_COLOR=1` or `HJ_INSTALL_COLOR=never` to suppress ANSI; `HJ_INSTALL_COLOR=always` forces ANSI for tests. Run `./install.sh --check` at any time to verify the machine **without changing anything**; it returns exit code 1 for missing required components. Use `./install.sh --check --strict` to also fail on warnings. The installer prepares LazyVim in a headless session, **waits until Tree-sitter parsers are compiled**, and checks that the Lua parser loads. Simply downloading plugin folders no longer counts as successful initialization. A warning now points to the private diagnostics file at `~/.local/state/ghostty-hackjitsu/nvim-bootstrap.log`; missing compilers and network failures are displayed rather than silently ignored.

## Automatic restart and first launch

A normal installation now **restarts Ghostty automatically**. The installer
uses SIGTERM rather than AppleScript to avoid the macOS
"Quit Ghostty / Cancel" modal, **waits for the previous process to exit**
(up to 10 seconds), then pauses one second before `open -a Ghostty`.
A failed shutdown aborts the relaunch instead of opening a second instance.
Successful launch is verified by detecting the new Ghostty process.

If the installer runs **inside Ghostty**, it starts a detached helper that
waits for setup to finish before closing and relaunching its parent app.
Read its result at `~/.local/state/ghostty-hackjitsu/restart.log`.
From an ordinary terminal, the helper runs in the foreground and prints
status lines.

**Save active Ghostty terminal jobs before installing.** A full restart
closes Ghostty tabs and shell processes. Historical Zellij sessions and Zsh
history are not deleted. Ghostty is a headless dropdown profile
(`macos-hidden = always`, `initial-window = false`),
so the app can be **running without a visible window**. After it
reopens, press **Option+Tab** to show the dropdown. If necessary, enable
Ghostty under System Settings > Privacy & Security > Accessibility.

Safety options: `--no-quit` skips closing/relaunching the running
app (new settings apply only after a later restart). `--no-relaunch`
closes the app but leaves it stopped. `--dry-run` and `--check`
never close or start Ghostty. Obsolete `--launch` and `--restart`
flags remain unsupported: the controlled restart is now the default.

## Preview-first setup: Powerlevel10k, Ghostty and Zellij

A normal install provisions the standalone Hack-Jitsu profile **without
running any interactive wizard** and keeps the existing minimal red prompt.
For the guided experience seen in `p10k configure`, run the installer
**from a real terminal** with `--setup`:

```bash
./install.sh --setup --no-quit
```

1. **Powerlevel10k**: the original `p10k configure` wizard shows real
   prompt variants. It runs in a **disposable isolated `ZDOTDIR`** and
   saves only the generated config to
   `~/.config/ghostty-hackjitsu/zsh/.p10k.zsh`. Never edits your
   personal `~/.zshrc` or `~/.p10k.zsh`.
2. **Hack-Jitsu previews**: the second wizard follows Powerlevel10k's
   *actual interaction pattern* rather than decorative cards. One screen
   shows all numbered choices and rendered terminal examples. Select with
   **one key, no Enter**; the next question appears immediately. Screens
   adapt to terminal size and redraw on resize. Use `r` to restart,
   `b` to return to the previous question and `q` to quit
   **without saving**. Only an optional custom title requires Enter.
   It covers Ghostty colors, Zellij classic/compact bar, font, opacity,
   Mac Option and window title. At the final summary, **press 1 to save**.

   Presentation/controls are based on Powerlevel10k's
   [MIT-licensed wizard source](https://github.com/romkatv/powerlevel10k/blob/master/internal/wizard.zsh):
   stacked numbered prompts, key-by-key input, screen-size-aware fallbacks,
   and restart/abort. Zellij examples are terminal-rendered illustrations,
   not screenshots. ANSI also cannot change actual Ghostty font pixels or
   macOS transparency; these appear after application. Use `p`
   at the theme stage for Ghostty's native `+list-themes` preview.

**Configuration locations and single source of truth:**

| Path | Purpose |
|---|---|
| `~/.config/ghostty-hackjitsu/ui.conf` | **Canonical** title, Zellij bar, theme, font, opacity and Option mapping (0600). |
| `~/.config/ghostty/config` | Generated from `ui.conf` + Ghostty template; do not edit independently. |
| `~/.config/ghostty-hackjitsu/zellij/config.kdl` | Generated from the same `ui.conf` + Zellij template. |
| `~/.config/ghostty-hackjitsu/zsh/.p10k.zsh` | P10K's independent prompt data; it is not a duplicate of UI preferences. |
| `~/.config/ghostty-hackjitsu/zsh/enable-p10k` | Marker enabling P10K only after successful configuration. |

The installer creates a default `ui.conf` on first installation.
Subsequent installations read it, and `hjsetup --apply` regenerates
Ghostty and Zellij from those same values. No separate copies of
preferences are maintained in the repository. The wizard keeps a draft
in memory until its final confirmation. Configs are validated by
Ghostty and Zellij **before saving**; modified files receive unique
backups and any detected write failure is rolled back. If the
process is forcibly killed mid-write, rerun `hjsetup --apply` to restore
all derived files from the authoritative `ui.conf`.
Your personal `~/.zshrc` and `~/.p10k.zsh` are untouched.

```bash
hjsetup                         # seven-page P10K-style visual wizard
hjsetup --preview               # read-only example gallery
hjsetup --all                   # run P10K first, then Hack-Jitsu
hjp10k                          # P10K only
hjsetup --show                  # show saved canonical settings
hjsetup --apply                 # regenerate both outputs from ui.conf
hjsetup --bar compact --theme TokyoNight --font 16 --opacity 0.8
```


Powerlevel10k is now an **optional installed dependency** (`brew install
powerlevel10k` with the standard installer). It is **enabled only after
successfully completing its wizard**, preserving the current prompt for
users who don't want it. The public repository includes no personal P10K
configuration. To restore the original Hack-Jitsu prompt, remove the
private `~/.config/ghostty-hackjitsu/zsh/enable-p10k` marker.

### Red Hack-Jitsu app icon

The bundled 1024×1024 RGBA icon is derived from the user-supplied red
Hack-Jitsu Ghostty artwork, with symmetric inset and **transparent**
corners (no surrounding black/white square). Ghostty itself supports
this natively: the generated local config uses `macos-icon = custom`
and an absolute `macos-custom-icon` path under
`~/.config/ghostty/`. **We do not modify the signed Ghostty.app
bundle**, so macOS updates remain safe.

Per the [official Ghostty documentation](https://ghostty.org/docs/config/reference),
the custom icon affects the running app icon (Dock/app switcher), **not
the Finder icon for the Ghostty.app bundle**. The Hack-Jitsu dropdown
deliberately uses `macos-hidden = always`, so you won't normally
see its icon in the Dock; this preserves the existing Option+Tab workflow.
The icon asset is nevertheless installed and configured.

Ghostty's built-in Zellij status bar uses the label `Alt`, which
means `⌥ Option` on Mac. The default maps **left Option as Alt**
while preserving right Option for Polish characters. Use `hjkeys`
for the Mac-oriented shortcut reference. Changing the Zellij bar
requires starting a **new Zellij session**; existing sessions are
never overwritten. Current settings are stored locally in
`~/.config/ghostty-hackjitsu/ui.conf` (mode 0600) and preserved
across reinstalls.


## Rich shell experience (matching the private Mac terminal)

The isolated Hack-Jitsu Zsh profile installs **eza**, **fastfetch**, **fzf-tab**, and **zsh-completions** via Homebrew if missing. `ls` becomes a colorful icon-based listing, with `ll` (details), `la` (all files) and `lt` (tree). `command ls` bypasses the alias.

**Tab** uses the Zsh completion system for **all commands with available completions** (including `git`, `ssh`, `rsync`, `nmap`, and installed tools like Docker or kubectl). `fzf-tab` supplies a fuzzy selection interface with option descriptions when installed. `ls` and related eza aliases explicitly reuse eza completions. For option menus, type a partial flag such as `git --<Tab>` or `ls -<Tab>`; after a fully formed flag like `ls -la<Tab>`, there may be nothing further to complete. Plugin order is deliberate: compinit, fzf-tab, autosuggestions, highlighting. `hjfetch` shows Fastfetch with the bundled HACK JITSU ASCII logo and live system information. The Fastfetch logo uses a red theme (rather than system defaults, which may be green). The shell prompt is a small **red `❯`**, without a forced pathname or Git branch; `pwd` and `git status` remain available when needed. The banner appears in sufficiently wide interactive sessions, and can be suppressed using `HJ_NO_BANNER=1`. Personal device information is never included in the public repo.

### ANSI log files in Neovim (automatic, non-destructive)

Hack-Jitsu Neovim **automatically hides ANSI SGR color codes** like a real Escape + `[31m`, serialized `\\x1b[31m`, or `\\u001b[31m` when opening a file that contains them. This removes the clutter from reading/editing logs, without deleting any bytes or modifying the file. No extra Neovim plugin or pre-conversion is needed.

- `:HJAnsiToggle` toggles whether the color codes are visible in the current buffer, without changing content.
- `:HJAnsiStrip` removes these **color sequences only** from the current buffer, then use `:w` to save (or `u` to undo). The original disk file stays unchanged until you explicitly save.
- General literal `\\xNN` values (e.g. `\\x41`, HTTP payload bytes or binary evidence) are **not** color escapes and are deliberately preserved.

This is enabled for **new and existing Hack-Jitsu-managed LazyVim configs**. The installer first backs up the managed `init.lua` and adds the small built-in module, but **never edits third-party Neovim profiles** or symlinked configurations. `--no-nvim` skips it.

### Neovim inside Zellij

**Every new Ghostty terminal starts a fresh Zellij session with an ordinary Zsh shell** instead of attaching to the last session. Auto-reattaching to `hackjitsu` or `hackjitsu-v2` previously brought back stale Neovim screens and even editor-only panes. New Zellij sessions are named after the macOS username (e.g. `martinezooo`) rather than displaying internal `hj-41648` identifiers in the tab bar/window title. If that name is already taken, the next new session gets a readable `martinezooo-2`, `martinezooo-3`, etc. It never attaches to a previously used name or resurrects old Neovim panes. The resulting names are short enough for macOS UNIX sockets; session serialization remains disabled. The private Zellij config also uses `on_force_close "quit"`: **when Ghostty actually closes**, its temporary session ends rather than accumulating detached sessions; **hiding** the dropdown does not trigger this. **Existing Zellij sessions are not deleted, killed or altered**; the old sessions can still be resumed deliberately by running `wave [session-name]` (or `zellij attach <session-name>`). The dropdown shortcut only shows/hides the running Ghostty process and keeps the current shell until Ghostty is restarted. When hiding a dropdown **while Neovim is open**, the editor stays open because Ghostty intentionally preserves its surface; to return to the shell you must exit Neovim normally. On a full restart, a different fresh session starts with Zsh.

**Neovim is no longer wrapped in `zellij edit --in-place`.** Typing `nvim filename` launches ordinary Neovim from the active shell. After `Esc`, `:q!`, Enter, the same shell prompt returns; quitting Neovim must not close the Zellij pane. New pane: **Ctrl+P**, then **N**. New tab: **Ctrl+T**, then **N**. Use `wave <session-name>` outside Zellij only when you intentionally want to resume an old session with its files/panes.

Fresh Hack-Jitsu installs download LazyVim and compile Tree-sitter grammars **before opening files**. We reproduced the previous `Failed to compile parser` and `ENOTEMPTY: Could not rename temp` errors: LazyVim's own background parser installation and our installer tried writing to the **same Tree-sitter cache folders simultaneously**. The managed profile now disables background grammar builds (plugin `build=false`, `ensure_installed={}`) and uses three separate Neovim sessions: sync plugins, compile the 23 required parsers, and verify all compiled parsers load in a **fresh Neovim process**. Plain `nvim plik.txt` should therefore no longer trigger competing parser installations. Additional languages can be installed with `:TSInstall <lang>`, and updated intentionally with `:TSUpdate`.

Requirements: `tree-sitter-cli >= 0.26.1`, working Clang/C compiler and internet access for first setup. Compile failures now show a warning, not false PASS, and the full local error log is stored in `~/.local/state/ghostty-hackjitsu/nvim-bootstrap.log` with permissions 0600. `--no-lazy-sync` intentionally skips this setup; `--check` only reads machine state. Unrelated personal Neovim configurations are never overwritten.

**Diagnose the actual Neovim from the Ghostty pane where it fails:**

```bash
hjdoctor nvim                    # Neovim config paths, parser and compiler diagnostics
hjdoctor nvim --file plik.txt    # reopen that file read-only and capture failures
hjdoctor nvim --repair           # explicit repair only for Hack-Jitsu-managed profiles
```

Before installing the shell helper, you can run `bash ~/ghostty-hackjitsu-edition/tools/nvim-doctor.sh`. It never clears parsers or caches and refuses repair of private Neovim configurations. Diagnostics remain local under `~/.local/state/ghostty-hackjitsu/nvim-doctor.*` (mode 0600). Inspect logs before sharing them: file paths and CLI output may contain private project data. The same Mac can run different Neovim profiles depending on its Ghostty/Zsh environment, so diagnosing the correct pane matters.


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

Opening the **local Ghostty dropdown** starts a **fresh Zellij session**
with a short unique name. It never reattaches an old editor automatically.
After leaving the current session, you may manually resume an old one using
`wave [session-name]`. No auto-launch over SSH, inside another
Zellij/tmux session, or in noninteractive shells.

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

The `nvim/` directory contains a portable starter configuration based on the official [LazyVim starter](https://github.com/LazyVim/starter) (Apache-2.0; license in `nvim/LICENSE`). The installer copies it to `~/.config/nvim` only when no profile exists. On upgrade it can add the built-in ANSI log viewer to an **existing Hack-Jitsu-managed profile** (after backing up its entrypoint), without replacing custom plugins. Unrelated third-party editor configurations and symlinks are left untouched; use `--no-nvim` to skip entirely.

Run `nvim` after installation. On first installation, the installer normally prepares LazyVim plugins from GitHub, so network access is required. If setup is skipped or fails, the first Neovim launch will download plugins. Use `:LazyHealth` to verify your setup, `:Lazy` for plugin management and `:LazyExtras` to activate optional language modules. LazyVim currently requires Neovim 0.11.2+, Git, curl, a C compiler, and tree-sitter-cli; the installed Nerd Font, fzf, fd, ripgrep and lazygit improve the experience. If your Mac does not have Xcode Command Line Tools, install them via your company-approved method.

Quick start: `nvim .` opens the current project, `Space ff` finds files, and `Space /` searches text (LazyVim defaults). Configuration can be changed in `~/.config/nvim/lua/config/` without touching the repository source. The installer **does not update an existing `~/.config/nvim`**: to deploy later changes to the starter, review and merge them manually (do not delete your working editor configuration).

## Changes and reinstallation

The installer copies files, not symlinks. Make changes in this repository and rerun `./install.sh --no-brew` to deploy them. It leaves unrelated personal files intact and does not modify `~/.ssh/config`, Git identity or existing Neovim profiles. On upgrade from older versions, the installer backs up `~/.zshrc` and removes only the exact Hack-Jitsu block it previously inserted. No background synchronization or automatic package upgrades.

Run `bash tests/test-install.sh`, `bash tests/test-check.sh` and `bash tests/test-packages.sh`, `bash tests/test-shell.sh`, `bash tests/test-isolated-zsh.sh`, `bash tests/test-history.sh`, `bash tests/test-shell-ux.sh`, `bash tests/test-ui-setup.sh`, `bash tests/test-zellij-runtime.sh`, and `bash tests/test-launch.sh` to verify dry runs, backups, package detection, embedded diagnostics and idempotency. Run `bash tests/test-ghostty.sh` on a Mac with Ghostty installed to validate the isolated Ghostty configuration, shortcuts and effective font. Run `bash tests/test-nvim.sh` after dependencies are installed to download plugins in a temporary directory and detect LazyVim errors that might be hidden behind a successful Neovim exit code. That optional test requires GitHub access, skips if `nvim` or `tree-sitter` is unavailable, and leaves existing Neovim data untouched. Ghostty may also load `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` or `config` *after* the XDG configuration, so the installer warns about either file but deliberately does not alter it. The source tree is also checked for personal identifiers. No installation is performed on your current Mac by creating this repository.
