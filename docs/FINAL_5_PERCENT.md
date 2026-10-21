# The last 5%: status

| Item | Status |
|---|---|
| Hide projects from phone search | **Not solved.** A dot folder was tried and removed; `.nomedia` covers the media scanner only |
| Open the browser for a dev server | Done and tested with real servers |
| Graphical programs (Tkinter/Pygame) | Written, NOT tested on a phone (starts automatically for Python programs that import tkinter, pygame ...) |
| Intel (x86_64) programs | Built, experimental (automatic for `./prog` Intel programs), not run on a phone |
| USB / Arduino flashing | Not built |
| Docker / containers | Not built; likely only a narrow subset is possible |

## Hiding projects from search

The workspace is `/storage/emulated/0/VSCodroid` with an empty `.nomedia` in it. That keeps the media
scanner (Gallery, Recent) away. It does not stop every phone-wide search app from listing the files.
A dot-folder (`.VSCodroid`) was tried to hide them and did not work, so it was removed.

What would work: a DocumentsProvider. Projects stay in private storage, which no search app can read,
and appear in the system Files app as a "VSCodroid" location, as Termux does. Private storage also
allows symbolic links. The cost: file managers that browse `/storage/emulated/0` directly would not
see the projects, which is the opposite of what the workspace move was for. It is a larger change and
a product decision.

## Intel programs

Starting an Intel program installs `qemu-user-static` inside the arm64 Ubuntu and unpacks an amd64 Ubuntu Base
beside it (first time only); it then runs the prebuilt Intel Linux program through qemu with the amd64
libraries at `/opt/amd64`. This needs no new binary in the app. It is an emulated processor, so it is
slow, and it runs one program at a time; it does not make the shell an Intel one. Box64 is faster but
is not offered as a ready download for Ubuntu arm64.

## Not built, and what each needs

- **USB / Arduino.** Android's USB host API works, but programs inside proot cannot
  see `/dev/ttyUSB*`. The route is a small Android service (a USB-serial library)
  that serves the device on a local TCP port, with `esptool --port rfc2217://...`
  or `avrdude -P net:...` on the Ubuntu side. WebUSB does not exist in Android's
  WebView. Needs Kotlin work, a Gradle dependency and a real board to test.
- **Docker.** Needs kernel features (namespaces, cgroups) a normal phone does not
  give an app, and proot cannot run inside proot. Podman rootless is out. udocker
  could run from the phone's own side using the bundled proot; that is a research
  task, and only simple images would work.
