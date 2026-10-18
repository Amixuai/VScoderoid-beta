# Device tests: storage errors, toolchains, extensions

None has been run on a phone yet. Record the result next to each line.

| # | Test | Expected |
|---|------|----------|
| S1 | In the workspace: `ln -s nothing x` | The normal `ln` error, then one line saying shared storage does not support symbolic links |
| S2 | `touch f; chmod +x f` | Normal error plus the permission-bits line (if the phone refuses it) |
| S3 | `cp -a dir other` where `dir` holds a link | Normal errors; the link line appears |
| S4 | `cp nothere x` | Only `No such file or directory`, no storage line |
| S5 | `tar xf` an archive with links into the workspace | Normal tar errors plus the link line |
| S6 | `ubuntu doctor` in the workspace and in `~` | Workspace: unsupported operations listed; `~`: all as on Linux |
| S7 | `VSCODROID_NO_FS_NOTES=1 chmod +x f` | Only the normal error |
| S8 | Delete nothing, check `ls /storage/emulated/0/vscodroid` after a fresh install | No `Projects`, `Backups` or `Exports` |
| J1 | `ubuntu apt update` then `apt install default-jdk` | Installs; `ubuntu java -version` and `javac -version` print versions |
| J2 | Repeat J1 with airplane mode on | A clear network failure from apt; `ubuntu doctor` says the server is unreachable |
| J3 | Compile and run a `Main.java` with `javac` and `java` in the terminal | Works |
| J4 | Install the Java extension, open a Maven or plain Java project, with a phone-side JDK installed | Language features start; note any missing component |
| J5 | Same with no phone-side JDK | Extension reports it needs a JDK; `ubuntu doctor` shows "phone JDK: none" |
| C1 | Install a clangd extension; `apt install clangd` | Record what the extension reports (it is not expected to start) |
| X1 | `ubuntu doctor` after each failure above | The reported cause matches what you saw |
