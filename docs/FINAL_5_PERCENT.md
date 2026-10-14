# The last 5%: status

| Item | Status |
|---|---|
| Hide projects from phone search | Done: workspace root is `.VSCodroid` (dot folder) plus `.nomedia` |
| Open the browser for a dev server | Done and tested with real servers |
| Graphical programs (Tkinter/Pygame) | Written, NOT tested on a phone (`ubuntu gui`) |
| Intel (x86_64) programs | Not built |
| USB / Arduino flashing | Not built |
| Docker / containers | Not built; likely only a narrow subset is possible |

## Hiding projects from search

The media scanner skips folders whose name starts with a dot, and `.nomedia` stays
in the root as a second guard. A phone's own search app may still read such a
folder; check by searching for a project file name after updating. A file manager
and the folder picker show the folder once "show hidden files" is turned on. An
existing visible folder (`vscodroid`, `VSCodroid`) is not moved; a folder you opened
before is reopened as it was, and only a new default workspace uses `.VSCodroid`.

A fully search-proof alternative would be a DocumentsProvider: projects kept in
private storage and shown in the system Files app as a "VSCodroid" location, as
Termux does. Private storage also allows symbolic links, but file managers that
browse `/storage/emulated/0` directly would not see it. It is a larger change.

## Not built, and what each needs

- **Intel programs.** proot can run them through qemu-user (`proot -q`) in an
  amd64 Ubuntu root. Needs a qemu-user binary built for Android shipped with the
  app (a new bundled binary, with its licence and size checks), an amd64 root
  filesystem (same Ubuntu server), and a slow-by-design emulation. Box64 is faster
  but is not packaged for Android/Ubuntu arm64 as a ready download.
- **USB / Arduino.** Android's USB host API works, but programs inside proot cannot
  see `/dev/ttyUSB*`. The route is a small Android service (a USB-serial library)
  that serves the device on a local TCP port, with `esptool --port rfc2217://...`
  or `avrdude -P net:...` on the Ubuntu side. WebUSB does not exist in Android's
  WebView. Needs Kotlin work, a Gradle dependency and a real board to test.
- **Docker.** Needs kernel features (namespaces, cgroups) a normal phone does not
  give an app, and proot cannot run inside proot. Podman rootless is out. udocker
  could run from the phone's own side using the bundled proot; that is a research
  task, and only simple images would work.
