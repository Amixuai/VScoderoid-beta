# Device tests: Ubuntu recovery and Git

> **Historical (superseded by Update-11).** The commands in this file (`ubuntu setup`, `ubuntu reset`, `ubuntu repair`,
> `ubuntu doctor`, `ubuntu git-login` and friends) no longer exist. Ubuntu now installs itself on first use, repairs a cut-off
> install by itself, and is reinstalled only from the Command Palette ("VSCodroid: Reinstall Linux Environment"). Read each
> row as the behaviour to check, triggered the new way. See docs/UBUNTU_ROUTING.md.

Run on a phone; record the result next to each line. None has been run yet.

| # | Test | Expected |
|---|------|----------|
| R1 | Put a file in `/storage/emulated/0/VSCodroid/p/a.txt`, run `ubuntu reset`, answer `y` | Question text appears exactly; Ubuntu reinstalls; `a.txt` still there |
| R2 | `ubuntu reset`, answer `n` | "cancelled", nothing changed |
| R3 | Command Palette: **VSCodroid: Reinstall Linux Environment** | A terminal opens and asks the same question |
| R4 | Break Ubuntu on purpose (`ubuntu rm /bin/sh`), then run `ubuntu repair` | Detects damage, reinstalls |
| R5 | `ubuntu repair` on a healthy Ubuntu | "looks healthy", nothing removed |
| R6 | After reset, `ubuntu git-check` | Sign-in still saved |
| G1 | After first Ubuntu setup, wait, `cat ~/.vscodroid/git-setup.log`, `ubuntu git --version` | "done"; version prints |
| G2 | Source Control: clone a private repo, commit, push, pull | Works as before |
| G3 | `ubuntu git-login`, then `ubuntu git clone https://github.com/OWNER/REPO.git` | Clones without asking again |
| G4 | `ls -l ~/.vscodroid/ubuntu-git/credentials`; search the project folder for the token | Mode 600; token not found in any project file |
| G5 | `git remote add x https://user:TOKEN@github.com/o/r.git` | Refused with the explanation |
| G6 | `ubuntu git-logout`, then clone a private repo | Asks for sign-in again |
| G7 | Run `apt install` in one terminal while the Git setup runs | The second waits, neither fails |
