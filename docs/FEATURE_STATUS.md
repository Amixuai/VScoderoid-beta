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
| `FINAL_5_PERCENT.md`, `UBUNTU_ROUTING.md`, `SYMLINKS_ON_PUBLIC_STORAGE.md`, `PROOT_PROTOTYPE.md` | Detail for the pieces above |
