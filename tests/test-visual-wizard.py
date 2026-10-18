#!/usr/bin/env python3
"""Real pseudo-terminal regression for isolated P10K and Hack-Jitsu previews."""
from __future__ import annotations
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent

def runpty(argv, env, answers, timeout=15):
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe(argv[0], list(map(str,argv)),env)
    text = b""
    prompts = 0
    start = time.monotonic()
    try:
        while time.monotonic() - start < timeout:
            ready,_,_ = select.select([fd],[],[],0.12)
            if ready:
                try:
                    part = os.read(fd,65536)
                except OSError:
                    break
                if not part:
                    break
                text += part
                # Each stage waits for a confirmation line ending with ': '.
                count = text.count(b"]: ")
                while prompts < count and prompts < len(answers):
                    os.write(fd,answers[prompts].encode()+b"\n")
                    prompts+=1
            if not ready:
                try:
                    wp, status=os.waitpid(pid,os.WNOHANG)
                except ChildProcessError:
                    break
                if wp:
                    pid=0
                    break
        else:
            raise RuntimeError("wizard hung past timeout")
    finally:
        if pid:
            try:os.kill(pid,signal.SIGTERM)
            except ProcessLookupError:pass
            try:os.waitpid(pid,0)
            except ChildProcessError:pass
        os.close(fd)
    return text.decode(errors="replace"), prompts

with tempfile.TemporaryDirectory(prefix="hj-visual-pty-") as root:
    base=Path(root)
    home=base/"home"
    cfg=home/".config"
    env={**os.environ,"HOME":str(home),"XDG_CONFIG_HOME":str(cfg),
         "XDG_STATE_HOME":str(home/".local/state"),"TERM":"xterm-256color",
         "HJ_AUTO_ZELLIJ":"0"}
    # Configure only. Never modifies the real user's Home, Ghostty or packages.
    proc=subprocess.run(["bash",str(ROOT/"install.sh"),"--no-brew","--no-quit",
                         "--no-nvim","--no-shell"],env=env,capture_output=True,text=True)
    assert proc.returncode==0,(proc.stdout[-1100:],proc.stderr[-1100:])
    script=cfg/"ghostty-hackjitsu/ui-setup.sh"
    prefs=cfg/"ghostty-hackjitsu/ui.conf"
    ghostty=cfg/"ghostty/config"
    orig=ghostty.read_bytes()
    # Render both previews with no TTY / no changes.
    preview=subprocess.run(["bash",str(script),"--preview"],env=env,capture_output=True,text=True)
    assert preview.returncode==0,preview.stderr
    assert "Zellij classic / 2 lines" in preview.stdout
    assert "Zellij compact / 1 line" in preview.stdout
    assert ghostty.read_bytes()==orig and not prefs.exists()
    # Visible samples followed by cancellation: no config writes.
    screen,count=runpty(["bash",script],env,["1","2","2","2","1","","n"])
    assert count==7,(count,screen[-900:])
    assert "Zellij compact / 1 line" in screen
    assert ghostty.read_bytes()==orig and not prefs.exists()
    # Commit: exactly one change at the final y.
    screen,count=runpty(["bash",script],env,["2","2","3","3","2","team-user","y"])
    assert count==7,(count,screen[-1100:])
    assert "Saved." in screen,screen[-1200:]
    installed=ghostty.read_text()
    assert "theme = TokyoNight" in installed,installed[-500:]
    assert "title = team-user" in installed
    assert "font-size = 16" in installed
    assert "background-opacity = 0.8" in installed
    assert "macos-icon = custom" in installed
    assert "default_layout" in (cfg/"ghostty-hackjitsu/zellij/config.kdl").read_text()
    assert "default_layout \"compact\"" in (cfg/"ghostty-hackjitsu/zellij/config.kdl").read_text()
    assert "option=both" in prefs.read_text()
    # The full Powerlevel10k wizard runs in a throwaway ZDOTDIR. Mock only the
    # interactive Zsh process, and assert ~/.zshrc and ~/.p10k.zsh never change.
    fakebin=base/"fakebin"
    fakebin.mkdir()
    wrapper=fakebin/"zsh"
    wrapper.write_text("#!/bin/sh\nprintf '%s\\n' '# Powerlevel10k generated config' "
                       "'PROMPT=private-wizard-prompt' > \"$ZDOTDIR/.p10k.zsh\"\n"
                       "printf 'MOCK_POWERLEVEL10K_WIZARD\\n'\n")
    wrapper.chmod(0o755)
    env["PATH"]=str(fakebin)+":"+os.environ["PATH"]
    personal_rc=home/".zshrc"
    personal_rc.write_text("PRIVATE ZSH USER CONTENT: DO NOT EDIT\n")
    personal_p10k=home/".p10k.zsh"
    personal_p10k.write_text("PRIVATE POWERLEVEL CONFIG: DO NOT EDIT\n")
    screen,_=runpty(["bash",cfg/"ghostty-hackjitsu/p10k-setup.sh"],env,[],timeout=8)
    assert "MOCK_POWERLEVEL10K_WIZARD" in screen,screen[-1000:]
    assert "Powerlevel10k prompt stored" in screen,screen[-1000:]
    assert personal_rc.read_text()=="PRIVATE ZSH USER CONTENT: DO NOT EDIT\n"
    assert personal_p10k.read_text()=="PRIVATE POWERLEVEL CONFIG: DO NOT EDIT\n"
    isolated=cfg/"ghostty-hackjitsu/zsh/.p10k.zsh"
    assert isolated.is_file()
    assert (cfg/"ghostty-hackjitsu/zsh/enable-p10k").is_file()
    assert isolated.stat().st_mode & 0o777 == 0o600
    assert not list((home/".local/state/ghostty-hackjitsu").glob("p10k-wizard.*"))
    # Check the actual install --setup order in a TTY: original P10K wizard
    # must finish before the Hack-Jitsu visual wizard starts.
    command=["bash",str(ROOT/"install.sh"),"--setup","--no-brew","--no-quit",
             "--no-nvim","--no-shell"]
    output,num=runpty(command,env,["1","1","2","2","1","","n"],timeout=19)
    assert num==7,(num,output[-1400:])
    stage1=output.find("Stage 1/2: Powerlevel10k")
    stage2=output.find("Stage 2/2: Hack-Jitsu")
    assert 0<=stage1<stage2,(stage1,stage2,output[-2500:])
    assert "HACK-JITSU" in output
    assert personal_rc.read_text()=="PRIVATE ZSH USER CONTENT: DO NOT EDIT\\n".replace('\\n','\n')
    print("PASS: visual wizard cancel/no writes, final commit, red icon, "
          "isolated Powerlevel10k PTTY flow and private Zsh preservation")
