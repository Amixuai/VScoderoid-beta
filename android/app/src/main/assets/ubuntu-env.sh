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
#
# Android will not start a program that is stored in shared storage (the
# workspace). So that `./hello` works after `gcc hello.c -o hello` as on a PC,
# a function named ./hello is defined for each program built there; it runs a
# private copy inside Ubuntu. `ubuntu ./hello` does the same explicitly.

[ "${VSCODROID_PLATFORM-}" = "android" ] || return 0
declare -F __vscodroid_ub_loaded >/dev/null 2>&1 && return 0
__vscodroid_ub_loaded() { :; }

__vscodroid_ub_root() { printf '%s' "${VSCODROID_UBUNTU_ROOT:-$HOME/proot/ubuntu}"; }

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

  local gpath=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  local -a envv=(HOME=/root "TERM=${TERM:-xterm}" LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive
                 PIP_BREAK_SYSTEM_PACKAGES=1 PIP_ROOT_USER_ACTION=ignore)
  if [ -n "${VSCODROID_VENV-}" ]; then
    envv+=("VIRTUAL_ENV=$VSCODROID_VENV"); gpath="$VSCODROID_VENV/bin:$gpath"
  fi
  envv+=("PATH=$gpath")
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
  if __vscodroid_ub_exec apt-get update -qq && __vscodroid_ub_exec apt-get install -y -qq --no-install-recommends $pkgs; then
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

ubuntu() {
  case "${1-}" in
    setup) bash "$HOME/.vscodroid/proot-test.sh" ubuntu; return $? ;;
    help|-h|--help)
      echo "ubuntu            open a shell inside the Ubuntu system"
      echo "ubuntu CMD ...    run CMD there (ubuntu ./hello runs a built program)"
      echo "ubuntu setup      install the Ubuntu system (once)"
      echo "native CMD ...    run CMD on the phone itself, not in Ubuntu"
      return 0 ;;
  esac
  if ! __vscodroid_ub_ready; then
    echo "vscodroid: the Ubuntu system is not installed yet. Run:  ubuntu setup" >&2
    return 1
  fi
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
