#!/usr/bin/env python3
"""Block accidental personal data in portable source and cheats."""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
paths = [root / "README.md", root / "install.sh"]
for folder in ("ghostty", "cheats", "shell", "nvim", "zellij"):
    paths.extend((root / folder).rglob("*"))
checks = {
    "private account or school marker": r"(?i)\b(?:usos|uam|bichon|myhackedworld)\b",
    "local macOS username path": r"/Users/[A-Za-z0-9_.-]+",
    "private IPv4": r"\b(?:10|192\.168|172\.(?:1[6-9]|2[0-9]|3[01]))\.(?:\d{1,3}\.){1,2}\d{1,3}\b",
    "known token or private key": r"(?:-----BEGIN [A-Z ]*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9_]{20}|sk-[A-Za-z0-9_-]{25})",
}
failed = []
for path in paths:
    if not path.is_file() or path.suffix.lower() in (".png", ".jpg", ".webp"):
        continue
    content = path.read_text(encoding="utf-8")
    for label, regex in checks.items():
        if re.search(regex, content):
            failed.append(f"{path.relative_to(root)}: {label}")
if failed:
    print("FAIL portability audit:\n" + "\n".join(failed), file=sys.stderr)
    sys.exit(1)
print(f"PASS portability audit ({len(paths)} entries)")
