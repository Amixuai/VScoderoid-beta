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
prefix. `ubuntu git-login` reads the token hidden and passes it on standard input. Ubuntu's own `git` inside the Ubuntu
shell is not guarded; `ubuntu git-check` warns about a token already in `.git/config`.

## 5. Build tasks and extensions (tasks.json, Code Runner, NPM Scripts)

2026-10-17. Same seven steps.

| Question | Finding |
|----------|---------|
| `type: shell` tasks | VS Code runs them as `bash -c "<command>"` in the terminal. `$BASH_ENV` is read by that shell, so the routing functions (gcc, python, cargo ...) exist and the command runs in Ubuntu. Working directory, environment and exit code come through; a compile error returns a normal error text and exit code 1 (checked in a sandbox, so problem matchers see what they expect) |
| `type: process` tasks, and extensions that start a compiler directly (for example a C/C++ extension's own build task) | **Not supported, with a reason.** They look for a program file named `gcc`. Android's SELinux policy does not allow starting a file kept in app storage (the reason the commands are shell functions in the first place), so a `gcc` file on PATH cannot be made. A native launcher in the app could do it; that is app code that cannot be built or tested here. Use a shell task instead |
| Code Runner | Its default shows output in the Output panel through a shell that is not ours, so routed commands would not be found. The app now ships `code-runner.runInTerminal: true`, which makes it use the integrated terminal, where they exist. It starts a program built from a C file by its **absolute path**; after a compile the app now defines that path (and `./name`) so it runs in Ubuntu |
| NPM Scripts | VS Code's npm tasks are shell tasks; `npm` already works. Unchanged |
| Result | Written; sandbox-tested with stand-ins for proot and the editor. **Not run with the real extensions on a phone** |
| Remaining limits | `type: process` tasks; paths with spaces or odd characters get no program name defined (use `ubuntu ./prog`); the Code Runner behaviour above is from its documented setting, not run here |

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
