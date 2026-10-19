# Where things live

2026-10-19. "Checked" means the behaviour was run in a sandbox with real tools; nothing here has been run on a phone yet.

| What | Where | Why |
|------|-------|-----|
| Your projects: source, `package.json`, lockfiles, `node_modules`, project config, files you download into a project, build outputs a project makes | The Public Workspace, `/storage/emulated/0/VSCodroid` (or a folder you picked) | So the Android file manager can see, copy and share them. The app never copies a project elsewhere |
| The Public Workspace folder itself | Named `VSCodroid`. If an earlier build made `vscodroid` and the storage tells the two apart, that folder is kept; no second one is made and nothing is renamed or moved | Shared storage is normally case-insensitive, so both are the same folder there. Not confirmed on a phone |
| The Ubuntu system | `~/proot/ubuntu` in private storage (`~/proot/ubuntu-amd64` for Intel programs) | It is the system's files, not yours; programs in it must be able to run |
| npm and other tool caches, user configuration | The private home (`~/.npm`, `~/.config`, ...) | As on a PC they sit beside the user, not in a project |
| Git sign-in for Ubuntu's git, and its settings | `~/.vscodroid/ubuntu-git` in private storage, shown in Ubuntu as `/root/.vscodroid-git` | Never in a project, never in a backup |
| Python virtual environments | Inside Ubuntu, with `.venv/bin/activate` left in the project | Shared storage cannot hold the links or run the programs an environment needs |
| Programs you build in a project | The project folder; started through a private copy | Android will not run a program stored in shared storage |
| Everything else the editor needs (runtime, extensions, settings) | Private storage | System files |

Downloads go where you choose; nothing is forced into `VSCodroid`.

## What protects what (and what does not)

| Protection | State |
|------------|-------|
| `ubuntu reset` and `repair` remove only `~/proot/ubuntu*`, and only a folder recognised as the app's own: exactly the app's home plus `proot/ubuntu` once links are resolved, not itself a link, with the installer's marker (or a genuine Ubuntu os-release for older installs). Otherwise nothing is removed and the reason is shown | Checked in a sandbox with a stand-in for proot |
| The Public Workspace is never touched by reset or repair, including when a link inside Ubuntu points at a project | Checked in a sandbox |
| A remote address carrying a password or token is refused by the phone's `git` and by the `git` inside Ubuntu (also after `-C <path>` and `-c`); one already stored is hidden when remotes or config are listed; a typed line carrying one is dropped from shell history | Checked with real git and real interactive shells; the Ubuntu wrapper was run directly, not inside proot |
| The Git sign-in is a plain file in private storage (folder 700, file 600; `ubuntu git-check` repairs loose modes). **It is not encrypted** | Checked in a sandbox. No Keystore encryption exists or is claimed |
| Tokens never printed by the app's own messages or its setup log | Checked in a sandbox |

## Not covered

- A token typed into other commands (`curl`, a script) is not blocked; only the history line is dropped.
- A program inside Ubuntu that runs `/usr/bin/git` by its full path skips the guard.
- Protection is for the listed git commands; a token passed some other way (a header, an environment variable) is not inspected.
- Anything an Android phone can read from the app's private storage can read the sign-in file.
