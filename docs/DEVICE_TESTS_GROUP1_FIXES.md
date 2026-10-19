# Device tests: Group 1 fixes (reset path validation, Git token protection, workspace path)

None has been run on a phone yet. Record the result next to each line.

| # | Test | Expected |
|---|------|----------|
| P1 | Put a file in `/storage/emulated/0/VSCodroid/p/a.txt`. Run `ubuntu reset`, answer `y` | Ubuntu reinstalls; `a.txt` is untouched |
| P2 | In Ubuntu: `ubuntu ln -s /storage/emulated/0/VSCodroid/p /root/proj` (may fail on shared storage; the link is made inside Ubuntu). Run `ubuntu reset --yes` | The project and its files are untouched |
| P3 | `ls -la ~/proot/ubuntu/.vscodroid-ubuntu` after a fresh `ubuntu setup` | The marker exists |
| P4 | Rename the marker and the os-release away inside `~/proot/ubuntu`, then `ubuntu reset` | "nothing was removed ... not recognised" |
| P5 | Replace `~/proot` by a link to another folder, then `ubuntu reset` | Refused; the other folder untouched. Undo the link |
| R1 | Interrupt an install (airplane mode during `ubuntu setup`), then `ubuntu reset` | Accepted (the installing marker), reinstalls |
| G1 | `git remote add origin https://USER:TOKEN@github.com/o/r.git` in a project | Refused; `.git/config` has no token |
| G2 | Same with `git -C <project> remote add ...`, `git clone https://TOKEN@github.com/o/r.git`, `git push https://USER:TOKEN@...` | Refused |
| G3 | The same commands inside the Ubuntu shell (`ubuntu`) | Refused |
| G4 | `git remote add origin https://github.com/o/r.git`, an SSH remote, then clone, commit, push, pull a real repository with `ubuntu git-login` | Work as before |
| G5 | Type a refused line, then run `history` (phone shell and Ubuntu shell) | The token line is not in the history |
| G6 | In a repo whose config already holds a token (made by an old build), `git remote -v` | Shows `https://***@...` |
| G7 | `ubuntu git-login`, `ubuntu git-check`, `ls -l ~/.vscodroid/ubuntu-git` | Folder 700, credentials 600, "plain file, not encrypted" |
| G8 | `ubuntu git-logout HOST` | That host's entry is gone; the file is removed when none is left |
| S1 | VS Code Source Control: sign in with GitHub, clone, commit, push | Works as before |
| W1 | Look at the workspace in the file manager | The folder is `VSCodroid`; no `Projects`, `Backups`, `Exports` |
| W2 | `npm install <package>` in a project in the workspace | `node_modules`, `package.json`, `package-lock.json` appear in the project, visible in the file manager |
| W3 | `npm run <script>` that calls an installed command | Runs |
| W4 | If a `vscodroid` (lower case) folder exists from an older build | The app keeps using it; no second folder appears |
