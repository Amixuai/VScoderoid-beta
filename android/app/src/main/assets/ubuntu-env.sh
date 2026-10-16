# VSCodroid: routes compilers and runtimes into the hidden Ubuntu system.
#
# Sourced by command-wrapper.sh, so it is active only on Android. Type the same
# commands as on a PC (gcc, g++, make, python, pip, cargo, go, apt ...) and they
# run inside the Ubuntu system the app keeps in its PRIVATE storage, started
# through proot. The current folder is passed through at the same path, so what
# a command writes lands in your visible workspace.
#
# Not routed: node and npm (they run natively), git and the editor itself.
#
# Opt out for one command:      VSCODROID_NO_UBUNTU=1 python3 script.py
#                               native python3 script.py
# Open an Ubuntu shell:         ubuntu
# Install Ubuntu (once):        ubuntu setup
# Repair / reinstall Ubuntu:    ubuntu repair | ubuntu reset   (your projects are never touched)
# Git sign-in for Ubuntu's git: ubuntu git-login | ubuntu git-logout | ubuntu git-check
#
# Android will not start a program that is stored in shared storage (the
# workspace). So that `./hello` works after `gcc hello.c -o hello` as on a PC,
# a function named ./hello is defined for each program built there; it runs a
# private copy inside Ubuntu. `ubuntu ./hello` does the same explicitly.

[ "${VSCODROID_PLATFORM-}" = "android" ] || return 0
declare -F __vscodroid_ub_loaded >/dev/null 2>&1 && return 0
__vscodroid_ub_loaded() { :; }

__vscodroid_ub_root() { printf '%s' "${VSCODROID_UBUNTU_ROOT:-$HOME/proot/ubuntu}"; }

__vscodroid_ub_git_dir() { printf '%s' "$HOME/.vscodroid/ubuntu-git"; }

__vscodroid_ub_ready() {
  local r; r=$(__vscodroid_ub_root)
  [ -n "${VSCODROID_PROOT-}" ] && [ -x "${VSCODROID_PROOT-}" ] && [ -x "${PROOT_LOADER-}" ] &&
    { [ -e "$r/bin/sh" ] || [ -L "$r/bin/sh" ]; }
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
  # While the graphical desktop runs (ubuntu gui start), programs draw on it.
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

  ${pre[@]+"${pre[@]}"} "$VSCODROID_PROOT" --link2symlink -0 -r "$root" "${bind[@]}" \
    --kernel-release=6.2.1-vscodroid -w "$cwd" --kill-on-exit \
    /usr/bin/env -i "${envv[@]}" "$@"
}

# ---- one package install at a time ------------------------------------------------
# Several things install packages: the first use of a tool, the Git setup that runs
# in the background, `ubuntu gui`, and the user's own apt. dpkg allows one at a time,
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
__vscodroid_ub_apt() {
  local st
  __vscodroid_ub_lock || { echo "vscodroid: another package install is still running" >&2; return 1; }
  __vscodroid_ub_exec apt-get "$@"; st=$?
  __vscodroid_ub_unlock
  return $st
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
    echo "vscodroid: '$n' runs inside the Ubuntu system, which is not installed yet. Run:  ubuntu setup" >&2
    return 127
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
      fi ;;
  esac
  case "$n" in
    apt|apt-get|dpkg)
      __vscodroid_ub_lock || { echo "vscodroid: another package install is still running" >&2; return 1; }
      __vscodroid_ub_exec "$n" "$@"; st=$?
      __vscodroid_ub_unlock
      return $st ;;
  esac
  __vscodroid_ub_exec "$n" "$@"; st=$?
  case "$n" in
    gcc|g++|cc|c++|make|cmake) [ $st -eq 0 ] && __vscodroid_ub_scan ;;
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
  name=${abs##*/}
  id=$(printf '%s' "$abs" | cksum | cut -d' ' -f1)
  dst="$(__vscodroid_ub_root)/tmp/vsc-run/$id/$name"
  if [ ! -f "$dst" ] || [ "$abs" -nt "$dst" ]; then
    mkdir -p "${dst%/*}" && cp -f "$abs" "$dst" && chmod 755 "$dst" || return 1
  fi
  __vscodroid_ub_exec "/tmp/vsc-run/$id/$name" "$@"
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
    eval "function $f { __vscodroid_ub_run_file '$f' \"\$@\"; }"
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
#   ubuntu gui start    start the desktop and open it in the browser
#   ubuntu gui open     open the page again
#   ubuntu gui stop     stop it
#   ubuntu gui status
#
# While it runs, routed commands such as `python3 game.py` draw on it.
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
        echo "vscodroid: first use of the graphical desktop: installing it into the Ubuntu system. This takes several minutes, once." >&2
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
      if __vscodroid_open_url "$url"; then echo "vscodroid: the desktop is open in the browser"; else echo "vscodroid: the desktop is at $url"; fi
      return 0 ;;
    open) __vscodroid_open_url "$url" || echo "$url"; return 0 ;;
    stop)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null; rm -f "$pidf"; echo "vscodroid: the desktop is stopped"; else rm -f "$pidf"; echo "vscodroid: the desktop is not running"; fi
      return 0 ;;
    status)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo "running ($url)"; else echo "not running"; fi
      return 0 ;;
    *) echo "usage: ubuntu gui start|open|stop|status" >&2; return 2 ;;
  esac
}

# ---- Intel (x86_64) programs ----------------------------------------------------
# qemu-user, installed inside the arm64 Ubuntu, runs an Intel Linux program and
# answers its system calls itself; the Intel libraries come from an amd64 Ubuntu
# unpacked beside the main one and shown at /opt/amd64. Slow by nature (an
# emulated processor) and EXPERIMENTAL. For prebuilt Intel binaries; it does not
# turn the whole system into an Intel one.
#
#   ubuntu x86 setup          install qemu and fetch the amd64 files (once)
#   ubuntu x86 run ./prog ... run an Intel program
__vscodroid_ub_x86() {
  local act=${1-help} root x86root marker prog abs id dst
  root=$(__vscodroid_ub_root)
  x86root="${root%/*}/ubuntu-amd64"
  marker="$root/var/lib/vscodroid/provisioned/qemu"
  case "$act" in
    setup)
      if [ ! -f "$marker" ]; then
        echo "vscodroid: installing qemu into the Ubuntu system (a few minutes, once)..." >&2
        __vscodroid_ub_apt update -qq &&
          __vscodroid_ub_apt install -y -qq --no-install-recommends qemu-user-static || {
          echo "vscodroid: could not install qemu (is the phone online?)" >&2; return 1; }
        mkdir -p "${marker%/*}" && : > "$marker"
      fi
      if [ ! -e "$x86root/lib64/ld-linux-x86-64.so.2" ] && [ ! -e "$x86root/usr/lib64/ld-linux-x86-64.so.2" ]; then
        bash "$HOME/.vscodroid/proot-test.sh" ubuntu-amd64 || return 1
      fi
      echo "vscodroid: Intel programs are ready: ubuntu x86 run ./program"
      return 0 ;;
    run)
      shift
      [ $# -ge 1 ] || { echo "usage: ubuntu x86 run PROGRAM [ARGS]" >&2; return 2; }
      if [ ! -f "$marker" ] || [ ! -d "$x86root/usr" ]; then
        echo "vscodroid: run  ubuntu x86 setup  first" >&2; return 1
      fi
      prog=$1; shift
      case "$prog" in
        */*) abs="$(cd "${prog%/*}" 2>/dev/null && pwd -P)/${prog##*/}" ;;
        *) abs="$(pwd -P)/$prog" ;;
      esac
      [ -f "$abs" ] || { echo "vscodroid: $prog: no such file" >&2; return 1; }
      id=$(printf '%s' "$abs" | cksum | cut -d' ' -f1)
      dst="$root/tmp/vsc-run/$id/${abs##*/}"
      mkdir -p "${dst%/*}" && cp -f "$abs" "$dst" && chmod 755 "$dst" || return 1
      VSCODROID_UB_EXTRA_BIND="$x86root:/opt/amd64" \
        __vscodroid_ub_exec qemu-x86_64-static -L /opt/amd64 "/tmp/vsc-run/$id/${abs##*/}" "$@"
      return $? ;;
    *) echo "usage: ubuntu x86 setup | ubuntu x86 run PROGRAM [ARGS]" >&2; return 2 ;;
  esac
}

# ---- repair / reinstall Ubuntu ----------------------------------------------------
# `ubuntu reset` wipes the Ubuntu system (every package installed in it) and
# installs it again. It removes only the Ubuntu folders inside the app's private
# storage. Projects in shared storage are never touched, and neither are the Git
# settings and sign-in (they live outside the Ubuntu system, see below).
# `ubuntu repair` looks first, and only reinstalls if Ubuntu is damaged.
#   --yes   skip the question (for scripts)
__vscodroid_ub_setup() { bash "$HOME/.vscodroid/proot-test.sh" ubuntu; }

__vscodroid_ub_healthy() {
  __vscodroid_ub_ready || return 1
  __vscodroid_ub_exec /bin/true >/dev/null 2>&1 || return 1
  local audit
  audit=$(__vscodroid_ub_exec dpkg --audit 2>&1) || return 1
  [ -z "$audit" ]
}

__vscodroid_ub_reset() {
  local mode=$1 a yes=0 root x86 ans tty
  shift
  for a in "$@"; do case "$a" in -y|--yes) yes=1 ;; esac; done
  root=$(__vscodroid_ub_root)
  # Only the Ubuntu folders in private storage may ever be removed.
  case "$root" in
    /storage/*|/sdcard/*|/mnt/*|""|/) echo "vscodroid: refusing to reset '$root': it is not in the app's private storage" >&2; return 1 ;;
    */proot/ubuntu) ;;
    *) echo "vscodroid: refusing to reset '$root': not the Ubuntu system folder" >&2; return 1 ;;
  esac
  x86="${root%/*}/ubuntu-amd64"

  if [ "$mode" = repair ] && __vscodroid_ub_healthy; then
    echo "vscodroid: Ubuntu looks healthy. To reinstall it anyway, run:  ubuntu reset"
    return 0
  fi
  if [ ! -d "$root" ]; then
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
  chmod -R u+rwX "$root" 2>/dev/null
  rm -rf "$root"
  if [ -d "$x86" ]; then chmod -R u+rwX "$x86" 2>/dev/null; rm -rf "$x86"; fi
  __vscodroid_ub_unlock
  if [ -e "$root" ]; then echo "vscodroid: could not remove all of $root" >&2; return 1; fi

  echo "vscodroid: installing Ubuntu again (a few minutes)..."
  if __vscodroid_ub_setup; then
    echo "vscodroid: Ubuntu is ready again. Your project files were not touched. Python virtual environments made before need to be created again."
    __vscodroid_ub_git_bg
    return 0
  fi
  echo "vscodroid: the reinstall did not finish. Run  ubuntu reset  again when the phone is online." >&2
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
  [ -f "$(__vscodroid_ub_root)/var/lib/vscodroid/provisioned/git" ] && return 0
  __vscodroid_ub_git_started=1
  ( trap '' HUP; __vscodroid_ub_git_bootstrap ) >/dev/null 2>&1 &
  echo "vscodroid: Git is being set up inside Ubuntu in the background (log: ~/.vscodroid/git-setup.log)" >&2
  return 0
}

# ubuntu git-login [host]: the token is typed hidden and handed to git on its
# standard input, so it never appears in a command line, shell history or a project.
__vscodroid_ub_git_login() {
  local host=${1:-github.com} d user token
  d=$(__vscodroid_ub_git_dir)
  __vscodroid_ub_git_configure || return 1
  printf 'Username for %s: ' "$host" >&2; read -r user
  printf 'Token (typing is hidden): ' >&2; read -rs token; echo >&2
  if [ -z "$user" ] || [ -z "$token" ]; then echo "vscodroid: cancelled; nothing was saved" >&2; return 1; fi
  printf 'protocol=https\nhost=%s\nusername=%s\npassword=%s\n\n' "$host" "$user" "$token" |
    GIT_CONFIG_GLOBAL=/dev/null __vscodroid_orig_git -c "credential.helper=store --file $d/credentials" credential approve || return 1
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
  if [ -s "$d/credentials" ]; then echo "sign-in:     saved (private storage, $(stat -c %a "$d/credentials" 2>/dev/null))"; else echo "sign-in:     none saved"; fi
  repo=$(__vscodroid_orig_git rev-parse --git-dir 2>/dev/null)
  if [ -n "$repo" ] && grep -Eq '://[^/@[:space:]]+:[^/@[:space:]]+@|://(gh[pousr]_|github_pat_)[A-Za-z0-9_]+@' "$repo/config" 2>/dev/null; then
    echo "WARNING:     this repository's remote address contains a password or token. Change it with:  git remote set-url origin https://github.com/OWNER/REPO.git"
  fi
}

# A token typed into a remote address ends up in .git/config, inside the project.
__vscodroid_token_in_args() {
  local a
  for a in "$@"; do
    case "$a" in
      *://*:*@*|*://gh[pousr]_*@*|*://github_pat_*@*)
        if printf '%s' "$a" | grep -Eq '://[^/@[:space:]]+:[^/@[:space:]]+@|://(gh[pousr]_|github_pat_)[A-Za-z0-9_]+@'; then
          echo "vscodroid: that address contains a password or token. Git would write it into .git/config, inside your project." >&2
          echo "          Use the plain address (https://github.com/OWNER/REPO.git) and sign in instead: through VS Code (Source Control)," >&2
          echo "          or for Ubuntu's git:  ubuntu git-login   (override: VSCODROID_NO_TOKEN_GUARD=1)" >&2
          return 0
        fi ;;
    esac
  done
  return 1
}

ubuntu() {
  case "${1-}" in
    setup) __vscodroid_ub_setup && __vscodroid_ub_git_bg; return $? ;;
    reset|repair)
      __vscodroid_ub_reset "$@"; return $? ;;
    git-login)  shift; __vscodroid_ub_git_login "$@"; return $? ;;
    git-logout) shift; __vscodroid_ub_git_logout "$@"; return $? ;;
    git-check)  __vscodroid_ub_git_check; return $? ;;
    x86)
      shift
      if ! __vscodroid_ub_ready; then echo "vscodroid: the Ubuntu system is not installed yet. Run:  ubuntu setup" >&2; return 1; fi
      __vscodroid_ub_x86 "$@"; return $? ;;
    gui)
      shift
      if ! __vscodroid_ub_ready; then echo "vscodroid: the Ubuntu system is not installed yet. Run:  ubuntu setup" >&2; return 1; fi
      __vscodroid_ub_gui "$@"; return $? ;;
    help|-h|--help)
      echo "ubuntu            open a shell inside the Ubuntu system"
      echo "ubuntu CMD ...    run CMD there (ubuntu ./hello runs a built program)"
      echo "ubuntu setup      install the Ubuntu system (once)"
      echo "ubuntu repair     check Ubuntu and reinstall it only if it is damaged"
      echo "ubuntu reset      wipe and reinstall Ubuntu (projects are not touched)"
      echo "ubuntu git-login  save a GitHub token for Ubuntu's git (typed hidden)"
      echo "ubuntu git-logout / git-check"
      echo "ubuntu gui start  graphical desktop for Tkinter/Pygame (experimental)"
      echo "ubuntu x86 setup  run Intel (x86_64) programs through qemu (experimental)"
      echo "native CMD ...    run CMD on the phone itself, not in Ubuntu"
      return 0 ;;
  esac
  if ! __vscodroid_ub_ready; then
    echo "vscodroid: the Ubuntu system is not installed yet. Run:  ubuntu setup" >&2
    return 1
  fi
  __vscodroid_ub_git_bg
  if [ $# -eq 0 ]; then __vscodroid_ub_exec /bin/bash -l; return $?; fi
  case "$1" in
    */*) if [ -f "$1" ] && __vscodroid_ub_on_shared "$(cd "${1%/*}" 2>/dev/null && pwd -P)/${1##*/}"; then
           __vscodroid_ub_run_file "$@"; return $?
         fi ;;
  esac
  __vscodroid_ub_exec "$@"
}

native() { VSCODROID_NO_UBUNTU=1 "$@"; }

sudo() {
  if [ $# -eq 0 ]; then echo "usage: sudo COMMAND ..." >&2; return 1; fi
  while [ "${1-}" = -E ] || [ "${1-}" = -S ]; do shift; done
  ubuntu "$@"
}

for __n in gcc g++ cc c++ cpp make cmake python python3 pip pip3 cargo rustc go gofmt apt apt-get apt-cache dpkg; do
  if declare -F "$__n" >/dev/null 2>&1; then
    eval "$(declare -f "$__n" | sed "1s/^$__n *()/__vscodroid_ub_orig_$__n ()/")"
    __vscodroid_ub_nat[$__n]=1
  else
    eval "__vscodroid_ub_orig_$__n() { command $__n \"\$@\"; }"
    command -v "$__n" >/dev/null 2>&1 && __vscodroid_ub_nat[$__n]=1 || __vscodroid_ub_nat[$__n]=0
  fi
  eval "$__n() { __vscodroid_ub_cmd $__n \"\$@\"; }"
done
unset __n

# ---- keep tokens out of project files -------------------------------------------
# The phone's own `git` refuses a remote address that carries a password or token
# (VSCODROID_NO_TOKEN_GUARD=1 turns this off).
if declare -F git >/dev/null 2>&1; then
  eval "$(declare -f git | sed '1s/^git *()/__vscodroid_orig_git ()/')"
else
  __vscodroid_orig_git() { command git "$@"; }
fi
git() {
  if [ -z "${VSCODROID_NO_TOKEN_GUARD-}" ]; then
    case "${1-}" in
      remote) case "${2-}" in add|set-url) __vscodroid_token_in_args "${@:3}" && return 1 ;; esac ;;
      clone|fetch|pull|push|ls-remote) __vscodroid_token_in_args "${@:2}" && return 1 ;;
    esac
  fi
  __vscodroid_orig_git "$@"
}
