# Ubuntu routing (gcc, g++, make, python, pip, cargo, go, apt)

`assets/ubuntu-env.sh` is sourced by `command-wrapper.sh`, so it exists only on
Android (`VSCODROID_PLATFORM=android`). A desktop build never loads it.

Routed names: gcc g++ cc c++ cpp make cmake python python3 pip pip3 cargo rustc
go gofmt apt apt-get apt-cache dpkg, plus `sudo` (already root inside Ubuntu).
Not routed: node, npm, git.

Each call starts proot with the Ubuntu system from `~/proot/ubuntu` (private
storage), binds the current folder at the same path, and runs the command there.
Files a command writes land in the visible workspace.

## First use

The first time a group is used its packages are installed (once, a few minutes,
needs internet): build = build-essential + cmake; python = python3, pip, venv,
dev; rust = cargo, rustc; go = golang-go. If that fails and the phone has its own
version of the command (python, make), the phone's version runs instead.

## Things that differ from a PC, on purpose or by necessity

- **Built programs.** Android will not start a program stored in shared storage.
  So that `./hello` works after `gcc hello.c -o hello`, a function named `./hello`
  is defined for each program built in the folder (after a compile, and at each
  prompt when the folder changes); it runs a private copy inside Ubuntu. Only
  files that start with the Linux program header and have a plain name get one.
  `ubuntu ./hello` does the same explicitly, and `ubuntu` alone opens an Ubuntu
  shell. `cargo` keeps its build folder inside Ubuntu (`cargo run` works).
- **Python environments.** `python -m venv .venv` creates the environment inside
  Ubuntu; `.venv/bin/activate` points to it. `pip install` outside an environment
  is allowed (the system "externally managed" lock is turned off).
- **Opt out.** `VSCODROID_NO_UBUNTU=1 cmd` or `native cmd` runs the phone's own
  command.
- **Setup.** `ubuntu setup` installs the Ubuntu system (same as the test script).

## Graphical programs (Tkinter, Pygame) - experimental

`ubuntu gui start` installs a virtual screen (Xtigervnc), a window manager
(openbox) and noVNC inside Ubuntu, starts them, and opens the screen in the
phone's browser at `http://localhost:6080`. While it runs, `python3 game.py` and
other routed commands draw on it. `ubuntu gui stop` ends it. It needs a few
hundred MB the first time. It is not shown inside a VS Code tab yet; the page
opens in the browser.

## Opening a dev server

After `npm start`, `npm run dev|serve|preview`, `python -m http.server` and
`manage.py runserver`, the likely ports (or the one named with `--port`/`PORT`)
are tried once a second for two minutes; the first that starts answering is
opened in the phone's browser through Android's VIEW intent. A port that was
already answering is ignored. `VSCODROID_NO_PREVIEW=1` turns it off; `xdg-open
<address>` opens an address by hand.

