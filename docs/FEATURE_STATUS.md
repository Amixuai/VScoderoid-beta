# Feature status

Updated 2026-10-15. "Tested" says where. Nothing marked "pending" has been run on a phone yet.

| Feature | State | Where tested |
|---------|-------|--------------|
| Workspace in public storage (`/storage/emulated/0/vscodroid`), All files access prompt | Built | Owner's Android 13 phone: workspace opened, terminal started in it |
| `.nomedia` in the workspace root | Built | Not checked against phone search (see below) |
| Old private folder no longer reopened after permission is granted | Built | Pending a phone run |
| Open Folder opens Android's folder picker (menu, long-press, Explorer; command override plus WebView fallback) | Built | Pending a phone run |
| Command wrapper: `npm install --no-bin-links`, venv moved to private storage, `ln` copy fallback, filesystem probe | Built | Shell logic tested in the sandbox; phone run pending |
| proot with Ubuntu 24.04, `gcc hello.c` | Built | Owner's Android 13 phone: PASS, glibc 2.39 |
| Routing of gcc, g++, make, cmake, python, pip, cargo, rustc, go, apt, sudo into Ubuntu; `./program` | Built | Sandbox with a stand-in for proot; phone run pending |
| Browser opens after `npm start`, `python -m http.server`, `runserver` | Built | Sandbox with real servers; the Android intent is pending a phone run |
| `ubuntu gui` (Tkinter/Pygame screen in the browser) | Built, experimental | Start/stop logic only; the real desktop pending |
| `ubuntu repair` / `ubuntu reset`, Command Palette "Reinstall Linux Environment" | Built | Sandbox (projects kept, refusals, cancel, repair); phone run pending |
| Git installed in Ubuntu in the background; private sign-in (`ubuntu git-login`), token guard | Built | Sandbox with real git (stored file, mode 600, guard cases); phone run pending |
| Ctrl+C reaches the running command (Ubuntu and phone side); shell stays usable; watcher stops | Built | Real pty in a sandbox with stand-ins; extra-key-row Ctrl unchanged; phone run pending (C1-C7) |
| `type: shell` tasks, Code Runner (terminal mode), NPM Scripts through the routing | Built | Sandbox: compile, run by absolute path, error and exit code; real extensions pending (B1-B7) |
| `type: process` tasks that name a compiler directly | Not supported | Android blocks a program file in app storage; use shell tasks |
| Accurate storage-limit line for failed cp/mv/tar/ln/chmod/chown/mkfifo/mknod; `ubuntu doctor` | Built | Sandbox with stand-ins; phone run pending (S1-S7, X1) |
| `apt install default-jdk` and other packages through Ubuntu's own `apt` | Built (routing existed) | Not run; phone run pending (J1-J3) |
| Java extensions | Depend on a phone-side JDK | Not verified (J4-J5) |
| C/C++ IntelliSense (Microsoft C/C++, clangd) | Not supported | See EXTENSION_COMPATIBILITY.md |
| Automatic `Projects`/`Backups`/`Exports` folders | Rejected, not implemented | `scripts/check-no-forced-folders.py` passes |
| Hiding project files from phone-wide search | **Not solved** | A dot-folder was tried and removed; `.nomedia` covers the media scanner only |
| Intel (x86_64) programs: `ubuntu x86 setup`, `ubuntu x86 run ./prog` (qemu-user inside Ubuntu, amd64 libraries unpacked beside it) | Built, experimental | Setup and run commands checked in the sandbox with stand-ins; real emulation pending a phone run. Slow by nature; prebuilt binaries only |
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
| `EXTENSION_COMPATIBILITY.md`, `DEVICE_TESTS_STABILITY.md` (new) | Which extensions work and why; phone tests for storage errors, toolchains, extensions |
| `DEVICE_TESTS_BUILD_CTRLC.md` (new) | Phone tests for build tasks, extensions and Ctrl+C |
| `ANDROID_LIMITATION_LOG.md`, `DEVICE_TESTS_RECOVERY_GIT.md` (new) | Investigation record and phone tests for Ubuntu recovery and Git |
| `README.md`, `USER_GUIDE.md`, `UBUNTU_ROUTING.md`, `03-ARCHITECTURE.md`, `06-SECURITY.md`, `PRIVACY_POLICY.md`, `08-RISK_MATRIX.md`, `11-GLOSSARY.md`, `12-IMPLEMENTATION_PLAN.md` | Lines added for recovery, Git and token handling |
| `FINAL_5_PERCENT.md`, `UBUNTU_ROUTING.md`, `SYMLINKS_ON_PUBLIC_STORAGE.md`, `PROOT_PROTOTYPE.md` | Detail for the pieces above |
