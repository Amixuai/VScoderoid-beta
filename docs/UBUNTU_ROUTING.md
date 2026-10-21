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
  An Intel program found the same way is run through qemu. `sudo -i` opens an Ubuntu
  shell. `cargo` keeps its build folder inside Ubuntu (`cargo run` works).
- **Python environments.** `python -m venv .venv` creates the environment inside
  Ubuntu; `.venv/bin/activate` points to it. `pip install` outside an environment
  is allowed (the system "externally managed" lock is turned off).
- **Opt out.** `command cmd` runs the phone's own command, if it has one (`VSCODROID_NO_UBUNTU=1` does the same
  for tasks and tests).
- **Setup.** The first use of a tool that lives in Ubuntu installs the Ubuntu system by itself (the same script as the
  test script), under the package lock, after checking free space. A folder left by an interrupted install is removed
  first, only if it is positively the app's own. If the download or the install fails, the message says so and it is
  tried again next time.

## Graphical programs (Tkinter, Pygame) - experimental

Running a Python program that imports `tkinter`, `pygame`, `turtle`, `pyglet` or `kivy` starts a virtual screen
(Xtigervnc), a window manager (openbox) and noVNC inside Ubuntu and opens the screen in the phone's browser at
`http://localhost:6080`; the program draws on it. The first time, a terminal is asked once ("Download the graphical
desktop now? [Y/n]") because of the few hundred MB; a task or other run with no terminal does not download anything and
says so. The desktop keeps running until the app is closed or Ubuntu is reinstalled. It is not shown inside a VS Code
tab yet; the page opens in the browser.

## Opening a dev server

After `npm start`, `npm run dev|serve|preview`, `python -m http.server` and
`manage.py runserver`, the likely ports (or the one named with `--port`/`PORT`)
are tried once a second for two minutes; the first that starts answering is
opened in the phone's browser through Android's VIEW intent. A port that was
already answering is ignored. `VSCODROID_NO_PREVIEW=1` turns it off; `xdg-open
<address>` opens an address by hand.

## Intel (x86_64) programs - experimental

Starting an Intel Linux program (`./prog`, recognised by the processor field of its ELF header) installs qemu and unpacks
an amd64 Ubuntu Base into `~/proot/ubuntu-amd64` the first time, with a notice, and runs the program through qemu-user
with the amd64 libraries mounted at `/opt/amd64`. Slow; prebuilt programs only; only programs that get a `./name`
function (see Built programs) are routed.

## Repair and reinstall

Ordinary damage repairs itself and removes nothing: an interrupted Ubuntu install is redone, and a half-configured
package set (`dpkg --audit` not empty) is finished with `dpkg --configure -a` before the next `apt`/`dpkg` run (and
once more after a failed `apt-get` of the app's own). The only destructive action is the Command Palette entry
**VSCodroid: Reinstall Linux Environment** (saf-bridge 1.12.0), which opens a terminal that calls the reinstall
function directly, asks "Proceed? [Y/n]", and waits for Enter at the end. Only the folders `~/proot/ubuntu` and
`~/proot/ubuntu-amd64` in private storage are removed; any other path is refused, and so is anything under `/storage`,
`/sdcard` or `/mnt`. Links inside Ubuntu are removed, never followed.

## Git inside Ubuntu

Installed once, in the background, the first time Ubuntu is ready (git, ca-certificates, openssh-client). Settings and
sign-in live in `~/.vscodroid/ubuntu-git` (shown in Ubuntu as `/root/.vscodroid-git`), so a reset keeps them. The helper
is git's own `store`, pointed at that private file: Git asks for the username and token itself when it needs them, and
`git credential reject` removes them. The folder and file modes are kept at 700 and 600 automatically. All package
installs (first use of a tool, the Git setup, the desktop, your own `apt`) take turns through one lock, because dpkg
allows one at a time. The phone's `git` refuses remote addresses that carry a token (`VSCODROID_NO_TOKEN_GUARD=1` turns
that off).

## Ctrl+C and process groups

A foreground command typed in the terminal runs under a guest shell with job control, so it has its own process group
and the terminal; Ctrl+C reaches that command and not proot. Programs with their own interrupt handling run it;
an Ubuntu shell (`sudo -i`) at its prompt only cancels the line. Off with `VSCODROID_UB_NO_JOB=1`. `--kill-on-exit` still ends everything
when proot ends. A program just built (`gcc ... -o name`, `rustc`, `make`) can be started as `name` by its path as typed,
by its absolute path (Code Runner does this), or as `./name`; a bare name is never defined.

## Tasks and extensions

`type: shell` tasks and Code Runner (set to run in the terminal) run commands through the routing. `type: process` tasks
(and a `make` recipe, which runs under `/system/bin/sh`) that name `gcc`, `g++`, `cc`, `c++`, `cpp`, `cmake`, `cargo`,
`rustc`, `go` or `gofmt` reach the routing through a launcher the app writes for each name (`ToolchainManager.addUbuntuRows`,
using the existing exec trampoline). The arguments are passed one by one, the exit status is the command's own, and a
toolchain that ships its own `go` or `cargo` keeps the name. `make`, `python` and `pip` are not given a launcher: the
phone has its own, and a program that starts them by name gets those. Status: written and checked with a stand-in launcher
in the sandbox; the Kotlin is not compiled here and nothing is run on a phone yet.

## Errors from shared storage

When `cp`, `mv`, `tar`, `ln`, `chmod`, `chown`, `chgrp`, `mkfifo` or `mknod` fails in shared storage because the storage
cannot do that, the tool's own error is shown unchanged and one line names the limit. Nothing is added for other errors,
and `VSCODROID_NO_FS_NOTES=1` turns it off. There is no `ubuntu doctor` command: a user needs no diagnostic command to use
the tools. The checks (proot present, Ubuntu present and startable, packages consistent, free space, what the folder
supports) are an internal function that the install path runs after a failure; it writes `~/.vscodroid/ubuntu.log`, and the
automated test calls it. The old description of `doctor` also listed a network check and a tool inventory (`java`, `clangd`
...); those are not provided any more.

## Reset path validation and the Git guard (2026-10-19)

The reinstall acts only on a folder it recognises as the app's own Ubuntu (see STORAGE_MAP.md) and otherwise
stops with the reason; the same test guards the clean-up of an interrupted install. The `git` inside Ubuntu is `/usr/local/bin/git`, written from `git-token-guard.sh`, the same file the
phone's `git` uses: it refuses remote addresses that carry a password or token, hides stored ones in output, and the typed
line is dropped from history. The sign-in file's modes are corrected each time Ubuntu's Git is configured.