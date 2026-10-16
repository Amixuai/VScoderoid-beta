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
