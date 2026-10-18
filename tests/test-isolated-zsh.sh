#!/usr/bin/env bash
# Exercise isolated Ghostty ZDOTDIR startup through a real pseudo-terminal.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v zsh >/dev/null 2>&1; then echo "SKIP: zsh missing"; exit 0; fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export HJ_TEST_BIN="$TMP/bin"
export HJ_TEST_ZELLIJ_LOG="$TMP/zellij.log"
mkdir -p "$HOME" "$HJ_TEST_BIN"
printf '%s\n' 'echo PERSONAL_ZSHRC_INCORRECTLY_LOADED' 'tmux attach' > "$HOME/.zshrc"
cat > "$HJ_TEST_BIN/zellij" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$HJ_TEST_ZELLIJ_LOG"
if [ "$1" = --config ] && [ "$3" = setup ] && [ "$4" = --check ]; then
  echo '[CONFIG FILE]: Well defined.'
fi
exit 0
SH
chmod +x "$HJ_TEST_BIN/zellij"
bash "$ROOT/install.sh" --no-brew --no-quit --no-nvim >"$TMP/install.log"
test -f "$XDG_CONFIG_HOME/ghostty-hackjitsu/zsh/.zshrc"
# Test-only zprofile restores the mocked binary before isolated .zshrc runs.
printf '%s\n' 'path=("$HJ_TEST_BIN" $path)' > "$XDG_CONFIG_HOME/ghostty-hackjitsu/zsh/.zprofile"
python3 - <<'PY'
import os,pathlib,pty,select,subprocess,time
log=pathlib.Path(os.environ['HJ_TEST_ZELLIJ_LOG'])
config=pathlib.Path(os.environ['XDG_CONFIG_HOME'])
base={**os.environ,
      'PATH':os.environ['HJ_TEST_BIN']+':'+os.environ['PATH'],
      'TERM_PROGRAM':'ghostty', 'TERM':'xterm-ghostty',
      'ZDOTDIR':str(config/'ghostty-hackjitsu'/'zsh')}
for remove in ['SSH_CONNECTION','SSH_TTY','TMUX','ZELLIJ','HJ_AUTO_ZELLIJ']:
    base.pop(remove,None)
def launch(case,expected,changes=None,marker=False):
    env={**base,**(changes or {})}
    if marker:
        (pathlib.Path(env['ZDOTDIR'])/'no-auto-zellij').touch()
    if log.exists():log.unlink()
    master,slave=pty.openpty()
    p=subprocess.Popen(['/bin/zsh','-lic','print -r -- ISOLATED_'+case],
        stdin=slave,stdout=slave,stderr=slave,env=env,close_fds=True)
    os.close(slave)
    out=b'';until=time.monotonic()+8
    while time.monotonic()<until:
        ready,_,_=select.select([master],[],[],0.1)
        if ready:
            try:
                data=os.read(master,4096)
                if not data:break
                out+=data
            except OSError:break
        if p.poll() is not None and not ready:break
    if p.poll() is None:p.kill()
    p.wait(timeout=3)
    os.close(master)
    output=out.decode('utf-8','replace')
    assert p.returncode==0,(case,p.returncode,output[-1000:])
    assert 'PERSONAL_ZSHRC_INCORRECTLY_LOADED' not in output,(case,output)
    assert 'command not found: tmux' not in output,(case,output)
    assert 'ISOLATED_'+case in output,(case,output)
    calls=log.read_text().strip().splitlines() if log.exists() else []
    assert len(calls)==expected,(case,calls,output[-1000:])
    if calls:
        assert calls[0].startswith('--session hj-'),(case,calls)
        assert len(calls[0].split(' ',1)[1]) <= 16,('socket-path risk',calls)
        assert 'attach' not in calls[0], (case,calls)
    print('PASS ZDOTDIR case',case,'Zellij calls:',len(calls))
launch('normal',1)
first=log.read_text().strip()
launch('normal_again',1)
second=log.read_text().strip()
assert first!=second,('Zellij sessions must have unique names',first,second)
print('PASS: each Ghostty startup gets a fresh session instead of old editor')
launch('nested_zellij',0,{'ZELLIJ':'1'})
launch('nested_tmux',0,{'TMUX':'/tmp/tmux'})
launch('ssh',0,{'SSH_CONNECTION':'remote'})
launch('disabled_env',0,{'HJ_AUTO_ZELLIJ':'0'})
launch('disabled_marker',0,marker=True)
print('PASS: personal ~/.zshrc never read and Zellij startup guards respected')
PY
