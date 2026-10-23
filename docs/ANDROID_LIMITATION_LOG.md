# Android limitation log: Ubuntu recovery and Git

2026-10-16. Follows the seven steps asked for. Items marked "pending" have not been run on a phone.

## 1. Ubuntu reset / repair

| Step | Finding |
|------|---------|
| Problem | Ubuntu lives in private storage as plain files, some read-only folders (mode 555); links inside may point at projects; no real mounts exist (proot translates paths), so deleting cannot reach a bind |
| Docs / terms | proot and Ubuntu Base are used as already shipped; nothing new to license |
| Alternatives | Delete through proot (rejected: depends on the thing being repaired); delete from the phone side (chosen) |
| Security | Guard: path must end `/proot/ubuntu`, never under `/storage`, `/sdcard`, `/mnt`; `chmod -R u+rwX` first; `rm` does not follow links |
| Result | Done. Checked in a sandbox: project file intact with a link to it inside Ubuntu, refusals, cancel, Enter, `--yes`, repair on healthy and on damaged Ubuntu |
| Device test | Pending (see DEVICE_TESTS_RECOVERY_GIT.md) |
| Remaining limit | Virtual environments made in Ubuntu are lost and must be recreated |

## 2. Git auto-setup

| Step | Finding |
|------|---------|
| Problem | The phone's Source Control uses the phone's own git, not Ubuntu's. Ubuntu's git is for tools run inside Ubuntu. dpkg allows one install at a time. Files in shared storage look foreign to git ("dubious ownership") |
| Alternatives | Run Source Control through Ubuntu git (rejected: slow, and VS Code runs git on the phone side) |
| Result | Git installed in the background once, one shared lock for all installs, `safe.directory=*` inside Ubuntu only, user name and email copied from the phone's git |
| Device test | Pending: clone, commit, push, pull |

## 3. Where to keep a GitHub token

Options checked against the Git Credential Manager documentation and Android's own documentation:

| Option | Verdict |
|--------|---------|
| GCM, Secret Service store | Needs a desktop keyring over D-Bus; none exists in proot |
| GCM, gpg/pass store | Needs gpg, pass and a key; on a phone the key sits beside the secrets, and headless use needs a pin-entry program |
| GCM / git `cache` | In-memory only; the daemon dies when the proot session ends, so every command would ask again |
| GCM | Also a .NET program that is not packaged for this environment |
| Plain file in a project or the home folder | Not acceptable |
| **git `store` on a private file (chosen for Ubuntu git)** | Plain file, mode 600, in app-private storage, outside any project, excluded from backups, kept across a reset. Not encrypted |
| VS Code GitHub sign-in (phone git, Source Control) | Already in place; token sealed in the workbench secret store |
| Android Keystore | The right place for a key, per Android's documentation: keys are hard to extract. It needs app code (Kotlin) and a bridge a shell helper can call; not built. This is the way to improve the Ubuntu sign-in |

Remaining limit: the Ubuntu sign-in file is protected by the app sandbox, not encrypted. Anything that can read the app's
private storage can read it.

Terms: the user supplies their own token and Git uses its standard credential protocol; nothing scrapes or bypasses
GitHub. GitHub's current token guidance should be re-read before release.

## 4. Keeping tokens out of project files

`git remote add|set-url`, `clone`, `fetch`, `pull`, `push` refuse an address with `user:password@` or a GitHub token
prefix. Ubuntu's Git asks for the token itself, hidden, and keeps it in its private `store` file. The `git` written into Ubuntu goes
through the same guard; the internal check that warns about a token already in `.git/config` is no longer a terminal command.

## 5. Build tasks and extensions (tasks.json, Code Runner, NPM Scripts)

2026-10-17. Same seven steps.

| Question | Finding |
|----------|---------|
| `type: shell` tasks | VS Code runs them as `bash -c "<command>"` in the terminal. `$BASH_ENV` is read by that shell, so the routing functions (gcc, python, cargo ...) exist and the command runs in Ubuntu. Working directory, environment and exit code come through; a compile error returns a normal error text and exit code 1 (checked in a sandbox, so problem matchers see what they expect) |
| Virtual environment in shared storage (`/storage/emulated/0/VSCodroid/...`) | **Cannot be a normal environment:** no symbolic links, no program can be started from that filesystem. The real environment is in Ubuntu (or private storage); the project holds `bin/activate`, `python`, `python3`, `pip`, `pip3` as text. Usable from the VSCodroid terminal (`source`, and the `bin/...` paths). **Not usable** by a program that starts `.venv/bin/python` itself (a Python extension, a notebook kernel, a `type: process` task), and not carried by a copy or commit of the project. Sandbox-tested with real Python/pip; not run on a phone |
| Tools installed with `apt` that are not routed names (`java`, `javac`, `clang`, `clangd`, `gdb` ...) | **Terminal and shell tasks: run through `command_not_found_handle`** (added in the audit after Update-11; sandbox-tested with a stand-in, not run on a phone). Not reachable from a `type: process` task or an extension that starts the program itself, and `which`/`command -v` do not see them |
| `type: process` tasks, and extensions that start a compiler directly (for example a C/C++ extension's own build task) | **Routed, not yet run on a phone.** They look for a program file named `gcc`, and Android's SELinux policy does not allow starting a file kept in app storage. The app already ships a real launcher in `nativeLibraryDir` (the exec trampoline, which reads `toolchain-exec.tsv`). `ToolchainManager.addUbuntuRows` now gives `gcc`, `g++`, `cc`, `c++`, `cpp`, `cmake`, `cargo`, `rustc`, `go` and `gofmt` a row each, run by `/system/bin/sh` with a generated script that sources `command-wrapper.sh` in bash and calls the command with `"$@"`. Limits: the Kotlin was not compiled here; `make`, `python` and `pip` keep the phone's own program for such callers; an absolute path (`/usr/bin/gcc`) is not a PATH lookup and never reaches it |
| Code Runner | Its default shows output in the Output panel through a shell that is not ours, so routed commands would not be found. The app now ships `code-runner.runInTerminal: true`, which makes it use the integrated terminal, where they exist. It starts a program built from a C file by its **absolute path**; after a compile the app now defines that path (and `./name`) so it runs in Ubuntu |
| NPM Scripts | VS Code's npm tasks are shell tasks; `npm` already works. Unchanged |
| Result | Written; sandbox-tested with stand-ins for proot and the editor. **Not run with the real extensions on a phone** |
| Remaining limits | `type: process` tasks are written but not run on a phone; paths with spaces or odd characters get no `./name` function defined; the Code Runner behaviour above is from its documented setting, not run here |

## 6. Ctrl+C

| Question | Finding |
|----------|---------|
| Keyboard | The extra key row already has a Ctrl latch that sends keys with Ctrl held (`keyboard/ExtraKeyRow.kt`); VS Code's terminal turns Ctrl+C into the interrupt character, and the editor treats the same key as Copy. No change was needed; not re-run on a phone |
| Phone-side commands (`npm start`) | A pty with a normal shell: the terminal's SIGINT goes to the foreground job. Checked with a real pty in a sandbox |
| Commands in Ubuntu | proot, as understood, answers SIGINT by killing everything it runs at once. A command started straight under proot shares proot's process group, so a program with its own Ctrl+C handling would be cut off, and at an Ubuntu prompt the session would go. This was reproduced with a stand-in that behaves that way |
| Fix | A foreground command typed in the terminal is started by a guest shell with job control (`set -m`), which gives the command its own process group and the terminal. Ctrl+C then reaches only that command; proot is not signalled. Background and piped calls, and calls with no terminal, run as before. `VSCODROID_UB_NO_JOB=1` turns it off |
| Process lifecycle | `--kill-on-exit` stays, so nothing is left in Ubuntu when proot ends. The browser-opening watcher now stops when its command ends or is interrupted |
| Result | Real-pty sandbox tests: a program's own handler runs and proot is not signalled (without the fix, proot kills it); at the Ubuntu prompt Ctrl+C does not end the session; a dev server stops, its port closes, no watcher remains, the prompt returns |
| Remaining limit | Whether the real proot on a phone behaves as described, and whether tcsetpgrp works under it, is for the device test (DEVICE_TESTS_BUILD_CTRLC.md). If a phone refuses job control, the old behaviour is one environment variable away |

## 7. Errors from unsupported operations in shared storage

2026-10-18. Status: written; tested only with stand-ins for the phone's tools in a sandbox. Not run on a phone.

| Step | Finding |
|------|---------|
| Limits involved | Shared storage cannot hold symbolic links or hard links, cannot change permission bits or owners, cannot hold pipes or device files, and nothing in it can be executed. These are the limits already recorded in this repository (the `ln -s` failure noted in `Environment.kt`, `SYMLINKS_ON_PUBLIC_STORAGE.md`) and the ones the owner met with `npm install` |
| Documentation | Android's storage documentation and the tools' manuals were **not re-read for this change**; the limits above come from the repository's own earlier findings. A reviewer should confirm them against the current Android documentation before release |
| What was wrong | When `cp -a`, `mv`, `tar`, `ln`, `chmod` and similar failed there, the terminal showed only the tool's terse line, with nothing to say the cause was the storage |
| Change | The tool's own error is kept exactly. One extra line names the cause, and only when (a) the folder is in shared storage and writable, (b) the error text is of the kind such a limit produces, and (c) a trial shows the folder really cannot do that operation. A missing file, a full disk or a real permission problem gets no extra line. A later Android that allows the operation gets none either. `VSCODROID_NO_FS_NOTES=1` turns it off |
| Exit codes | Unchanged |
| Result | Sandbox, with stand-ins that fail like the storage: links, permission bits, pipes and tar extraction get the right line; "No such file" gets none; a folder that can do the operation gets none; the original text and exit code are intact |
| Not covered | Errors printed by programs inside Ubuntu, by npm, git or other tools that call the system directly, and `Permission denied` from running a stored program (`./script.sh`): no line is added there, because nothing in the shell sees those errors. the supported operations of a folder are written to `~/.vscodroid/ubuntu.log` by the internal check |
| Crashes | No crash was reproduced in the sandbox, and no phone log was available, so no crash fix is claimed. The shell layers never abort the shell: they pass the tool's status through |

## 8. Language toolchains and extensions

2026-10-18. Status: **nothing here has been run on a phone.** See EXTENSION_COMPATIBILITY.md for the table.

| Question | Finding |
|----------|---------|
| `apt install default-jdk` | Goes through the routed `apt` in Ubuntu, under the shared package lock. Not run. Things that can fail, all visible in apt's own error: no network, too little space (several hundred MB), a damaged package database (finished automatically with `dpkg --configure -a`), and the JDK's post-install step, which starts Java once; if proot blocks it the error names the step |
| Which tools the editor can use | Extensions run on the phone side. They can start programs the phone can run, not Ubuntu's programs (they are built for a different C library and are not reachable as files the phone may start). So Ubuntu's JDK serves the terminal, and the Java extension needs a JDK that runs on the phone |
| Java extensions | The app already exports `JAVA_HOME` for a phone-side JDK when one is installed from the Toolchains list. No new interface was added. Not verified with a real project |
| C/C++ IntelliSense | The Microsoft C/C++ extension is published through Microsoft's Marketplace, whose terms limit it to Microsoft's own products, and it ships programs for the desktop C library. Not offered. A clangd-based extension from Open VSX would need a clangd the phone can start; running Ubuntu's through proot was considered and not shipped (the extension checks the program's version by starting it directly, so a wrapper is fragile). Compiling and running through tasks works as described in section 5 |
| Config defects found | None found by reading the code; no settings changed in this round |
| Remaining | Real-project tests (see DEVICE_TESTS_STABILITY.md). Anything an extension needs that the phone cannot start stays unsupported and is listed in EXTENSION_COMPATIBILITY.md |

## 9. Automatic base folders: rejected

2026-10-18. Not implemented, by decision. Checked: no code creates `Projects`, `Backups` or `Exports`; the app creates only the workspace root, an empty `.nomedia` in it, and (on a fresh private folder) a welcome `README.md`. `scripts/check-no-forced-folders.py` fails if code ever names those folders. It is not yet wired into a workflow; run it from the repository root.

## 10. Group 1 follow-up (reset path validation, Git token protection, workspace path)

2026-10-19. Status: written and checked in a sandbox; **no phone test yet.**

| Item | Found | Fix | Checked |
|------|-------|-----|---------|
| Reset/repair path check | Trusted any path ending in `proot/ubuntu`; no marker, no link or `..` check; a linked `~/proot` would redirect an install or removal | The folder must be exactly the app home plus `proot/ubuntu` once links are resolved, not a link, not in shared storage, with the installer marker (or a genuine Ubuntu os-release for older installs). The installer now writes the markers. Otherwise nothing happens and the reason is shown, before any question | Sandbox: correct path, three marker kinds accepted; unrelated `/tmp/.../proot/ubuntu`, `..`, `//`, link, linked parent, no marker refused; workspace intact in all |
| Read-only folders | `chmod -R` could follow links into a project | `find -type d` (does not follow links) | Sandbox |
| Git guard | Only the phone's `git`; skipped when `-C` or `-c` came first; nothing inside Ubuntu; stored tokens printed by `remote -v` and `config`; the typed line stayed in history | One shared guard file used by the phone and by a `git` wrapper written into Ubuntu; global options skipped; output masked; the history line dropped | Real git, temporary repositories, 25 cases; the Ubuntu wrapper run directly (not inside proot) |
| Logout | Left an empty credentials file | Removed when nothing is left | Sandbox |
| Token file modes | Not verified | Created with umask 077; modes corrected whenever Ubuntu's Git is configured | Sandbox |
| Workspace spelling | Code used `vscodroid`; the designated path is `VSCodroid` | `VSCodroid`; an existing `vscodroid` folder is kept, never duplicated or moved | Code only; Kotlin not compiled, not run |
| Docs | 10 references and one manifest comment used the lower-case spelling; no single description of what lives where | Corrected; STORAGE_MAP.md added | Docs checks |

Unchanged on purpose: the private-storage sign-in, its plain-file form (stated as not encrypted), Source Control and GitHub sign-in, login/logout/check behaviour, the existing reset question and its text.
Remaining limits are listed in STORAGE_MAP.md under "Not covered".
