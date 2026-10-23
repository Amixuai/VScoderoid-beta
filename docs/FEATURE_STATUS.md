# Feature status

Updated 2026-10-15. "Tested" says where. Nothing marked "pending" has been run on a phone yet.

| Feature | State | Where tested |
|---------|-------|--------------|
| Workspace in public storage (`/storage/emulated/0/VSCodroid`), All files access prompt | Built | Owner's Android 13 phone: workspace opened, terminal started in it |
| `.nomedia` in the workspace root | Built | Not checked against phone search (see below) |
| Old private folder no longer reopened after permission is granted | Built | Pending a phone run |
| Open Folder opens Android's folder picker (menu, long-press, Explorer; command override plus WebView fallback) | Built | Pending a phone run |
| Command wrapper: `npm install --no-bin-links`, `ln` copy fallback, filesystem probe | Built | Shell logic tested in the sandbox; phone run pending |
| `python3 -m venv`: real environment where the folder can hold one; in shared storage the environment lives in Ubuntu (or private storage) with `bin/activate`, `python`, `python3`, `pip`, `pip3` usable in the terminal; every failure reported | Fixed in Update-14; sandbox-tested with real Python and pip | Phone run pending. A program that starts `.venv/bin/python` itself cannot |
| Variables you export reach commands run in Ubuntu | Fixed in Update-14; sandbox-tested | Phone run pending |
| proot with Ubuntu 24.04, `gcc hello.c` | Built | Owner's Android 13 phone: PASS, glibc 2.39 |
| Routing of gcc, g++, make, cmake, python, pip, cargo, rustc, go, apt, sudo into Ubuntu; `./program` | Built | Sandbox with a stand-in for proot; phone run pending |
| Browser opens after `npm start`, `python -m http.server`, `runserver` | Built | Sandbox with real servers; the Android intent is pending a phone run |
| Graphical programs (Tkinter/Pygame screen in the browser), started automatically by a Python program that imports them | Built, experimental | Detection and the no-terminal case checked in the sandbox; the real desktop pending a phone |
| Tools installed with `apt` and not routed by name (`java`, `javac`, `clang`, `gdb` ...) run by their own name in the terminal and shell tasks (not-found handler) | Built, sandbox-tested, NOT run on a phone |
| Automatic first-use install and clean-up of an interrupted one; automatic `dpkg --configure -a`; Command Palette "Reinstall Linux Environment" (runs the reinstall directly) | Built | Sandbox (projects kept, refusals, cancel, repair); phone run pending |
| Git installed in Ubuntu in the background; private sign-in (Git's own prompt and `store` helper), token guard | Built | Sandbox with real git (stored file, mode 600, guard cases); phone run pending |
| Ctrl+C reaches the running command (Ubuntu and phone side); shell stays usable; watcher stops | Built | Real pty in a sandbox with stand-ins; extra-key-row Ctrl unchanged; phone run pending (C1-C7) |
| `type: shell` tasks, Code Runner (terminal mode), NPM Scripts through the routing | Built | Sandbox: compile, run by absolute path, error and exit code; real extensions pending (B1-B7) |
| `type: process` tasks that name `gcc`, `g++`, `cc`, `c++`, `cpp`, `cmake`, `cargo`, `rustc`, `go`, `gofmt` | Written, NOT run on a phone, Kotlin not compiled | Launcher rows through the exec trampoline; launcher checked in the sandbox |
| Accurate storage-limit line for failed cp/mv/tar/ln/chmod/chown/mkfifo/mknod | Built | Sandbox with stand-ins; phone run pending (S1-S7, X1) |
| `apt install default-jdk` and other packages through Ubuntu's own `apt` | Built (routing existed) | Not run; phone run pending (J1-J3) |
| Java extensions | Depend on a phone-side JDK | Not verified (J4-J5) |
| C/C++ IntelliSense (Microsoft C/C++, clangd) | Not supported | See EXTENSION_COMPATIBILITY.md |
| Automatic `Projects`/`Backups`/`Exports` folders | Rejected, not implemented | `scripts/check-no-forced-folders.py` passes |
| Reset/repair only act on a positively recognised app-owned Ubuntu (path, link and marker checks) | Built | Sandbox with a stand-in for proot; phone run pending (P1-P5, R1) |
| Git token guard for the phone's git and Ubuntu's git; masking; history; logout cleanup; mode checks | Built | Real git in temporary repositories and real interactive shells; the Ubuntu wrapper run directly, not inside proot; phone run pending (G1-G8, S1) |
| Public Workspace spelled `VSCodroid`, an existing `vscodroid` kept | Built (Kotlin not compiled) | Not run; phone run pending (W1-W4) |
| Git sign-in encryption | Not built, not claimed | Plain file in private storage |
| Hiding project files from phone-wide search | **Not solved** | A dot-folder was tried and removed; `.nomedia` covers the media scanner only |
| Intel (x86_64) programs started as `./prog` (set up on first use; qemu-user inside Ubuntu, amd64 libraries unpacked beside it) | Built, experimental | Detection, first-use setup and the qemu call checked in the sandbox with stand-ins; real emulation pending a phone run. Slow by nature; prebuilt binaries only |
| USB / Arduino flashing | Not built | Needs an Android USB service and a serial-over-TCP bridge |
| Docker / containers | Not built | Not possible in the usual sense on a phone without root; udocker is research |
| CI fixes from the 2026-10-13 report (attribution, unit tests, libandroid-shmem) | Applied | Pending a green build |

## Documents changed for this status (2026-10-15)

| Document | Change |
|----------|--------|
| `PRIVACY_POLICY.md` | Names `MANAGE_EXTERNAL_STORAGE`; five permissions of its own; new "Linux Environment" section; date moved |
| `06-SECURITY.md` | Permission moved from "not held" to held; new 4.3 on All files access |
| `10-RELEASE_PLAN.md` | Permissions row corrected (seven on the listing, five ours) |
| `03-ARCHITECTURE.md` | Storage design superseded note: public storage, picker, wrapper, Ubuntu routing |
| `USER_GUIDE.md` | File locations, Open Folder, terminal behaviour |
| `08-RISK_MATRIX.md`, `11-GLOSSARY.md` | New risks and terms |
| `PLAY_STORE_ALL_FILES_ACCESS.md` (new) | Declaration answers and fallback |
| `FEATURE_STATUS.md` (new) | This page |
| `STORAGE_MAP.md`, `DEVICE_TESTS_GROUP1_FIXES.md` (new) | Where things live and what protects them; phone tests for the Group 1 fixes |
| `EXTENSION_COMPATIBILITY.md`, `DEVICE_TESTS_STABILITY.md` (new) | Which extensions work and why; phone tests for storage errors, toolchains, extensions |
| `DEVICE_TESTS_BUILD_CTRLC.md` (new) | Phone tests for build tasks, extensions and Ctrl+C |
| `ANDROID_LIMITATION_LOG.md`, `DEVICE_TESTS_RECOVERY_GIT.md` (new) | Investigation record and phone tests for Ubuntu recovery and Git |
| `README.md`, `USER_GUIDE.md`, `UBUNTU_ROUTING.md`, `03-ARCHITECTURE.md`, `06-SECURITY.md`, `PRIVACY_POLICY.md`, `08-RISK_MATRIX.md`, `11-GLOSSARY.md`, `12-IMPLEMENTATION_PLAN.md` | Lines added for recovery, Git and token handling |
| `FINAL_5_PERCENT.md`, `UBUNTU_ROUTING.md`, `SYMLINKS_ON_PUBLIC_STORAGE.md`, `PROOT_PROTOTYPE.md` | Detail for the pieces above |
