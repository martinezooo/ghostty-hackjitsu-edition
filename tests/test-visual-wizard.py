#!/usr/bin/env python3
"""PTY integration: Powerlevel10k-like *single-key* UI, paths and persistence."""
from __future__ import annotations
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

ROOT = Path(__file__).resolve().parent.parent


def runpty(argv, env, actions, *, size=(28, 94), timeout=15):
    """For each (screen substring, keystroke), wait for *that* screen, then type."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(str(argv[0]), [str(a) for a in argv], env)
    os.set_blocking(fd, False)
    fcntl.ioctl(fd, termios.TIOCSWINSZ,
                struct.pack("HHHH", size[0], size[1], 0, 0))
    os.kill(pid, signal.SIGWINCH)
    transcript = bytearray()
    position = 0
    index = 0
    start = time.monotonic()
    exitcode = None
    try:
        while time.monotonic() - start < timeout:
            ready, _, _ = select.select([fd], [], [], .075)
            if ready:
                try:
                    block = os.read(fd, 65536)
                except (BlockingIOError, OSError):
                    block = b""
                transcript.extend(block)
            while index < len(actions):
                expected, keystroke = actions[index]
                needle = expected.encode("utf-8")
                found = transcript.find(needle, position)
                if found == -1:
                    break
                position = found + len(needle)
                if isinstance(keystroke, tuple):
                    rows, cols = keystroke
                    fcntl.ioctl(fd, termios.TIOCSWINSZ,
                                struct.pack("HHHH", rows, cols, 0, 0))
                    os.kill(pid, signal.SIGWINCH)
                else:
                    # No newline unless explicitly requested. This verifies
                    # that selection really is a P10K-style raw single key.
                    os.write(fd, keystroke.encode("utf-8"))
                index += 1
            waited, status = os.waitpid(pid, os.WNOHANG)
            if waited:
                exitcode = os.waitstatus_to_exitcode(status)
                pid = 0
                break
        else:
            raise AssertionError("Wizard timed out at step "
                                 f"{index}/{len(actions)}: {transcript[-1600:]!r}")
    finally:
        if pid:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass
        os.close(fd)
    text = transcript.decode("utf-8", errors="replace")
    assert index == len(actions), (
        f"Only {index}/{len(actions)} prompts appeared; "
        f"last output: {text[-2000:]}")
    return text, exitcode


with tempfile.TemporaryDirectory(prefix="hj-visual-p10k-") as root:
    base = Path(root)
    home = base / "home"
    home.mkdir()
    cfg = home / ".config"
    state = home / ".local/state"
    env = {**os.environ, "HOME": str(home), "XDG_CONFIG_HOME": str(cfg),
           "XDG_STATE_HOME": str(state), "TERM": "xterm-256color",
           "HJ_AUTO_ZELLIJ": "0", "USER": "analyst"}
    installer = ["bash", str(ROOT / "install.sh"),
                 "--no-brew", "--no-quit", "--no-nvim", "--no-shell"]
    proc = subprocess.run(installer, env=env, capture_output=True, text=True)
    assert proc.returncode == 0, (proc.stdout[-1500:], proc.stderr[-1000:])
    setup = cfg / "ghostty-hackjitsu/ui-setup.sh"
    prefs = cfg / "ghostty-hackjitsu/ui.conf"
    ghostty = cfg / "ghostty/config"
    zellij = cfg / "ghostty-hackjitsu/zellij/config.kdl"
    assert prefs.is_file(), "Default ui.conf must exist after installation."
    assert prefs.stat().st_mode & 0o777 == 0o600
    before = [p.read_bytes() for p in (prefs, ghostty, zellij)]

    # Static samples are printable and never change installed settings.
    preview = subprocess.run(["bash", str(setup), "--preview"], env=env,
                             capture_output=True, text=True)
    assert preview.returncode == 0, preview.stderr
    assert "(1)  Hack-Jitsu Red." in preview.stdout
    assert "(2)  Classic. Full keyboard shortcuts." not in preview.stdout
    assert "Classic. Full keyboard shortcuts." in preview.stdout
    assert "Compact. One line with tabs." in preview.stdout
    assert [p.read_bytes() for p in (prefs, ghostty, zellij)] == before

    # A selection happens immediately when the user presses a digit: no Enter.
    screen, rc = runpty(["bash", str(setup)], env, [
        ("Choice [123prq]: ", "2"),
        ("Choice [12brq]: ", "q"),
    ])
    assert rc == 0, (rc, screen[-700:])
    assert "Tokyo Night." in screen and "Zellij Status Bar" in screen
    assert "Cancelled." in screen
    assert "\x1b[?1049h" in screen and "\x1b[?1049l" in screen
    assert [p.read_bytes() for p in (prefs, ghostty, zellij)] == before

    # r restarts the wizard and b goes back to previous question.
    screen, rc = runpty(["bash", str(setup)], env, [
        ("Choice [123prq]: ", "1"),
        ("Choice [12brq]: ", "r"),
        ("Choice [123prq]: ", "3"),
        ("Choice [12brq]: ", "b"),
        ("Choice [123prq]: ", "q"),
    ])
    assert rc == 0 and screen.count("Prompt Colors") >= 3
    assert [p.read_bytes() for p in (prefs, ghostty, zellij)] == before

    # q from the FINAL summary also must not save the prior six choices.
    screen, rc = runpty(["bash", str(setup)], env, [
        ("Choice [123prq]: ", "2"),
        ("Choice [12brq]: ", "2"),
        ("Choice [123brq]: ", "3"),
        ("Choice [123brq]: ", "3"),
        ("Choice [1234brq]: ", "2"),
        ("Choice [123brq]: ", "1"),
        ("Choice [1brq]: ", "q"),
    ])
    assert rc == 0
    assert [p.read_bytes() for p in (prefs, ghostty, zellij)] == before

    # Confirm fully-configured user intent. Only the title entry needs Enter.
    screen, rc = runpty(["bash", str(setup)], env, [
        ("Choice [123prq]: ", "2"),
        ("Choice [12brq]: ", "2"),
        ("Choice [123brq]: ", "3"),
        ("Choice [123brq]: ", "3"),
        ("Choice [1234brq]: ", "2"),
        ("Choice [123brq]: ", "3"),
        ("Window title (Enter to keep current): ", "team-user\n"),
        ("Choice [1brq]: ", "1"),
    ])
    assert rc == 0, (rc, screen[-1500:])
    assert "Saved UI preferences:" in screen
    installed = ghostty.read_text()
    assert "title = team-user" in installed
    assert "theme = TokyoNight" in installed
    assert "font-size = 16" in installed
    assert "background-opacity = 0.8" in installed
    assert "macos-icon = custom" in installed
    assert 'default_layout "compact"' in zellij.read_text()
    saved = prefs.read_text()
    for line in ("title=team-user", "bar=compact", "theme=TokyoNight",
                 "font=16", "opacity=0.8", "option=both"):
        assert line in saved, line
    assert prefs.stat().st_mode & 0o777 == 0o600

    # A saved ui.conf is authoritative on every reinstall and --apply.
    saved_bytes = [p.read_bytes() for p in (prefs, ghostty, zellij)]
    for command in (["bash", str(setup), "--apply"], installer):
        proc = subprocess.run(command, env=env, capture_output=True, text=True)
        assert proc.returncode == 0, proc.stderr[-1200:]
        assert [p.read_bytes() for p in (prefs, ghostty, zellij)] == saved_bytes

    # Simulate failure *after* writing a new Zellij file, before Ghostty.
    # A transactional save must roll back Zellij and leave ui.conf unchanged.
    failbin = base / "failbin"
    failbin.mkdir()
    fake_mv = failbin / "mv"
    fake_mv.write_text(
        "#!/bin/sh\n"
        "case \"$*\" in *ghostty/config*) exit 37;; esac\n"
        "exec /bin/mv \"$@\"\n"
    )
    fake_mv.chmod(0o755)
    envfail = {**env, "PATH": str(failbin) + ":" + env["PATH"]}
    proc = subprocess.run(["bash", str(setup), "--title", "rollback-test",
                           "--bar", "classic"], env=envfail,
                          capture_output=True, text=True)
    assert proc.returncode != 0, "Mocked mv failure unexpectedly succeeded"
    assert [p.read_bytes() for p in (prefs, ghostty, zellij)] == saved_bytes, (
        "Output divergence after mid-transaction write failure")

    # A failed or aborted wizard never leaves the terminal alt buffer active.
    screen, rc = runpty(["bash", str(setup)], env, [
        ("Choice [123prq]: ", "\x03"),
    ])
    assert rc == 0 and "Cancelled." in screen
    assert "\x1b[?1049l" in screen
    assert [p.read_bytes() for p in (prefs, ghostty, zellij)] == saved_bytes

    # Tiny terminals show a size warning; resize redraws with intact state.
    screen, rc = runpty(["bash", str(setup)], env, [
        ("Terminal window is too small.", (28, 94)),
        ("Choice [123prq]: ", "q"),
    ], size=(11, 44))
    assert rc == 0
    assert "Cancelled." in screen
    assert [p.read_bytes() for p in (prefs, ghostty, zellij)] == saved_bytes

    # Mock only the Powerlevel10k subprocess, never the filesystem it writes.
    fakebin = base / "fakebin"
    fakebin.mkdir()
    fakezsh = fakebin / "zsh"
    fakezsh.write_text(
        "#!/bin/sh\n"
        "printf '%s\\n' '# Powerlevel10k generated config' "
        "'PROMPT=wizard-private' > \"$ZDOTDIR/.p10k.zsh\"\n"
        "echo MOCK_P10K_WIZARD\n")
    fakezsh.chmod(0o755)
    env["PATH"] = str(fakebin) + ":" + os.environ["PATH"]
    personal_rc = home / ".zshrc"
    personal_rc.write_text("PRESERVE MY PERSONAL ZSH\n")
    personal_p10k = home / ".p10k.zsh"
    personal_p10k.write_text("PRESERVE MY PERSONAL P10K\n")
    screen, rc = runpty(["bash", cfg / "ghostty-hackjitsu/p10k-setup.sh"], env, [])
    assert rc == 0 and "MOCK_P10K_WIZARD" in screen
    isolated = cfg / "ghostty-hackjitsu/zsh/.p10k.zsh"
    assert isolated.is_file()
    assert isolated.stat().st_mode & 0o777 == 0o600
    assert (isolated.parent / "enable-p10k").is_file()
    assert personal_rc.read_text() == "PRESERVE MY PERSONAL ZSH\n"
    assert personal_p10k.read_text() == "PRESERVE MY PERSONAL P10K\n"
    assert [p.read_bytes() for p in (prefs, ghostty, zellij)] == saved_bytes

    # Actual installer executes P10K first, then the Hack-Jitsu wizard.
    screen, rc = runpty(["bash", str(ROOT / "install.sh"), "--setup",
                          "--no-brew", "--no-quit", "--no-nvim", "--no-shell"],
                        env, [("Choice [123prq]: ", "q")], timeout=19)
    assert rc == 0, (rc, screen[-1800:])
    a = screen.find("Stage 1/2: Powerlevel10k")
    b = screen.find("Stage 2/2: Hack-Jitsu")
    assert a >= 0 and b > a, (a, b)
    assert personal_rc.read_text() == "PRESERVE MY PERSONAL ZSH\n"
    assert personal_p10k.read_text() == "PRESERVE MY PERSONAL P10K\n"
    assert [p.read_bytes() for p in (prefs, ghostty, zellij)] == saved_bytes

print("PASS: P10K-style single-key choices, r/b/q, previews, TTY resize, "
      "atomic save, unchanged reinstall and isolated P10K files.")
