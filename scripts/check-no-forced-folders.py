#!/usr/bin/env python3
"""Fails if app code creates the folder hierarchy the project has rejected.

The workspace is the one root folder in public storage (see PublicStorage.kt). Users
organise their own folders: the app must not create "Projects", "Backups" or "Exports"
under it (or anywhere in shared storage) on first launch or at any other time.

Looks in the Kotlin sources and the shell assets for a string or path that names one of
those folders. Comments are ignored. Run from the repository root.
"""
import re, sys, pathlib

NAMES = ("Projects", "Backups", "Exports")
ROOTS = ["android/app/src/main/kotlin", "android/app/src/main/assets"]
EXTS = {".kt", ".sh"}
pat = re.compile(r'["\'/](?:%s)["\'/]' % "|".join(NAMES))

bad = []
for root in ROOTS:
    for f in pathlib.Path(root).rglob("*"):
        if f.suffix not in EXTS or "extensions" in f.parts:
            continue
        for n, line in enumerate(f.read_text(errors="replace").splitlines(), 1):
            code = line.split("//")[0] if f.suffix == ".kt" else line.split("#")[0]
            if pat.search(code):
                bad.append(f"{f}:{n}: {line.strip()[:100]}")
if bad:
    print("FAIL  code that names a forced folder (Projects / Backups / Exports):")
    print("\n".join("  " + b for b in bad))
    sys.exit(1)
print("  ok     no code creates Projects, Backups or Exports")
