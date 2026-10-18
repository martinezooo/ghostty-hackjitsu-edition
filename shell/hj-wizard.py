#!/usr/bin/env python3
"""Visual Hack-Jitsu wizard, inspired by the Powerlevel10k presentation style.

Stages preview before selection; changes to installed config are made only
after explicit confirmation. Never writes personal ~/.zshrc or global Zellij.
"""
from __future__ import annotations
import os
from pathlib import Path
import subprocess
import sys

HJ = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "ghostty-hackjitsu"
SETUP = HJ / "ui-setup.sh"
IS_TTY = sys.stdin.isatty() and sys.stdout.isatty()
COLORS = os.getenv("NO_COLOR") is None and (IS_TTY or "--preview" in sys.argv)

def color(code, text):
    return f"\033[{code}m{text}\033[0m" if COLORS else text

def clear():
    if IS_TTY:
        sys.stdout.write("\033[2J\033[H")

def headline(num, title):
    clear()
    print()
    print(color("1;31", "  ██ HACK-JITSU  /  Ghostty Edition"))
    print(color("2", f"  Configuration preview  ·  {num}/6"))
    print("  " + "━" * 51)
    print(color("1", f"  {title}"))
    print()

def card(label, body, primary=False):
    print("  " + color("1;31" if primary else "1;36", f"┌─ {label} " + "─" * max(2, 45-len(label))))
    for line in body:
        print("  " + color("90", "│") + "  " + line)
    print("  " + color("90", "└" + "─"*52))
    print()

def option(options, default, question="Choose (q = cancel)"):
    print("  " + color("1", "    ".join(f"{i}={text}" for i,text in options)))
    print(color("90", f"  {question} [default {default}]: "), end="", flush=True)
    while True:
        value = sys.stdin.readline().strip().lower()
        if value in ("q", "quit", "\x03"):
            raise KeyboardInterrupt
        if value == "":
            value = default
        allowed = {i for i, _ in options}
        if value in allowed:
            return value
        print(f"  Choose {', '.join(allowed)} or q: ", end="", flush=True)

def load():
    cfg = {"title": os.environ.get("USER", "user"),
           "bar": "classic", "option": "left", "theme": "hack-jitsu",
           "font": "14", "opacity": "0.9"}
    if HJ.joinpath("ui.conf").is_file():
        for line in HJ.joinpath("ui.conf").read_text().splitlines():
            key,_,value=line.partition("=")
            if key in cfg and value:
                cfg[key]=value
    return cfg

def preview_terminal(cfg):
    themes={
        "hack-jitsu":("1;31","31", "dark / red", "#ec1313"),
        "TokyoNight":("1;34","34","midnight / blue","#7aa2f7"),
        "Catppuccin Frappe":("1;35","35","plum / pastel","#ca9ee6")}
    bold,c,style,hexval=themes.get(cfg["theme"],themes["hack-jitsu"])
    card(f"Ghostty • {style} • font {cfg['font']} • opacity {cfg['opacity']}", [
       color("90", "Last login: Sun Oct 18 on ttys004"),
       color(bold,"   HACK-JITSU  ") + color("90","Ghostty · ") + cfg["title"],
       color("90","~ / audit / api-response.log"),
       color(c,"  ❯ ") + color("97","nvim response.log"),
       color("90",f"   ANSI preview: {hexval}  ⌥ Option+Tab · Ctrl+T")
    ],True)

def preview_bars(cfg):
    if cfg["bar"]=="classic":
        card("Zellij classic / 2 lines",[
            color("90","●  hj-23456   [1] zsh    [2] nvim"),
            color("30;47"," CTRL  LOCK   PANE   TAB   RESIZE   MOVE   SEARCH   QUIT "),
            color("90","⌃P,N = new pane  ·  ⌃T,N = new tab  ·  ⌥ = Alt")
        ])
    else:
        card("Zellij compact / 1 line",[
            color("30;47"," [1] zsh  [2] nvim                        ⌥←  ⌥→ "),
            color("90","Single line, no full shortcut bar.  hjkeys shows help.")
        ])

def run():
    if "--preview" in sys.argv:
        for bar in ("classic","compact"):
            cfg=load()
            cfg["bar"]=bar
            headline("PREVIEW",f"Example: {bar} Zellij")
            preview_terminal(cfg)
            preview_bars(cfg)
        print("This is a terminal-rendered preview, not a screenshot of Ghostty.")
        return 0
    if not IS_TTY:
        print("Interactive terminal required; use hjsetup --preview for examples.",file=sys.stderr)
        return 2
    cfg=load()
    try:
        headline(1,"Select terminal colors")
        for i,t in enumerate(("hack-jitsu","TokyoNight","Catppuccin Frappe"),1):
            tmp=cfg.copy(); tmp["theme"]=t
            preview_terminal(tmp)
        while True:
            selection=option([("1","Hack-Jitsu red"),("2","TokyoNight blue"),("3","Catppuccin plum"),
                              ("p","Open Ghostty native theme preview")],
                             {"hack-jitsu":"1","TokyoNight":"2","Catppuccin Frappe":"3"}.get(cfg["theme"],"1"))
            if selection!="p":
                break
            candidates=["/Applications/Ghostty.app/Contents/MacOS/ghostty",
                        str(Path.home()/"Applications/Ghostty.app/Contents/MacOS/ghostty")]
            binary=next((b for b in candidates if Path(b).is_file()),None)
            if binary:
                subprocess.run([binary,"+list-themes"],check=False)
            else:
                print("Native Ghostty theme browser unavailable; use the sample previews.")
            headline(1,"Select terminal colors")
            for name in ("hack-jitsu","TokyoNight","Catppuccin Frappe"):
                tmp=cfg.copy(); tmp["theme"]=name
                preview_terminal(tmp)
        cfg["theme"]={"1":"hack-jitsu","2":"TokyoNight","3":"Catppuccin Frappe"}[selection]
        headline(2,"Select Zellij status bar")
        preview_terminal(cfg)
        for kind in ("classic","compact"):
            tmp=cfg.copy();tmp["bar"]=kind
            preview_bars(tmp)
        cfg["bar"]={"1":"classic","2":"compact"}[
            option([("1","Full shortcuts"),("2","Compact / one line")],
                   "2" if cfg["bar"]=="compact" else "1")]
        headline(3,"Text size and transparency")
        preview_terminal(cfg)
        cfg["font"]={"1":"12","2":"14","3":"16"}[
            option([("1","12pt small"),("2","14pt balanced"),("3","16pt large")],
                   {"12":"1","14":"2","16":"3"}.get(cfg["font"],"2"))]
        cfg["opacity"]={"1":"1","2":"0.9","3":"0.8"}[
            option([("1","Opaque / 100%"),("2","90%"),("3","80%")],
                   {"1":"1","0.9":"2","0.8":"3"}.get(cfg["opacity"],"2"),"Opacity")]
        headline(4,"macOS Option / Alt handling")
        card("Keyboard and shortcut mapping",[
            "⌥  Option = Alt   (Zellij notation)",
            "⌃  Control+P,N = split pane",
            "⌃  Control+T,N = new tab",
            "Left Option → Zellij; right Option → Polish letters (default)"
        ])
        cfg["option"]={"1":"left","2":"both","3":"off"}[
            option([("1","Left Option=Alt"),("2","Both Options=Alt"),("3","No remapping")],
                   {"left":"1","both":"2","off":"3"}.get(cfg["option"],"1"))]
        headline(5,"Window title (Ghostty)")
        preview_terminal(cfg)
        print("  Ghostty title will replace dynamic titles such as zellij (hj-23456).")
        print(f"  Name [default {cfg['title']}]: ",end="",flush=True)
        new_title=sys.stdin.readline().strip()
        if new_title.lower() in ("q","quit"):
            raise KeyboardInterrupt
        if new_title:
            cfg["title"]=new_title
        headline(6,"Preview before saving")
        preview_terminal(cfg)
        preview_bars(cfg)
        card("Settings to save",[
            "Title: "+cfg["title"],"Theme: "+cfg["theme"],
            "Font: "+cfg["font"]+"pt  Opacity: "+cfg["opacity"],
            "Option mapping: "+cfg["option"],
            "Custom icon: Hack-Jitsu RED (transparent PNG)"
        ])
        if option([("y","Save these settings"),("n","Cancel")],"n")!="y":
            print("  Cancelled. No files changed.")
            return 0
        result=subprocess.run(["bash",str(SETUP),"--title",cfg["title"],"--bar",cfg["bar"],
                               "--option",cfg["option"],"--theme",cfg["theme"],
                               "--font",cfg["font"],"--opacity",cfg["opacity"]],check=False)
        if result.returncode:
            print(color("1;31","  Failed to write settings; original files preserved."),file=sys.stderr)
            return result.returncode
        print(color("1;32","  Saved. Reopen the next Zellij session to see the chosen bar."))
        return 0
    except (KeyboardInterrupt,EOFError):
        print("\n  Cancelled. Existing settings remain unchanged.")
        return 130

if __name__=="__main__":
    sys.exit(run())
