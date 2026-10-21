# VSCodroid: routes compilers and runtimes into the hidden Ubuntu system.
#
# Sourced by command-wrapper.sh, so it is active only on Android. Type the same
# commands as on a PC (gcc, g++, make, python, pip, cargo, go, apt ...) and they
# run inside the Ubuntu system the app keeps in its PRIVATE storage, started
# through proot. The current folder is passed through at the same path, so what
# a command writes lands in your visible workspace.
#
# Nothing here has to be typed by the user. The first use of a tool installs the
# Ubuntu system by itself; an interrupted install is cleaned up and redone; a
# half-finished package install is completed before the next apt/dpkg run; a
# program built in the workspace starts with ./name; a Python program that
# imports Tkinter or Pygame gets the graphical desktop; an Intel (x86_64) program
# is run through qemu. Not routed: node and npm (they run natively), git and the
# editor itself.
#
# Standard ways to step outside the routing:  `command gcc ...` runs the phone's own
# gcc if there is one; `sudo -i` opens a shell inside Ubuntu.
# The one destructive action, reinstalling Ubuntu, is the Command Palette entry
# "VSCodroid: Reinstall Linux Environment"; it asks before it removes anything.
#
# Android will not start a program that is stored in shared storage (the
# workspace). So that `./hello` works after `gcc hello.c -o hello` as on a PC,
# a function named ./hello is defined for each program built there; it runs a
# private copy inside Ubuntu.

[ "${VSCODROID_PLATFORM-}" = "android" ] || return 0
declare -F __vscodroid_ub_loaded >/dev/null 2>&1 && return 0
__vscodroid_ub_loaded() { :; }

__vscodroid_ub_root() { printf '%s' "${VSCODROID_UBUNTU_ROOT:-$HOME/proot/ubuntu}"; }

__vscodroid_ub_git_dir() { printf '%s' "$HOME/.vscodroid/ubuntu-git"; }

__vscodroid_ub_ready() {
  local r; r=$(__vscodroid_ub_root)
  [ -n "${VSCODROID_PROOT-}" ] && [ -x "${VSCODROID_PROOT-}" ] && [ -x "${PROOT_LOADER-}" ] &&
    [ ! -e "$r/.vscodroid-installing" ] &&
    { [ -e "$r/bin/sh" ] || [ -L "$r/bin/sh" ]; }
}

# Developer log, never shown in the normal terminal flow.
__vscodroid_ub_log() {
  mkdir -p "$HOME/.vscodroid" 2>/dev/null
  printf '%s %s\n' "$(date '+%F %T' 2>/dev/null)" "$*" >> "$HOME/.vscodroid/ubuntu.log" 2>/dev/null
  return 0
}

# Runs a command inside Ubuntu, in the current folder.
__vscodroid_ub_exec() {
  local root cwd d
  root=$(__vscodroid_ub_root)
  cwd=$(pwd -P 2>/dev/null || pwd)
  local -a bind=(-b /dev -b /proc -b /sys)
  [ -d /storage/emulated/0 ] && bind+=(-b /storage/emulated/0)
  case "$cwd" in /storage/emulated/0|/storage/emulated/0/*) ;; *) bind+=(-b "$cwd") ;; esac
  [ -n "${VSCODROID_UB_EXTRA_BIND-}" ] && bind+=(-b "$VSCODROID_UB_EXTRA_BIND")
  # Ubuntu's git settings and sign-in live in the app's private storage, outside the
  # Ubuntu system, so a reset or repair of Ubuntu keeps them (see __vscodroid_ub_git_dir).
  local gitdir; gitdir=$(__vscodroid_ub_git_dir)
  [ -d "$gitdir" ] && bind+=(-b "$gitdir:/root/.vscodroid-git")

  local gpath=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  local -a envv=(HOME=/root "TERM=${TERM:-xterm}" LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive
                 PIP_BREAK_SYSTEM_PACKAGES=1 PIP_ROOT_USER_ACTION=ignore)
  if [ -n "${VSCODROID_VENV-}" ]; then
    envv+=("VIRTUAL_ENV=$VSCODROID_VENV"); gpath="$VSCODROID_VENV/bin:$gpath"
  fi
  envv+=("PATH=$gpath")
  [ -f "$gitdir/gitconfig" ] && envv+=(GIT_CONFIG_GLOBAL=/root/.vscodroid-git/gitconfig)
  [ -n "${VSCODROID_NO_TOKEN_GUARD-}" ] && envv+=(VSCODROID_NO_TOKEN_GUARD=1)
  # While the graphical desktop runs, programs draw on it.
  if [ -f "$HOME/.vscodroid/gui.pid" ] && kill -0 "$(cat "$HOME/.vscodroid/gui.pid" 2>/dev/null)" 2>/dev/null; then
    envv+=(DISPLAY=:1)
  fi
  # Built programs cannot run from shared storage, so Rust's build folder stays
  # inside Ubuntu, one per project, unless the user chose one.
  if [ -n "${CARGO_TARGET_DIR-}" ]; then
    envv+=("CARGO_TARGET_DIR=$CARGO_TARGET_DIR")
  else
    d=$cwd
    while [ -n "$d" ] && [ "$d" != / ]; do
      if [ -f "$d/Cargo.toml" ]; then
        envv+=("CARGO_TARGET_DIR=/root/.cache/vscodroid-target/$(printf '%s' "$d" | cksum | cut -d' ' -f1)")
        break
      fi
      d=${d%/*}
    done
  fi

  local -a pre=()
  [ "$(cat "$HOME/.vscodroid/proot-mode" 2>/dev/null)" = noseccomp ] && pre=(env PROOT_NO_SECCOMP=1)
  [ -f "$root/etc/resolv.conf" ] || { rm -f "$root/etc/resolv.conf"; printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$root/etc/resolv.conf"; }

  # Ctrl+C. The terminal sends SIGINT to the foreground process group. A command
  # started straight under proot shares proot's group, and proot answers SIGINT by
  # killing everything it runs at once, so a program that handles Ctrl+C itself (a
  # Python KeyboardInterrupt, a server's clean shutdown) never gets the chance, and
  # at an Ubuntu prompt the whole session would die. So a foreground command from
  # the terminal is started by a guest shell with job control, which gives the
  # command its OWN process group and the terminal: Ctrl+C then reaches only that
  # command, as on a PC, and proot is not signalled. Background and piped calls, and
  # calls with no terminal, run as before. VSCODROID_UB_NO_JOB=1 turns this off.
  local -a run=("$@")
  if [ -n "${VSCODROID_UB_FG-}" ] && [ -z "${VSCODROID_UB_NO_JOB-}" ] && [ -t 0 ] && [ "${BASHPID:-$$}" = "$$" ]; then
    run=(/bin/bash -c 'set -m; "$@"; exit $?' vscodroid-run "$@")
  fi

  ${pre[@]+"${pre[@]}"} "$VSCODROID_PROOT" --link2symlink -0 -r "$root" "${bind[@]}" \
    --kernel-release=6.2.1-vscodroid -w "$cwd" --kill-on-exit \
    /usr/bin/env -i "${envv[@]}" "${run[@]}"
}

# A command typed in the terminal: runs in the foreground with its own process group.
__vscodroid_ub_fg() { VSCODROID_UB_FG=1 __vscodroid_ub_exec "$@"; }

# ---- one package install at a time ------------------------------------------------
# Several things install packages: the first use of a tool, the Git setup that runs
# in the background, the graphical desktop, and the user's own apt. dpkg allows one at a time,
# so ours take a lock folder and wait their turn; a lock whose owner is gone is cleared.
__vscodroid_ub_lock() {
  local d="$HOME/.vscodroid/ubuntu.lock.d" waited=0 pid
  mkdir -p "$HOME/.vscodroid" 2>/dev/null
  while ! mkdir "$d" 2>/dev/null; do
    pid=$(cat "$d/pid" 2>/dev/null)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$d"; continue; fi
    [ $waited -ge "${VSCODROID_UB_LOCK_WAIT:-900}" ] && return 1
    sleep 1; waited=$((waited + 1))
  done
  echo "${BASHPID:-$$}" > "$d/pid"
}
__vscodroid_ub_unlock() { rm -rf "$HOME/.vscodroid/ubuntu.lock.d"; }
# An install that was killed half-way leaves dpkg with packages that are unpacked but
# not configured. Ubuntu's own remedy, `dpkg --configure -a`, finishes them and removes
# nothing. A damaged state that remains afterwards is left for apt to report in its
# own words.
__vscodroid_ub_heal() {
  [ -n "$(__vscodroid_ub_exec dpkg --audit 2>/dev/null)" ] || return 0
  echo "vscodroid: finishing a package installation that was interrupted..." >&2
  __vscodroid_ub_log "dpkg --audit not clean; running dpkg --configure -a"
  __vscodroid_ub_exec dpkg --configure -a >&2
  __vscodroid_ub_exec apt-get -f install -y -qq >/dev/null 2>&1
  return 0
}

__vscodroid_ub_apt() {
  local st
  __vscodroid_ub_lock || { echo "vscodroid: another package install is still running" >&2; return 1; }
  __vscodroid_ub_exec apt-get "$@"; st=$?
  if [ $st -ne 0 ] && [ -n "$(__vscodroid_ub_exec dpkg --audit 2>/dev/null)" ]; then
    __vscodroid_ub_heal
    __vscodroid_ub_exec apt-get "$@"; st=$?
  fi
  __vscodroid_ub_unlock
  return $st
}

# ---- first use: the Ubuntu system installs itself ------------------------------------
# A half-unpacked folder from an interrupted install carries the installer's
# "installing" marker. It is removed only when it is positively the app's own folder
# (same tests as a reinstall); anything else is left alone and the install stops.
__vscodroid_ub_clear_partial() {
  local root; root=$(__vscodroid_ub_root)
  [ -e "$root/.vscodroid-installing" ] && [ ! -L "$root/.vscodroid-installing" ] || return 0
  __vscodroid_ub_is_ours "$root" ubuntu >/dev/null 2>&1 || return 0
  find "$root" -type d -exec chmod u+rwx {} + 2>/dev/null
  rm -rf "$root"
}

# Free space, in KB, where the Ubuntu system is kept.
__vscodroid_ub_free_kb() { df -Pk "$HOME" 2>/dev/null | awk 'NR==2{print $4}'; }

__vscodroid_ub_autosetup() {
  local need free st
  if [ -z "${VSCODROID_PROOT-}" ] || [ ! -x "${VSCODROID_PROOT-}" ]; then
    echo "vscodroid: this build has no proot, so Linux tools are not available here" >&2
    return 1
  fi
  need=${VSCODROID_UB_MIN_KB:-1500000}
  free=$(__vscodroid_ub_free_kb)
  case "$free" in
    ''|*[!0-9]*) ;;
    *) if [ "$free" -lt "$need" ]; then
         echo "vscodroid: not enough free storage to install the Linux system (about $((need / 1024)) MB needed, $((free / 1024)) MB free)" >&2
         return 1
       fi ;;
  esac
  __vscodroid_ub_lock || { echo "vscodroid: the Linux system is still being installed from another terminal" >&2; return 1; }
  # Another terminal may have finished it while this one waited for the lock.
  if __vscodroid_ub_ready; then __vscodroid_ub_unlock; return 0; fi
  __vscodroid_ub_clear_partial
  echo "vscodroid: first use of a Linux tool: installing the Ubuntu system into the app's private storage (a few minutes, once)." >&2
  __vscodroid_ub_log "installing Ubuntu"
  bash "$HOME/.vscodroid/proot-test.sh" ubuntu; st=$?
  __vscodroid_ub_unlock
  # The script also compiles a test program; if only that step failed, the system is
  # unpacked and usable, and the command about to run reports the real problem itself.
  [ $st -eq 0 ] || __vscodroid_ub_log "install script ended with status $st"
  if ! __vscodroid_ub_ready; then
    __vscodroid_ub_log "install failed (status $st)"
    __vscodroid_ub_selfcheck >/dev/null 2>&1
    echo "vscodroid: the Linux system could not be installed (is the phone online? is there enough storage?). Nothing else was changed; it is tried again the next time a Linux tool is used." >&2
    return 1
  fi
  __vscodroid_ub_log "install finished"
  return 0
}

# command -> "group packages...": installed the first time the command is used.
__vscodroid_ub_group() {
  case "$1" in
    gcc|g++|cc|c++|cpp|make|cmake) echo "build build-essential cmake" ;;
    python|python3|pip|pip3) echo "python python3 python3-pip python3-venv python3-dev python-is-python3" ;;
    cargo|rustc) echo "rust cargo rustc gcc libc6-dev" ;;
    go|gofmt) echo "go golang-go" ;;
  esac
}

__vscodroid_ub_provision() {
  local cmd=$1 line group pkgs marker
  line=$(__vscodroid_ub_group "$cmd")
  [ -n "$line" ] || return 0
  set -- $line; group=$1; shift; pkgs="$*"
  marker="$(__vscodroid_ub_root)/var/lib/vscodroid/provisioned/$group"
  [ -f "$marker" ] && return 0
  echo "vscodroid: first use of '$cmd': installing $pkgs into the Ubuntu system. This takes a few minutes, once." >&2
  if __vscodroid_ub_apt update -qq && __vscodroid_ub_apt install -y -qq --no-install-recommends $pkgs; then
    mkdir -p "${marker%/*}" && : > "$marker"
    return 0
  fi
  echo "vscodroid: could not install $pkgs (is the phone online?)" >&2
  return 1
}

# python -m venv <dir>: the environment cannot live in shared storage, so it is
# created inside Ubuntu and <dir>/bin/activate points to it.
__vscodroid_ub_venv() {
  local a target="" abs name id guest
  local -a opts=()
  for a in "${@:3}"; do case "$a" in -*) opts+=("$a") ;; *) target=$a ;; esac; done
  [ -n "$target" ] || return 2
  case "$target" in /*) abs=$target ;; *) abs="$(pwd -P 2>/dev/null || pwd)/$target" ;; esac
  name=${abs##*/}; name=${name#.}; [ -n "$name" ] || name=env
  id=$(printf '%s' "$abs" | cksum | cut -d' ' -f1)
  guest="/root/.venvs/$name-$id"
  __vscodroid_ub_exec python3 -m venv ${opts[@]+"${opts[@]}"} "$guest" || return $?
  mkdir -p "$abs/bin" 2>/dev/null || return 0
  printf '%s\n' \
    "# VSCodroid: this environment lives inside the Ubuntu system, because shared storage cannot hold one." \
    "export VSCODROID_VENV='$guest'" \
    '__vscodroid_ps1_old=${PS1-}' \
    "PS1='($name) '\"\${PS1-}\"" \
    'deactivate() { unset VSCODROID_VENV; PS1=$__vscodroid_ps1_old; unset __vscodroid_ps1_old; unset -f deactivate; }' \
    > "$abs/bin/activate"
  echo "vscodroid: environment created. Activate it with:  source $target/bin/activate" >&2
  return 0
}

declare -A __vscodroid_ub_nat 2>/dev/null

__vscodroid_ub_cmd() {
  local n=$1; shift
  if [ -n "${VSCODROID_NO_UBUNTU-}" ]; then "__vscodroid_ub_orig_$n" "$@"; return $?; fi
  if ! __vscodroid_ub_ready; then
    if [ "${__vscodroid_ub_nat[$n]-0}" = 1 ]; then "__vscodroid_ub_orig_$n" "$@"; return $?; fi
    __vscodroid_ub_autosetup || return 1
  fi
  __vscodroid_ub_git_bg
  if ! __vscodroid_ub_provision "$n"; then
    if [ "${__vscodroid_ub_nat[$n]-0}" = 1 ]; then "__vscodroid_ub_orig_$n" "$@"; return $?; fi
    return 1
  fi
  local st
  case "$n" in
    python|python3)
      if [ "${1-}" = "-m" ] && [ "${2-}" = "venv" ]; then
        __vscodroid_ub_venv "$@"; st=$?
        [ $st -ne 2 ] && return $st
      fi
      # A program that draws a window (Tkinter, Pygame ...) gets the virtual screen.
      __vscodroid_ub_wants_gui "$@" && __vscodroid_ub_gui_ensure ;;
  esac
  case "$n" in
    apt|apt-get|dpkg)
      __vscodroid_ub_lock || { echo "vscodroid: another package install is still running" >&2; return 1; }
      __vscodroid_ub_heal
      __vscodroid_ub_fg "$n" "$@"; st=$?
      __vscodroid_ub_unlock
      return $st ;;
  esac
  __vscodroid_ub_fg "$n" "$@"; st=$?
  case "$n" in
    gcc|g++|cc|c++|rustc|make|cmake)
      if [ $st -eq 0 ]; then
        # The program just built can be started the way a PC does: by the path it was
        # given (-o), by its absolute path (what Code Runner uses), or as ./name.
        local a prev="" out=""
        for a in "$@"; do [ "$prev" = -o ] && out=$a; prev=$a; done
        [ -n "$out" ] && __vscodroid_ub_define_prog "$out"
        __vscodroid_ub_scan
      fi ;;
  esac
  return $st
}

__vscodroid_ub_on_shared() {
  local pre
  for pre in ${VSCODROID_SHARED_PREFIXES:-/storage /sdcard /mnt}; do
    case "$1" in "$pre"/*) return 0 ;; esac
  done
  return 1
}

__vscodroid_ub_is_elf() {
  [ -f "$1" ] && [ "$(LC_ALL=C head -c4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = 7f454c46 ]
}

# Which processor an ELF file is for: x86_64, aarch64 or other (e_machine, bytes 18-19).
__vscodroid_ub_elf_arch() {
  local m
  m=$(LC_ALL=C dd if="$1" bs=1 skip=18 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
  case "$m" in 3e00) echo x86_64 ;; b700) echo aarch64 ;; *) echo other ;; esac
}

# Run a file stored in shared storage through a private copy inside Ubuntu.
# Anything else is left to the system, which says what it always says.
__vscodroid_ub_run_file() {
  local p=$1 abs id name dst
  shift
  case "$p" in
    */*) abs="$(cd "${p%/*}" 2>/dev/null && pwd -P)/${p##*/}" ;;
    *) abs="$(pwd -P 2>/dev/null || pwd)/$p" ;;
  esac
  if [ ! -f "$abs" ] || ! __vscodroid_ub_ready || ! __vscodroid_ub_on_shared "$abs"; then
    command "$p" "$@"; return $?
  fi
  if __vscodroid_ub_is_elf "$abs" && [ "$(__vscodroid_ub_elf_arch "$abs")" = x86_64 ]; then
    __vscodroid_ub_x86_run "$abs" "$@"; return $?
  fi
  name=${abs##*/}
  id=$(printf '%s' "$abs" | cksum | cut -d' ' -f1)
  dst="$(__vscodroid_ub_root)/tmp/vsc-run/$id/$name"
  if [ ! -f "$dst" ] || [ "$abs" -nt "$dst" ]; then
    mkdir -p "${dst%/*}" && cp -f "$abs" "$dst" && chmod 755 "$dst" || return 1
  fi
  __vscodroid_ub_fg "/tmp/vsc-run/$id/$name" "$@"
}

# One built program, under every name it can be started by: as typed, absolute, ./name.
__vscodroid_ub_define_prog() {
  local p=$1 abs n here
  case "$p" in
    */*) abs="$(cd "${p%/*}" 2>/dev/null && pwd -P)/${p##*/}" ;;
    *) abs="$(pwd -P 2>/dev/null || pwd)/$p" ;;
  esac
  [ -f "$abs" ] && __vscodroid_ub_is_elf "$abs" || return 0
  here=$(pwd -P 2>/dev/null)
  for n in "$p" "$abs" "./${abs##*/}"; do
    [ "$n" = "./${abs##*/}" ] && [ "${abs%/*}" != "$here" ] && continue
    case "$n" in ""|*[!A-Za-z0-9_./+-]*) continue ;; esac
    # Never a bare name: `-o ls` must not turn `ls` into this program.
    case "$n" in */*) ;; *) continue ;; esac
    eval "function $n { __vscodroid_ub_run_file '$abs' \"\$@\"; }"
  done
}

# Define ./name for each program found here and in the usual build folders.
__vscodroid_ub_scan() {
  __vscodroid_ub_ready || return 0
  local f base
  for f in ./* ./build/* ./bin/* ./out/*; do
    [ -f "$f" ] || continue
    base=${f##*/}
    case "$base" in
      a.out) ;;
      *.*|*[!A-Za-z0-9_+-]*) continue ;;
    esac
    __vscodroid_ub_is_elf "$f" || continue
    __vscodroid_ub_define_prog "$f"
  done
  return 0
}

__vscodroid_ub_scan_key=
__vscodroid_ub_prompt() {
  local k
  k="$(pwd -P 2>/dev/null):$(stat -c %Y . 2>/dev/null)"
  [ "$k" = "$__vscodroid_ub_scan_key" ] && return 0
  __vscodroid_ub_scan_key=$k
  __vscodroid_ub_scan
}
case $- in
  *i*)
    if declare -p PROMPT_COMMAND 2>/dev/null | grep -q '^declare -a'; then
      PROMPT_COMMAND+=(__vscodroid_ub_prompt)
    else
      PROMPT_COMMAND="__vscodroid_ub_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
    fi ;;
esac

# ---- graphical programs (Tkinter, Pygame ...) --------------------------------
# A virtual screen (Xtigervnc) and a small window manager run inside Ubuntu, and
# noVNC shows that screen in a browser page on this phone (localhost:6080).
# EXPERIMENTAL: needs a few hundred MB the first time.
#
# Nothing is typed to start it. Running a Python program that imports tkinter,
# pygame, turtle, pyglet or kivy starts the desktop (after one question, the first
# time, because of the download) and opens it in the browser; the program then draws
# on it. The desktop keeps running until the app is closed or Ubuntu is reinstalled.
__vscodroid_ub_wants_gui() {
  local a f=""
  for a in "$@"; do
    case "$a" in -*) continue ;; *.py) f=$a; break ;; *) break ;; esac
  done
  [ -n "$f" ] && [ -f "$f" ] || return 1
  head -c 65536 "$f" 2>/dev/null |
    grep -Eq '^[[:space:]]*(import|from)[[:space:]]+(tkinter|Tkinter|pygame|turtle|pyglet|kivy)([[:space:].]|$)'
}

__vscodroid_ub_gui_ensure() {
  local root marker pid ans tty
  root=$(__vscodroid_ub_root)
  pid=$(cat "$HOME/.vscodroid/gui.pid" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then return 0; fi
  marker="$root/var/lib/vscodroid/provisioned/gui"
  if [ ! -f "$marker" ]; then
    tty=${VSCODROID_UB_TTY:-/dev/tty}
    if [ ! -r "$tty" ] || { [ -z "${VSCODROID_UB_TTY-}" ] && [ ! -t 0 ]; }; then
      echo "vscodroid: this program opens a window, which needs the graphical desktop (a one-time download of a few hundred MB). Run the program once from a terminal to install it." >&2
      return 0
    fi
    printf '%s ' "This program opens a window. Download the graphical desktop now (a few hundred MB, once)? [Y/n]" >&2
    read -r ans < "$tty"
    case "$ans" in ""|y|Y|yes|YES|Yes) ;; *) echo "vscodroid: skipped; the program will run without a screen." >&2; return 0 ;; esac
  fi
  __vscodroid_ub_gui start
  return 0
}

__vscodroid_ub_gui() {
  local act=${1-status} root pidf pid url marker
  root=$(__vscodroid_ub_root)
  pidf="$HOME/.vscodroid/gui.pid"
  url="http://localhost:6080/vnc.html?autoconnect=1&resize=scale"
  pid=$(cat "$pidf" 2>/dev/null)
  case "$act" in
    start)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "vscodroid: the desktop is already running"; __vscodroid_open_url "$url"; return 0
      fi
      marker="$root/var/lib/vscodroid/provisioned/gui"
      if [ ! -f "$marker" ]; then
        echo "vscodroid: installing the graphical desktop into the Ubuntu system. This takes several minutes, once." >&2
        if ! { __vscodroid_ub_apt update -qq &&
               __vscodroid_ub_apt install -y -qq --no-install-recommends \
                 tigervnc-standalone-server novnc websockify openbox xterm x11-utils python3-tk; }; then
          echo "vscodroid: could not install the desktop (is the phone online?)" >&2; return 1
        fi
        mkdir -p "${marker%/*}" && : > "$marker"
      fi
      # One long-lived proot holds the screen and the web page; they end with it.
      (
        __vscodroid_ub_exec /bin/sh -c 'rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
          Xtigervnc :1 -geometry 1280x720 -depth 24 -SecurityTypes None -localhost -rfbport 5901 >/tmp/vnc.log 2>&1 &
          sleep 2
          DISPLAY=:1 openbox >/tmp/openbox.log 2>&1 &
          exec websockify --web /usr/share/novnc 6080 localhost:5901' >/dev/null 2>&1 &
        echo $! > "$pidf"
      )
      sleep 4
      if __vscodroid_open_url "$url"; then echo "vscodroid: the desktop is open in the browser" >&2; else echo "vscodroid: the desktop is at $url" >&2; fi
      return 0 ;;
    open) __vscodroid_open_url "$url" || echo "$url"; return 0 ;;
    stop)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null; rm -f "$pidf"; else rm -f "$pidf"; fi
      return 0 ;;
    status)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo "running ($url)"; else echo "not running"; fi
      return 0 ;;
    *) return 2 ;;
  esac
}

# ---- Intel (x86_64) programs ----------------------------------------------------
# qemu-user, installed inside the arm64 Ubuntu, runs an Intel Linux program and
# answers its system calls itself; the Intel libraries come from an amd64 Ubuntu
# unpacked beside the main one and shown at /opt/amd64. Slow by nature (an
# emulated processor) and EXPERIMENTAL. For prebuilt Intel binaries only; it does
# not turn the whole system into an Intel one, and a program that is not found by
# ./name (see __vscodroid_ub_scan) is not routed.
#
# Nothing is typed to set it up: starting an Intel program prepares qemu and the
# amd64 files the first time, with a notice.
__vscodroid_ub_x86_ensure() {
  local root x86root marker
  root=$(__vscodroid_ub_root)
  x86root="${root%/*}/ubuntu-amd64"
  marker="$root/var/lib/vscodroid/provisioned/qemu"
  if [ -f "$marker" ] && { [ -e "$x86root/lib64/ld-linux-x86-64.so.2" ] || [ -e "$x86root/usr/lib64/ld-linux-x86-64.so.2" ]; }; then
    return 0
  fi
  echo "vscodroid: this is an Intel (x86_64) program; preparing the emulator for it (a few minutes, once)." >&2
  if [ ! -f "$marker" ]; then
    __vscodroid_ub_apt update -qq &&
      __vscodroid_ub_apt install -y -qq --no-install-recommends qemu-user-static || {
      echo "vscodroid: could not install qemu (is the phone online?)" >&2; return 1; }
    mkdir -p "${marker%/*}" && : > "$marker"
  fi
  if [ ! -e "$x86root/lib64/ld-linux-x86-64.so.2" ] && [ ! -e "$x86root/usr/lib64/ld-linux-x86-64.so.2" ]; then
    bash "$HOME/.vscodroid/proot-test.sh" ubuntu-amd64 >&2 || return 1
  fi
  return 0
}

# __vscodroid_ub_x86_run <absolute path of an Intel program> [args...]
__vscodroid_ub_x86_run() {
  local abs=$1 root x86root id dst
  shift
  __vscodroid_ub_x86_ensure || return 1
  root=$(__vscodroid_ub_root)
  x86root="${root%/*}/ubuntu-amd64"
  id=$(printf '%s' "$abs" | cksum | cut -d' ' -f1)
  dst="$root/tmp/vsc-run/$id/${abs##*/}"
  mkdir -p "${dst%/*}" && cp -f "$abs" "$dst" && chmod 755 "$dst" || return 1
  VSCODROID_UB_EXTRA_BIND="$x86root:/opt/amd64" \
    __vscodroid_ub_fg qemu-x86_64-static -L /opt/amd64 "/tmp/vsc-run/$id/${abs##*/}" "$@"
}

# ---- reinstall Ubuntu ---------------------------------------------------------------
# Reached only from the Command Palette ("VSCodroid: Reinstall Linux Environment"),
# which opens a terminal that calls __vscodroid_ub_reset directly. It wipes the
# Ubuntu system (every package installed in it) and installs it again. It removes
# only the Ubuntu folders inside the app's private storage. Projects in shared storage
# are never touched, and neither are the Git settings and sign-in (they live outside
# the Ubuntu system, see below). Ordinary damage (an interrupted install, a half-
# configured package) is repaired on its own and never needs this.
#   --yes   skip the question (for scripts)
__vscodroid_ub_setup() { bash "$HOME/.vscodroid/proot-test.sh" ubuntu; }

__vscodroid_ub_healthy() {
  __vscodroid_ub_ready || return 1
  __vscodroid_ub_exec /bin/true >/dev/null 2>&1 || return 1
  local audit
  audit=$(__vscodroid_ub_exec dpkg --audit 2>&1) || return 1
  [ -z "$audit" ]
}

# The canonical form of a folder (links resolved), or nothing.
__vscodroid_ub_canon() { ( cd "$1" 2>/dev/null && pwd -P ); }

# Is <path> THE <leaf> system this app installed? Every test must pass, or nothing is
# removed. On failure the reason is printed and the status is 1. A name that merely ends
# in proot/ubuntu proves nothing: the folder must be exactly <app home>/proot/<leaf>
# once links are resolved, must not itself be a link, must not be in shared storage, and
# must carry the installer's marker (or, for an install made before markers existed,
# look like a real Ubuntu).
__vscodroid_ub_is_ours() {
  local p=$1 leaf=$2 home canon_p
  if [ -z "${HOME-}" ] || [ ! -d "$HOME" ]; then echo "HOME is not set to a folder"; return 1; fi
  home=$(__vscodroid_ub_canon "$HOME")
  case "$home" in ""|/storage/*|/sdcard/*|/mnt/*) echo "the app's home folder is not in private storage"; return 1 ;; esac
  case "$p" in *..*|*//*|*/./*|*/.) echo "the path has '..', '.' or '//' in it"; return 1 ;; esac
  [ -L "$p" ] && { echo "it is a symbolic link"; return 1; }
  [ -L "$HOME/proot" ] && { echo "$HOME/proot is a symbolic link"; return 1; }
  [ -d "$p" ] || { echo "it is not a folder"; return 1; }
  canon_p=$(__vscodroid_ub_canon "$p")
  [ "$canon_p" = "$home/proot/$leaf" ] || { echo "it resolves to $canon_p, not to $home/proot/$leaf"; return 1; }
  if { [ -f "$p/.vscodroid-ubuntu" ] && [ ! -L "$p/.vscodroid-ubuntu" ]; } ||
     { [ -f "$p/.vscodroid-installing" ] && [ ! -L "$p/.vscodroid-installing" ]; }; then
    return 0
  fi
  if [ -f "$p/etc/os-release" ] && [ ! -L "$p/etc/os-release" ] && grep -q '^ID=ubuntu' "$p/etc/os-release" &&
     { [ -e "$p/bin/sh" ] || [ -L "$p/bin/sh" ]; }; then
    return 0
  fi
  echo "it has no installer marker and does not look like an Ubuntu system"
  return 1
}

# Older installs have no marker. Once one is confirmed genuine, give it one, so that a
# later damaged state can still be recognised and repaired.
__vscodroid_ub_mark_if_genuine() {
  local root; root=$(__vscodroid_ub_root)
  [ -f "$root/.vscodroid-ubuntu" ] && return 0
  __vscodroid_ub_is_ours "$root" ubuntu >/dev/null 2>&1 && : > "$root/.vscodroid-ubuntu" 2>/dev/null
  return 0
}

__vscodroid_ub_reset() {
  local mode=$1 a yes=0 root x86 ans tty why
  shift
  for a in "$@"; do case "$a" in -y|--yes) yes=1 ;; esac; done
  root=$(__vscodroid_ub_root)
  x86="$HOME/proot/ubuntu-amd64"
  # A link in place of the proot folder would send an install or a removal somewhere else.
  if [ -L "$HOME/proot" ]; then
    echo "vscodroid: nothing was changed. $HOME/proot is a symbolic link; Ubuntu is only installed or removed inside the app's own folder." >&2
    return 1
  fi
  # Only the Ubuntu folders this app installed in its private storage may ever be removed,
  # and only when each is positively recognised. Anything doubtful stops here, before any
  # question is asked or anything is deleted.
  if [ -e "$root" ] || [ -L "$root" ]; then
    why=$(__vscodroid_ub_is_ours "$root" ubuntu) || {
      echo "vscodroid: nothing was removed. '$root' is not recognised as the Ubuntu system this app installed: $why." >&2
      return 1
    }
  fi
  if [ -e "$x86" ] || [ -L "$x86" ]; then
    why=$(__vscodroid_ub_is_ours "$x86" ubuntu-amd64) || {
      echo "vscodroid: nothing was removed. '$x86' is not recognised as the Intel Ubuntu folder this app installed: $why." >&2
      return 1
    }
  fi

  if [ "$mode" = repair ] && __vscodroid_ub_healthy; then
    echo "vscodroid: Ubuntu looks healthy. To reinstall it anyway, use the Command Palette entry \"VSCodroid: Reinstall Linux Environment\"."
    return 0
  fi
  if [ ! -e "$root" ] && [ ! -L "$root" ]; then
    echo "vscodroid: Ubuntu is not installed; installing it."
    __vscodroid_ub_setup && __vscodroid_ub_git_bg
    return $?
  fi

  if [ $yes -eq 0 ]; then
    tty=${VSCODROID_UB_TTY:-/dev/tty}
    if [ ! -r "$tty" ] || { [ -z "${VSCODROID_UB_TTY-}" ] && [ ! -t 0 ]; }; then
      echo "vscodroid: this asks a question, so it needs a terminal. In a script, add --yes." >&2
      return 1
    fi
    printf '%s ' "Warning: This will wipe all packages installed inside Ubuntu. Your files in /VSCodroid will NOT be deleted. Proceed? [Y/n]"
    read -r ans < "$tty"
    case "$ans" in ""|y|Y|yes|YES|Yes) ;; *) echo "vscodroid: cancelled. Nothing was changed."; return 1 ;; esac
  fi

  # Nothing may be running in Ubuntu or installing into it while it is removed.
  if [ -f "$HOME/.vscodroid/gui.pid" ]; then __vscodroid_ub_gui stop >/dev/null 2>&1; fi
  __vscodroid_ub_lock || { echo "vscodroid: a package install is still running; try again in a minute" >&2; return 1; }
  echo "vscodroid: removing the Ubuntu system..."
  # Make read-only folders removable; rm does not follow links, so a link inside
  # Ubuntu that points at a project is removed, not the project.
  # find does not follow links and touches only folders; rm does not follow them either.
  find "$root" -type d -exec chmod u+rwx {} + 2>/dev/null
  rm -rf "$root"
  if [ -d "$x86" ]; then find "$x86" -type d -exec chmod u+rwx {} + 2>/dev/null; rm -rf "$x86"; fi
  __vscodroid_ub_unlock
  if [ -e "$root" ]; then echo "vscodroid: could not remove all of $root" >&2; return 1; fi

  echo "vscodroid: installing Ubuntu again (a few minutes)..."
  if __vscodroid_ub_setup; then
    echo "vscodroid: Ubuntu is ready again. Your project files were not touched. Python virtual environments made before need to be created again."
    __vscodroid_ub_git_bg
    return 0
  fi
  echo "vscodroid: the reinstall did not finish. Use \"VSCodroid: Reinstall Linux Environment\" again when the phone is online." >&2
  return 1
}

# ---- Git in Ubuntu --------------------------------------------------------------
# Git inside Ubuntu (what cargo, go, pip and the Ubuntu shell use) is installed in
# the background the first time Ubuntu is ready. Its settings and its stored sign-in
# live in ~/.vscodroid/ubuntu-git in private storage, shown inside Ubuntu as
# /root/.vscodroid-git: never in a project, never in a backup, and kept when Ubuntu is
# reinstalled. The sign-in uses git's own `store` helper pointed at that private
# file: it is a plain file protected by the app's sandbox (mode 600), NOT encrypted;
# see docs/ANDROID_LIMITATION_LOG.md for why nothing stronger fits here.
#
# The phone's own git (Source Control, the terminal's `git`) signs in through VS Code
# and is unaffected by any of this.
#
# Ubuntu's git signs in the standard way: `git clone`/`git push` ask for a username and
# a token, and the `store` helper above keeps them in the private file. They are removed
# with the standard `git credential reject`. The three functions below
# (__vscodroid_ub_git_login/logout/check) are no longer reachable from the terminal;
# they stay for the automated tests.
__vscodroid_ub_git_configure() {
  local d cfg name email
  d=$(__vscodroid_ub_git_dir); cfg="$d/gitconfig"
  ( umask 077; mkdir -p "$d" ) && chmod 700 "$d" 2>/dev/null
  __vscodroid_orig_git config --file "$cfg" credential.helper 'store --file /root/.vscodroid-git/credentials' || return 1
  __vscodroid_orig_git config --file "$cfg" init.defaultBranch main
  # Files in shared storage appear to belong to another user; without this git
  # refuses them as "dubious ownership".
  __vscodroid_orig_git config --file "$cfg" safe.directory '*'
  name=$(__vscodroid_orig_git config --global user.name 2>/dev/null)
  email=$(__vscodroid_orig_git config --global user.email 2>/dev/null)
  [ -z "$name" ]  || __vscodroid_orig_git config --file "$cfg" user.name "$name"
  [ -z "$email" ] || __vscodroid_orig_git config --file "$cfg" user.email "$email"
  chmod 600 "$cfg" 2>/dev/null
  # Keep the sign-in file private whatever a restore or a copy did to its mode.
  [ -f "$d/credentials" ] && chmod 600 "$d/credentials" 2>/dev/null
  return 0
}

# The git inside Ubuntu goes through the same guard: /usr/local/bin/git is written from
# git-token-guard.sh and runs the real /usr/bin/git. Rewritten only when it differs.
# A line carrying a token is also dropped from the Ubuntu shell's history.
__vscodroid_ub_git_guard_install() {
  local root lib dst tmp rc
  root=$(__vscodroid_ub_root); lib="$HOME/.vscodroid/git-token-guard.sh"; dst="$root/usr/local/bin/git"
  [ -f "$lib" ] && [ -d "$root/usr/local/bin" ] || return 0
  tmp="$dst.new.$$"
  {
    printf '%s\n' '#!/bin/bash' '# Written by VSCodroid: refuses remote addresses that carry a token, then runs git.'
    cat "$lib"
    printf '%s\n' '__vscodroid_tg_guest() {' \
      '  local real=${VSCODROID_REAL_GIT:-/usr/bin/git}' \
      '  if [ ! -x "$real" ]; then echo "git: not installed in Ubuntu yet (see ~/.vscodroid/git-setup.log, or run: apt install git)" >&2; return 127; fi' \
      '  __vscodroid_tg_run "$real" "$@"' '}' '__vscodroid_tg_guest "$@"' 'exit $?'
  } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  if [ -f "$dst" ] && cmp -s "$tmp" "$dst"; then rm -f "$tmp"; else chmod 755 "$tmp" && mv -f "$tmp" "$dst"; fi
  rc="$root/root/.bashrc"
  if ! grep -q '# vscodroid-token-scrub' "$rc" 2>/dev/null; then
    cat >> "$rc" <<'RC_EOF'

# vscodroid-token-scrub: forget a typed line that carries a password or token in a URL
__vscodroid_scrub() {
  local l; l=$(HISTTIMEFORMAT= history 1 2>/dev/null) || return 0
  if printf '%s' "$l" | grep -Eq '://[^/@[:space:]]+:[^/@[:space:]]+@|://(gh[pousr]_|github_pat_)[A-Za-z0-9_]+@'; then history -d $((HISTCMD - 1)) 2>/dev/null; fi
}
PROMPT_COMMAND="__vscodroid_scrub${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
RC_EOF
  fi
  return 0
}

__vscodroid_ub_git_bootstrap() {
  local root marker log
  root=$(__vscodroid_ub_root)
  marker="$root/var/lib/vscodroid/provisioned/git"
  log="$HOME/.vscodroid/git-setup.log"
  __vscodroid_ub_git_configure
  [ -f "$marker" ] && return 0
  {
    echo "$(date '+%F %T') installing git into Ubuntu"
    if __vscodroid_ub_apt update -qq &&
       __vscodroid_ub_apt install -y -qq --no-install-recommends git ca-certificates openssh-client &&
       __vscodroid_ub_exec git --version; then
      mkdir -p "${marker%/*}" && : > "$marker"
      echo "done"
    else
      echo "failed (will be tried again next time)"
    fi
  } >> "$log" 2>&1
}

# Start it once per shell, without waiting, when Ubuntu is ready and git is not there yet.
__vscodroid_ub_git_bg() {
  [ -n "${__vscodroid_ub_git_started-}" ] && return 0
  __vscodroid_ub_ready || return 0
  __vscodroid_ub_mark_if_genuine
  __vscodroid_ub_git_guard_install
  [ -f "$(__vscodroid_ub_root)/var/lib/vscodroid/provisioned/git" ] && return 0
  __vscodroid_ub_git_started=1
  # Started inside a second subshell so an interactive shell prints no "[1] 1234" job line.
  ( ( trap '' HUP; __vscodroid_ub_git_bootstrap ) >/dev/null 2>&1 & )
  echo "vscodroid: Git is being set up inside Ubuntu in the background (log: ~/.vscodroid/git-setup.log)" >&2
  return 0
}

# git login [host]: the token is typed hidden and handed to git on its
# standard input, so it never appears in a command line, shell history or a project.
__vscodroid_ub_git_login() {
  local host=${1:-github.com} d user token
  d=$(__vscodroid_ub_git_dir)
  __vscodroid_ub_git_configure || return 1
  printf 'Username for %s: ' "$host" >&2; read -r user
  printf 'Token (typing is hidden): ' >&2; read -rs token; echo >&2
  if [ -z "$user" ] || [ -z "$token" ]; then echo "vscodroid: cancelled; nothing was saved" >&2; return 1; fi
  ( umask 077
    printf 'protocol=https\nhost=%s\nusername=%s\npassword=%s\n\n' "$host" "$user" "$token" |
      GIT_CONFIG_GLOBAL=/dev/null __vscodroid_orig_git -c "credential.helper=store --file $d/credentials" credential approve ) || return 1
  chmod 600 "$d/credentials" 2>/dev/null
  token=
  echo "vscodroid: saved for $host in the app's private storage (not in any project)."
}

__vscodroid_ub_git_logout() {
  local host=${1:-github.com} d
  d=$(__vscodroid_ub_git_dir)
  [ -f "$d/credentials" ] || { echo "vscodroid: nothing saved"; return 0; }
  printf 'protocol=https\nhost=%s\n\n' "$host" |
    GIT_CONFIG_GLOBAL=/dev/null __vscodroid_orig_git -c "credential.helper=store --file $d/credentials" credential reject
  [ -s "$d/credentials" ] || rm -f "$d/credentials"
  echo "vscodroid: sign-in for $host removed"
}

__vscodroid_ub_git_check() {
  local d root repo
  d=$(__vscodroid_ub_git_dir); root=$(__vscodroid_ub_root)
  echo "phone git:   $(__vscodroid_orig_git --version 2>&1)"
  if [ -f "$root/var/lib/vscodroid/provisioned/git" ]; then
    echo "Ubuntu git:  $(__vscodroid_ub_exec git --version 2>&1)"
  else
    echo "Ubuntu git:  not installed yet (see ~/.vscodroid/git-setup.log)"
  fi
  echo "helper:      $(__vscodroid_orig_git config --file "$d/gitconfig" credential.helper 2>/dev/null || echo 'not configured')"
  if __vscodroid_shared_name "$d"; then echo "WARNING:     the sign-in folder is in shared storage ($d); it should be in private storage"; fi
  [ -d "$d" ] && [ "$(stat -c %a "$d" 2>/dev/null)" != 700 ] && chmod 700 "$d" 2>/dev/null && echo "fixed:       $d was readable by others; now 700"
  if [ -s "$d/credentials" ]; then
    [ "$(stat -c %a "$d/credentials" 2>/dev/null)" != 600 ] && chmod 600 "$d/credentials" 2>/dev/null && echo "fixed:       credentials file was readable by others; now 600"
    echo "sign-in:     saved (private storage, mode $(stat -c %a "$d/credentials" 2>/dev/null), plain file, not encrypted)"
  else echo "sign-in:     none saved"; fi
  repo=$(__vscodroid_orig_git rev-parse --git-dir 2>/dev/null)
  if [ -n "$repo" ] && grep -Eq '://[^/@[:space:]]+:[^/@[:space:]]+@|://(gh[pousr]_|github_pat_)[A-Za-z0-9_]+@' "$repo/config" 2>/dev/null; then
    echo "WARNING:     this repository's remote address contains a password or token. Change it with:  git remote set-url origin https://github.com/OWNER/REPO.git"
  fi
}

# Read-only health check. It is not a command: the install path runs it after a failed
# install, and the tests call it. The answers go to ~/.vscodroid/ubuntu.log; they are
# printed only with VSCODROID_SELFCHECK_VERBOSE=1. Status 1 means something is wrong.
__vscodroid_ub_chk() {
  __vscodroid_ub_log "check $1: $2"
  [ -z "${VSCODROID_SELFCHECK_VERBOSE-}" ] || echo "$1: $2"
  [ "$2" = ok ] || __vscodroid_ub_chk_bad=1
}

__vscodroid_ub_selfcheck() {
  local root op free
  root=$(__vscodroid_ub_root); __vscodroid_ub_chk_bad=0
  if [ -n "${VSCODROID_PROOT-}" ] && [ -x "${VSCODROID_PROOT-}" ]; then __vscodroid_ub_chk proot ok; else __vscodroid_ub_chk proot "missing"; fi
  if [ -n "${PROOT_LOADER-}" ] && [ -x "${PROOT_LOADER-}" ]; then __vscodroid_ub_chk loader ok; else __vscodroid_ub_chk loader "missing"; fi
  [ ! -e "$root/.vscodroid-installing" ] || __vscodroid_ub_chk installer "an install did not finish"
  if __vscodroid_ub_ready; then
    __vscodroid_ub_chk ubuntu ok
    if __vscodroid_ub_exec /bin/true >/dev/null 2>&1; then __vscodroid_ub_chk start ok; else __vscodroid_ub_chk start "proot could not start a command"; fi
    if [ -z "$(__vscodroid_ub_exec dpkg --audit 2>/dev/null)" ]; then __vscodroid_ub_chk packages ok; else __vscodroid_ub_chk packages "an installation was left unfinished"; fi
  else
    __vscodroid_ub_chk ubuntu "not installed"
  fi
  free=$(__vscodroid_ub_free_kb)
  case "$free" in ''|*[!0-9]*) ;; *) if [ "$free" -ge "${VSCODROID_UB_MIN_KB:-1500000}" ]; then __vscodroid_ub_chk storage ok; else __vscodroid_ub_chk storage "only $((free / 1024)) MB free"; fi ;; esac
  # What this folder supports is information, not a fault.
  if declare -F __vscodroid_op_works >/dev/null 2>&1; then
    for op in symlink hardlink chmod fifo; do
      if __vscodroid_op_works "$op" "$(pwd -P 2>/dev/null || pwd)"; then __vscodroid_ub_log "folder $op: supported"; else __vscodroid_ub_log "folder $op: not supported"; fi
    done
  fi
  return $__vscodroid_ub_chk_bad
}

# A shell, or one command, inside the Ubuntu system. `ubuntu` and `sudo` both end here.
__vscodroid_ub_run_cmd() {
  if ! __vscodroid_ub_ready; then __vscodroid_ub_autosetup || return 1; fi
  __vscodroid_ub_git_bg
  if [ $# -eq 0 ]; then __vscodroid_ub_exec /bin/bash -l; return $?; fi
  case "$1" in
    apt|apt-get|dpkg) __vscodroid_ub_cmd "$@"; return $? ;;
  esac
  case "$1" in
    */*) if [ -f "$1" ] && __vscodroid_ub_on_shared "$(cd "${1%/*}" 2>/dev/null && pwd -P)/${1##*/}"; then
           __vscodroid_ub_run_file "$@"; return $?
         fi ;;
  esac
  __vscodroid_ub_fg "$@"
}

# Kept as a way in for people who know it; nothing documented or automatic needs it.
ubuntu() { __vscodroid_ub_run_cmd "$@"; }
native() { VSCODROID_NO_UBUNTU=1 "$@"; }

# sudo as on a PC: the commands that need root run as (fake) root inside Ubuntu.
# `sudo -i`, `sudo -s` and `sudo su` open a shell there.
sudo() {
  while :; do
    case "${1-}" in
      -E|-S|-n|-H|-A|-b|-k|-v|--preserve-env) shift ;;
      -u|-g) shift; shift ;;
      -u?*|-g?*|--user=*|--group=*|--preserve-env=*) shift ;;
      -i|-s|--login|--shell) shift; [ $# -eq 0 ] && { __vscodroid_ub_run_cmd; return $?; }; break ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  if [ $# -eq 0 ]; then echo "usage: sudo COMMAND ..." >&2; return 1; fi
  if [ "$1" = su ] && { [ $# -eq 1 ] || [ "$2" = - ]; }; then __vscodroid_ub_run_cmd; return $?; fi
  __vscodroid_ub_run_cmd "$@"
}

for __n in gcc g++ cc c++ cpp make cmake python python3 pip pip3 cargo rustc go gofmt apt apt-get apt-cache dpkg; do
  if declare -F "$__n" >/dev/null 2>&1; then
    eval "$(declare -f "$__n" | sed "1s/^$__n *()/__vscodroid_ub_orig_$__n ()/")"
    __vscodroid_ub_nat[$__n]=1
  else
    eval "__vscodroid_ub_orig_$__n() { command $__n \"\$@\"; }"
    # A launcher the app put on PATH for programs that start this command by name
    # (usr/libexec/tcbin) leads back into this routing; it is not a native tool.
    __p=$(command -v "$__n" 2>/dev/null)
    case "$__p" in ''|*/usr/libexec/tcbin/*) __vscodroid_ub_nat[$__n]=0 ;; *) __vscodroid_ub_nat[$__n]=1 ;; esac
  fi
  eval "$__n() { __vscodroid_ub_cmd $__n \"\$@\"; }"
done
unset __n __p

# ---- keep tokens out of project files -------------------------------------------
# The phone's own `git` goes through the same guard as the git inside Ubuntu
# (git-token-guard.sh): it refuses a remote address that carries a password or token,
# hides one already stored when remotes or config are listed, and a line that carries one
# is dropped from the shell history. VSCODROID_NO_TOKEN_GUARD=1 turns the guard off.
[ -f "$HOME/.vscodroid/git-token-guard.sh" ] && . "$HOME/.vscodroid/git-token-guard.sh"
if declare -F git >/dev/null 2>&1; then
  eval "$(declare -f git | sed '1s/^git *()/__vscodroid_orig_git ()/')"
else
  __vscodroid_orig_git() { command git "$@"; }
fi
git() {
  if declare -F __vscodroid_tg_run >/dev/null 2>&1; then __vscodroid_tg_run __vscodroid_orig_git "$@"; else __vscodroid_orig_git "$@"; fi
}
case $- in
  *i*)
    if declare -F __vscodroid_tg_scrub_history >/dev/null 2>&1; then
      if declare -p PROMPT_COMMAND 2>/dev/null | grep -q '^declare -a'; then PROMPT_COMMAND+=(__vscodroid_tg_scrub_history)
      else PROMPT_COMMAND="__vscodroid_tg_scrub_history${PROMPT_COMMAND:+;$PROMPT_COMMAND}"; fi
    fi ;;
esac
