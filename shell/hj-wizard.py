#!/usr/bin/env python3
"""Ghostty Hack-Jitsu setup in the interaction style of Powerlevel10k.

Design inspiration: romkatv/powerlevel10k/internal/wizard.zsh (MIT).
Like P10K: a clean screen, several *rendered* examples per choice, single-key
selection, responsive resizing, q=quit and r=restart. Unlike a shell prompt,
font size and background opacity cannot be changed by ANSI sequences; these
are accurately described as post-apply settings, not fake "live" previews.

Only ui-setup.sh persists data. This wizard keeps a draft in memory and asks
for confirmation before passing all values in a single save operation.
"""
from __future__ import annotations

from copy import deepcopy
import getpass
import os
from pathlib import Path
import re
import select
import shutil
import signal
import subprocess
import sys
import termios
import time
import tty
import unicodedata

HOME = Path.home()
CONFIG_HOME = Path(os.getenv("XDG_CONFIG_HOME", str(HOME / ".config")))
PREF = CONFIG_HOME / "ghostty-hackjitsu" / "ui.conf"
SETUP = CONFIG_HOME / "ghostty-hackjitsu" / "ui-setup.sh"
COLOR = sys.stdout.isatty() and not os.getenv("NO_COLOR")
THEMES = {
    "hack-jitsu": ("Hack-Jitsu Red", (239, 53, 65), (255, 255, 255)),
    "TokyoNight": ("Tokyo Night", (122, 162, 247), (27, 30, 49)),
    "Catppuccin Frappe": ("Catppuccin Frappé", (202, 158, 230), (35, 38, 52)),
}
PAGES = ("theme", "bar", "font", "opacity", "option", "title", "save")
WINCH = False


def winch(_signum, _frame):
    global WINCH
    WINCH = True


def ansi(code: str, text: str) -> str:
    return f"\x1b[{code}m{text}\x1b[0m" if COLOR else text


def bold(text: str) -> str:
    return ansi("1", text)


def shade(text: str) -> str:
    return ansi("90", text)


def fg(text: str, rgb: tuple[int, int, int]) -> str:
    return ansi(f"38;2;{rgb[0]};{rgb[1]};{rgb[2]}", text)


def bg(text: str, rgb: tuple[int, int, int], foreground=(255, 255, 255)) -> str:
    if not COLOR:
        return text
    return (f"\x1b[48;2;{rgb[0]};{rgb[1]};{rgb[2]}m"
            f"\x1b[38;2;{foreground[0]};{foreground[1]};{foreground[2]}m"
            f"{text}\x1b[0m")


def text_width(s: str) -> int:
    clean = re.sub(r"\x1b\[[0-9;]*m", "", s)
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1
               for c in clean if unicodedata.category(c) not in ("Mn", "Me"))


def limit_line(s: str, width: int) -> str:
    # ANSI-aware cropping to avoid corrupting the terminal on narrow windows.
    tokens = re.findall(r"\x1b\[[0-9;]*m|.", s, re.DOTALL)
    out = []
    used = 0
    for token in tokens:
        if token.startswith("\x1b["):
            out.append(token)
            continue
        count = text_width(token)
        if used + count > width:
            break
        out.append(token)
        used += count
    return "".join(out) + ("\x1b[0m" if COLOR else "")


def centered(s: str, width: int) -> str:
    return " " * max(2, (min(width, 88) - text_width(s)) // 2) + bold(s)


def terminal_size() -> tuple[int, int]:
    columns, rows = shutil.get_terminal_size(fallback=(80, 24))
    return max(0, columns), max(0, rows)


def username() -> str:
    return os.environ.get("USER") or getpass.getuser()


def load_saved() -> dict[str, str]:
    values = {
        "title": username(), "bar": "classic", "option": "left",
        "theme": "hack-jitsu", "font": "14", "opacity": "0.9"
    }
    if PREF.is_symlink():
        raise ValueError("Refusing symlinked preferences file")
    if PREF.exists():
        if not PREF.is_file():
            raise ValueError("Preferences path is not a regular file")
        for line in PREF.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                raise ValueError("Malformed line in ui.conf")
            key, value = line.split("=", 1)
            if key not in values or not value:
                raise ValueError(f"Unknown or empty setting in ui.conf: {key}")
            values[key] = value
    if (values["theme"] not in THEMES
        or values["bar"] not in ("classic", "compact")
        or values["font"] not in ("12", "14", "16")
        or values["opacity"] not in ("1", "0.9", "0.8")
        or values["option"] not in ("left", "right", "both", "off")):
        raise ValueError("Saved ui.conf contains unsupported settings")
    return values


def theme_sample(name: str, compact: bool = False) -> list[str]:
    label, accent, dark = THEMES[name]
    if compact:
        return [fg("    ❯", accent) + " nvim audit.log   " +
                shade(" main • 3 files")]
    if name == "hack-jitsu":
        first = fg("    ╭─ ", accent) + fg("     ~/pentest     main", accent)
    elif name == "TokyoNight":
        first = fg("    ╭─ ", accent) + bg("   ~/pentest ", dark) + fg("    main", accent)
    else:
        first = fg("    ╭─ ", accent) + bg(" 󰣇  ~/pentest ", dark) + fg("    main", accent)
    return [first,
            fg("    ╰─ ❯ ", accent) + "nvim findings.md    " + shade("17:48  ✓")]


def zellij_sample(style: str, compact: bool = False) -> list[str]:
    if style == "classic":
        return ([shade("    [1]  zsh     [2]  nvim     [3] 󰃷 scan")]
                + ([ansi("30;47", "    Ctrl  LOCK  PANE  TAB  RESIZE  MOVE  SEARCH  QUIT")
                    ] if not compact else []))
    return [ansi("30;47", "    [1]  zsh    [2]  nvim    [3] scan  ⌥←  ⌥→")]


def page_data(name: str, cfg: dict[str, str], compact: bool):
    if name == "theme":
        return "Prompt Colors", "Choose the accent of the entire terminal.", [
            ("1", "Hack-Jitsu Red.", theme_sample("hack-jitsu", compact)),
            ("2", "Tokyo Night.", theme_sample("TokyoNight", compact)),
            ("3", "Catppuccin Frappé.", theme_sample("Catppuccin Frappe", compact)),
        ], ["(p)  Ghostty's native live theme browser."]
    if name == "bar":
        return "Zellij Status Bar", "Compare the status area below your terminal.", [
            ("1", "Classic. Full keyboard shortcuts.", zellij_sample("classic", compact)),
            ("2", "Compact. One line with tabs.", zellij_sample("compact", compact)),
        ], ["Note: the real plugin prints Alt; on Mac this is ⌥ Option."]
    if name == "font":
        return "Font Size", "Ghostty will apply this size to its rendered text.", [
            ("1", "12 pt. More lines on screen.", [shade("    Compact • fits long logs")]),
            ("2", "14 pt. Balanced.", [shade("    Recommended daily use")]),
            ("3", "16 pt. Easier to read.", [shade("    Larger, fewer lines")]),
        ], ["Font pixels cannot be changed inside a running terminal preview."]
    if name == "opacity":
        return "Background Opacity", "Choose how much of the desktop is visible behind Ghostty.", [
            ("1", "100%. Opaque.", [shade("    Maximum contrast")]),
            ("2", "90%. Subtle transparency.", [shade("    Mostly opaque, desktop faintly visible")]),
            ("3", "80%. More transparency.", [shade("    More of the desktop visible")]),
        ], ["True transparency is applied by Ghostty, not ANSI preview."]
    if name == "option":
        return "Mac Keyboard", "Zellij calls the macOS ⌥ Option key Alt.", [
            ("1", "Left ⌥ is Alt; right ⌥ types Polish letters.", [shade("    Recommended for Polish keyboard")]),
            ("2", "Both ⌥ keys work as Alt.", [shade("    Faster Zellij shortcuts, fewer symbols")]),
            ("3", "Right ⌥ is Alt; left types symbols.", [shade("    Alternate keyboard layout")]),
            ("4", "Option key behaves like regular macOS.", [shade("    Some Zellij Alt shortcuts may not work")]),
        ], ["⌃ Control+P,N → new pane   •   ⌃ Control+T,N → new tab"]
    if name == "title":
        return "Window Title", "Appears in place of zellij (hj-12345).", [
            ("1", f"Your macOS username: {username()}", [shade("    title = " + username())]),
            ("2", "Hack-Jitsu", [shade("    title = Hack-Jitsu")]),
            ("3", "Type your own title.", [shade("    1–48 ASCII letters, numbers, spaces, . _ -")]),
        ], ["A custom title is the only step that needs Enter."]
    if name == "save":
        return "Apply Your Choices", "Review everything before writing any settings.", [
            ("1", "Save selected settings.", [
                f"    Title: {cfg['title']}   Theme: {cfg['theme']}",
                f"    Zellij: {cfg['bar']}   Font: {cfg['font']} pt   Opacity: {cfg['opacity']}",
                f"    Option as Alt: {cfg['option']}",
            ])
        ], ["No changes are made until you press 1 here."]
    raise ValueError(name)


def render(page: str, cfg: dict[str, str], *, static: bool = False):
    cols, rows = terminal_size()
    width = max(0, min(cols - 4, 88))
    if not static and (cols < 52 or rows < 14):
        message = ["", bold("  Terminal window is too small."),
                   "  Make it at least 52 columns by 14 rows.",
                   f"  Current size: {cols} × {rows}", "",
                   "  Resize the window, or press q to quit."]
        output = "\n".join(message)
        sys.stdout.write("\x1b[2J\x1b[H" + output + "\n")
        sys.stdout.flush()
        return set("q"), True
    compact = rows < 22 or cols < 67
    title, subtitle, variants, footer = page_data(page, cfg, compact)
    # Matches P10K's hierarchy: centered question, rendered examples under
    # numbered answers, restart + quit, and a one-key Choice prompt.
    numbered = PAGES.index(page) + 1
    if rows >= 30:
        lines = ["", "  " + bold("HACK-JITSU · Ghostty Edition"),
                 "  " + shade(f"Configuration wizard  {numbered}/{len(PAGES)}"),
                 "", centered(title, cols), "  " + shade(subtitle), ""]
    else:
        # At 80x24, spend most of the screen on *real examples*, just like
        # Powerlevel10k; reduce decorative headers before shrinking previews.
        lines = ["", "  " + shade(f"Hack-Jitsu · {numbered}/{len(PAGES)}"),
                 centered(title, cols), ""]
    for key, label, preview in variants:
        lines.append("  " + bold(f"({key})  {label}"))
        if not compact:
            lines.extend(preview)
        else:
            lines.append(preview[0] if preview else "")
        lines.append("")
    if rows >= 23:
        for note in footer:
            lines.append("  " + shade(note))
        if footer:
            lines.append("")
    if page != "theme":
        lines.append("  (b)  Previous question.")
    elif rows >= 29:
        lines.append("  " + shade("First question."))
    lines.append("  (r)  Restart from the beginning.")
    lines.append("  (q)  Quit and do nothing.")
    lines.append("")
    options = "".join(key for key, _, _ in variants)
    if page == "theme":
        options += "p"
    if page != "theme":
        options += "b"
    options += "rq"
    prompt = "  " + bold(f"Choice [{options}]: ")
    if len(lines) + 1 > rows:
        # Exactly like P10K's priority passes: discard less essential preview
        # lines but never lose menu choices or the Choice prompt.
        lines = ["", centered(title, cols), ""]
        for key, label, preview in variants:
            lines += ["  " + bold(f"({key})  {label}"),
                      preview[0] if preview else ""]
        lines += ["", "  (b) Back   (r) Restart   (q) Quit", ""]
        if page == "theme":
            lines[-2] = "  (p) Native themes  (r) Restart  (q) Quit"
    if len(lines) + 1 > rows:
        lines = ["", centered(title, cols), ""]
        lines += ["  " + bold(f"({key})  {label}") for key,label,_ in variants]
        lines += ["", "  (r) Restart  (q) Quit", ""]
    trimmed = [limit_line(line, width) for line in lines]
    if not static:
        sys.stdout.write("\x1b[2J\x1b[H" + "\n".join(trimmed) + "\n" + prompt)
    else:
        sys.stdout.write("\n".join(trimmed) + "\n" + prompt + "\n")
    sys.stdout.flush()
    return set(options), False


class Keyboard:
    def __init__(self):
        self.fd = sys.stdin.fileno()
        self.saved = termios.tcgetattr(self.fd)
        self.active = False

    def raw(self):
        if not self.active:
            tty.setcbreak(self.fd, termios.TCSANOW)
            self.active = True

    def cooked(self):
        if self.active:
            termios.tcsetattr(self.fd, termios.TCSANOW, self.saved)
            self.active = False

    def read(self, choices: set[str], *, wait_resize: bool = False):
        global WINCH
        previous_size = terminal_size()
        while True:
            if WINCH or terminal_size() != previous_size:
                WINCH = False
                return None
            ready, _, _ = select.select([self.fd], [], [], 0.15)
            if not ready:
                continue
            char = os.read(self.fd, 1).decode("ascii", errors="ignore").lower()
            if char == "\x03":
                raise KeyboardInterrupt
            if char == "q":
                return "q"
            if wait_resize:
                continue
            if char in choices:
                return char

    def close(self):
        self.cooked()


def custom_title(kbd: Keyboard) -> str | None:
    kbd.cooked()
    sys.stdout.write("\n  Window title (Enter to keep current): ")
    sys.stdout.flush()
    value = sys.stdin.readline()
    kbd.raw()
    if not value:
        return None
    candidate = value.strip()
    if not candidate:
        return ""
    if not re.fullmatch(r"[A-Za-z0-9_. -]{1,48}", candidate):
        sys.stdout.write("\n  Invalid title: use 1–48 ASCII letters/numbers/spaces/._-.\n")
        sys.stdout.flush()
        time.sleep(1.6)
        return None
    return candidate


def select_value(page: str, selected: str, cfg: dict[str, str], kbd: Keyboard):
    mapping = {
        "theme": {"1": "hack-jitsu", "2": "TokyoNight", "3": "Catppuccin Frappe"},
        "bar": {"1": "classic", "2": "compact"},
        "font": {"1": "12", "2": "14", "3": "16"},
        "opacity": {"1": "1", "2": "0.9", "3": "0.8"},
        "option": {"1": "left", "2": "both", "3": "right", "4": "off"},
        "title": {"1": username(), "2": "Hack-Jitsu"},
    }
    if page == "title" and selected == "3":
        value = custom_title(kbd)
        if value is None:
            return False
        if value:
            cfg["title"] = value
        return True
    cfg[page] = mapping[page][selected]
    return True


def native_theme_browser():
    executable = "/Applications/Ghostty.app/Contents/MacOS/ghostty"
    if not Path(executable).is_file():
        executable = shutil.which("ghostty")
    if not executable:
        return
    subprocess.run([executable, "+list-themes"], check=False)


def apply(cfg: dict[str, str]) -> int:
    # Persistence remains centralized in ui-setup.sh. The wizard never
    # writes ui.conf, ~/.zshrc, ~/.config/zellij, or Ghostty directly.
    return subprocess.run([
        "/bin/bash", str(SETUP),
        "--title", cfg["title"], "--bar", cfg["bar"],
        "--option", cfg["option"], "--theme", cfg["theme"],
        "--font", cfg["font"], "--opacity", cfg["opacity"],
    ], check=False).returncode


def run_preview():
    cfg = load_saved()
    for mode in ("theme", "bar"):
        if mode == "bar":
            for style in ("classic", "compact"):
                cfg["bar"] = style
                render("bar", cfg, static=True)
        else:
            render("theme", cfg, static=True)
    print("Note: font pixels, opacity and actual Zellij widgets render only in Ghostty.")
    return 0


def run():
    if "--preview" in sys.argv:
        return run_preview()
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("Interactive TTY required. Run hjsetup --preview for examples.", file=sys.stderr)
        return 2

    initial = load_saved()
    cfg = deepcopy(initial)
    previous_handler = signal.getsignal(signal.SIGWINCH)
    signal.signal(signal.SIGWINCH, winch)
    keyboard = Keyboard()
    page_index = 0
    status = 0
    # Use alternate screen buffer: keeps the existing Zellij/terminal scrollback
    # intact even when users restart or abort the wizard.
    sys.stdout.write("\x1b[?1049h\x1b[?25l")
    sys.stdout.flush()
    in_alt = True
    try:
        keyboard.raw()
        while True:
            page = PAGES[page_index]
            keys, too_small = render(page, cfg)
            key = keyboard.read(keys, wait_resize=too_small)
            if key is None:
                continue
            if key == "q":
                break
            if key == "r":
                cfg = deepcopy(initial)
                page_index = 0
                continue
            if key == "b":
                page_index = max(0, page_index-1)
                continue
            if page == "theme" and key == "p":
                keyboard.cooked()
                sys.stdout.write("\x1b[?1049l\x1b[?25h")
                sys.stdout.flush()
                in_alt = False
                native_theme_browser()
                sys.stdout.write("\x1b[?1049h\x1b[?25l")
                sys.stdout.flush()
                in_alt = True
                keyboard.raw()
                continue
            if page == "save":
                keyboard.cooked()
                sys.stdout.write("\x1b[?1049l\x1b[?25h")
                sys.stdout.flush()
                in_alt = False
                status = apply(cfg)
                if status == 0:
                    print("Saved. Settings: " + str(PREF))
                    print("Zellij bar changes appear in your next *new* session.")
                else:
                    print("Could not save settings; review errors above.", file=sys.stderr)
                return status
            if select_value(page, key, cfg, keyboard):
                page_index += 1
    except KeyboardInterrupt:
        pass
    finally:
        keyboard.close()
        signal.signal(signal.SIGWINCH, previous_handler)
        if in_alt:
            sys.stdout.write("\x1b[?25h\x1b[?1049l")
        else:
            sys.stdout.write("\x1b[?25h")
        sys.stdout.flush()
    print("Cancelled. Existing configuration unchanged.")
    return status


if __name__ == "__main__":
    try:
        sys.exit(run())
    except (ValueError, OSError) as exc:
        print(f"hjsetup: {exc}", file=sys.stderr)
        sys.exit(2)
