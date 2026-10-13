# VSCodroid command wrapper.
#
# Lets you type ordinary developer commands (npm install, python -m venv ...)
# and quietly adds what Android's shared storage needs. Shared storage (where
# the workspace lives) is served through FUSE: today it cannot hold symbolic
# links and nothing in it can be executed.
#
# Nothing here is hard-wired to a particular Android version. Whether a folder
# can hold links is ASKED OF THE FILESYSTEM (a link is made and removed in it),
# so on a phone, or a later Android, where links work, every command below runs
# exactly as typed.
#
#   * Android only. Anywhere else this file does nothing, so desktop builds run
#     every command exactly as typed. The app sets VSCODROID_PLATFORM=android.
#   * Only where it matters: a command is changed only when it would write into
#     shared storage. Inside the app's own storage, and for global installs
#     (npm i -g), every command runs unchanged.
#   * Opt out for one command with `command npm ...` or VSCODROID_NO_WRAP=1.
#
# Sourced from .bashrc and from BASH_ENV, so it must print nothing when sourced.
# This copy is rewritten at every launch; edits here are lost.

[ "${VSCODROID_PLATFORM-}" = "android" ] || return 0
declare -F __vscodroid_wrap_loaded >/dev/null 2>&1 && return 0
__vscodroid_wrap_loaded() { :; }

# ---- helpers ---------------------------------------------------------------

# Nearest folder that exists, going up from a path that may not exist yet.
__vscodroid_nearest_dir() {
  local d=$1
  [ -d "$d" ] || d=${d%/*}
  while [ -n "$d" ] && [ ! -d "$d" ]; do d=${d%/*}; done
  printf '%s' "${d:-/}"
}

declare -A __vscodroid_links_ok 2>/dev/null

# Can a symbolic link be made in this folder? Asked by making one.
# VSCODROID_SYMLINK_PROBE: "fail" or "ok" skip the question (for tests).
__vscodroid_links_work() {
  case "${VSCODROID_SYMLINK_PROBE-}" in fail) return 1 ;; ok) return 0 ;; esac
  local d=$1 probe
  if [ -n "${__vscodroid_links_ok[$d]+x}" ]; then
    [ "${__vscodroid_links_ok[$d]}" = 1 ]
    return $?
  fi
  probe="$d/.vscodroid-link-probe.$$"
  if command ln -s . "$probe" 2>/dev/null; then
    rm -f "$probe" 2>/dev/null
    __vscodroid_links_ok[$d]=1
    return 0
  fi
  __vscodroid_links_ok[$d]=0
  return 1
}

# True where links cannot be made. The folder names are only a cheap first
# filter (so the app's own storage is never probed); the answer is the probe's.
__vscodroid_is_shared() {
  local pre named=1
  for pre in ${VSCODROID_SHARED_PREFIXES:-/storage /sdcard /mnt/sdcard /mnt/user /mnt/media_rw}; do
    case "$1" in "$pre"|"$pre"/*) named=0 ;; esac
  done
  [ $named -eq 0 ] || return 1
  __vscodroid_links_work "$(__vscodroid_nearest_dir "$1")" && return 1
  return 0
}

__vscodroid_cwd_shared() { __vscodroid_is_shared "$(pwd -P 2>/dev/null || pwd)"; }

# Keep whatever the command already was (the app defines npm, npx and the
# toolchain commands as functions) under another name, then wrap that.
__vscodroid_capture() {
  local n=$1
  if declare -F "$n" >/dev/null 2>&1; then
    eval "$(declare -f "$n" | sed "1s/^$n *()/__vscodroid_orig_$n ()/")"
  else
    eval "__vscodroid_orig_$n() { command $n \"\$@\"; }"
  fi
}

__vscodroid_have() { declare -F "$1" >/dev/null 2>&1 || command -v "$1" >/dev/null 2>&1; }

# ---- npm: no bin links on shared storage -------------------------------------

# Nearest folder up from here that has a package.json.
__vscodroid_project_root() {
  local d
  d=$(pwd -P 2>/dev/null || pwd)
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/package.json" ] && { printf '%s' "$d"; return 0; }
    d=${d%/*}
  done
  return 1
}

# Path of a local package command, from the list written after install.
__vscodroid_bin_path() {
  local n p
  [ -f "$1/node_modules/.vscodroid-bins" ] || return 1
  while IFS=' ' read -r n p; do
    if [ "$n" = "$2" ]; then
      case "$p" in ''|*[!A-Za-z0-9_./@-]*|*..*) return 1 ;; esac
      printf '%s' "$p"
      return 0
    fi
  done < "$1/node_modules/.vscodroid-bins"
  return 1
}

# npm normally links node_modules/.bin/<cmd>, so `vite` or `tsc` just work in
# scripts. Without links the same commands are defined as shell functions that
# run the package's file with node. Scripts started by npm get them too, since
# BASH_ENV sources this file.
__vscodroid_load_bins() {
  local root=$1 n p
  case "$root" in ''|*[\"\$\`\\]*) return 0 ;; esac
  [ -f "$root/node_modules/.vscodroid-bins" ] || return 0
  while IFS=' ' read -r n p; do
    case "$n" in ''|*[!A-Za-z0-9_.-]*) continue ;; esac
    case "$p" in ''|*[!A-Za-z0-9_./@-]*|*..*) continue ;; esac
    eval "$n() { node \"$root/node_modules/$p\" \"\$@\"; }"
  done < "$root/node_modules/.vscodroid-bins"
}

if __vscodroid_have npm; then
  __vscodroid_capture npm
  npm() {
    if [ -n "${VSCODROID_NO_WRAP-}" ] || ! __vscodroid_cwd_shared; then
      __vscodroid_orig_npm "$@"
      return $?
    fi
    local -a __args=()
    local __a __sub="" __global=0 __has=0 __flag=0 __regen=0
    for __a in "$@"; do
      case "$__a" in
        -g|--global|--global=true|--location=global) __global=1 ;;
        --no-bin-links|--bin-links|--bin-links=*) __has=1 ;;
      esac
    done
    for __a in "$@"; do
      __args+=("$__a")
      if [ -z "$__sub" ]; then
        case "$__a" in
          -*) ;;
          *)
            __sub=$__a
            case "$__a" in
              install|i|in|ins|inst|insta|instal|add|ci|clean-install|update|up|upgrade|install-test|it|install-ci-test|cit|rebuild|rb)
                __regen=1
                if [ $__has -eq 0 ]; then __args+=(--no-bin-links); __flag=1; fi ;;
              uninstall|remove|rm|un|unlink|r) __regen=1 ;;
            esac ;;
        esac
      fi
    done
    [ $__global -eq 1 ] && { __vscodroid_orig_npm "$@"; return $?; }
    local __root; __root=$(__vscodroid_project_root)
    [ -n "$__root" ] && __vscodroid_load_bins "$__root"
    __vscodroid_orig_npm "${__args[@]}"
    local __st=$?
    if [ $__st -eq 0 ] && [ $__regen -eq 1 ] && [ -n "$__root" ]; then
      node "$HOME/.vscodroid/bin-manifest.js" "$__root" 2>/dev/null
      __vscodroid_load_bins "$__root"
    fi
    return $__st
  }
fi

if __vscodroid_have npx; then
  __vscodroid_capture npx
  npx() {
    if [ -z "${VSCODROID_NO_WRAP-}" ] && [ $# -gt 0 ] && __vscodroid_cwd_shared; then
      case "$1" in
        -*) ;;
        *)
          local __root __p
          __root=$(__vscodroid_project_root) && __p=$(__vscodroid_bin_path "$__root" "$1") && {
            __vscodroid_load_bins "$__root"
            shift
            node "$__root/node_modules/$__p" "$@"
            return $?
          } ;;
      esac
    fi
    __vscodroid_orig_npx "$@"
  }
fi

# Scripts that npm starts: find the project from what npm tells them.
if [ -n "${npm_config_local_prefix-}" ] && __vscodroid_is_shared "$npm_config_local_prefix"; then
  __vscodroid_load_bins "$npm_config_local_prefix"
fi

# ---- python: virtual environments ---------------------------------------------

# A virtual environment needs symbolic links and a program it can start, and
# shared storage offers neither. So `python -m venv <dir>` on shared storage is
# created in the app's own storage instead (~/venvs/<name>-<id>), and <dir>/bin/
# gets a small activate file that points at it. `source <dir>/bin/activate` then
# works exactly as on a desktop. Sourcing needs no execute permission.
#
# Everything else about `python` (including `python -m venv` in internal
# storage, and every other `-m` module) runs unchanged.
__vscodroid_py() {
  local __c=$1; shift
  if [ -n "${VSCODROID_NO_WRAP-}" ] || [ "${1-}" != "-m" ] || [ "${2-}" != "venv" ]; then
    "__vscodroid_orig_$__c" "$@"
    return $?
  fi
  local __a __target="" __abs
  local -a __opts=()
  for __a in "${@:3}"; do
    case "$__a" in
      -*) __opts+=("$__a") ;;
      *) __target=$__a ;;
    esac
  done
  __abs=$__target
  case "$__abs" in /*) ;; *) __abs="$(pwd -P 2>/dev/null || pwd)/$__abs" ;; esac
  if [ -z "$__target" ] || ! __vscodroid_is_shared "$__abs"; then
    "__vscodroid_orig_$__c" "$@"
    return $?
  fi
  # --copies and --symlinks mean nothing for an environment that lives in
  # internal storage; the default (links) is what works there.
  local -a __keep=()
  for __a in "${__opts[@]}"; do
    case "$__a" in --copies|--symlinks) ;; *) __keep+=("$__a") ;; esac
  done
  local __name __id __home
  __name=$(basename "$__abs"); __name=${__name#.}; [ -n "$__name" ] || __name=env
  __id=$(printf '%s' "$__abs" | cksum | cut -d' ' -f1)
  __home="$HOME/venvs/$__name-$__id"
  mkdir -p "$HOME/venvs" 2>/dev/null
  "__vscodroid_orig_$__c" -m venv "${__keep[@]}" "$__home"
  local __st=$?
  [ $__st -eq 0 ] || return $__st
  mkdir -p "$__abs/bin" 2>/dev/null || return 0
  printf '%s\n' \
    "# VSCodroid: this environment lives in the app's own storage, because" \
    "# shared storage cannot hold one. Sourcing this file activates it." \
    ". \"$__home/bin/activate\"" > "$__abs/bin/activate"
  echo "vscodroid: environment created. Activate it with:  source $__target/bin/activate" >&2
  return 0
}

for __n in python3 python; do
  if __vscodroid_have "$__n"; then
    __vscodroid_capture "$__n"
    eval "$__n() { __vscodroid_py $__n \"\$@\"; }"
  fi
done
unset __n

# ---- ln: copy where a link cannot be made --------------------------------------

# `ln -s a b` (and `ln a b`) in a folder that cannot hold links would fail with
# "Operation not permitted". There, the thing that was asked for is made as a
# COPY instead, and one line says so. A copy is not a link: later changes to the
# original do not show up in it. If the target does not exist yet (a link to
# something created later) there is nothing to copy and the real error is shown.
ln() {
  if [ -n "${VSCODROID_NO_WRAP-}" ]; then command ln "$@"; return $?; fi
  local __a __end=0 __force=0 __notd=0 __odd=0
  local -a __pos=()
  for __a in "$@"; do
    if [ $__end -eq 0 ]; then
      case "$__a" in
        --) __end=1; continue ;;
        --force) __force=1; continue ;;
        --no-target-directory) __notd=1; continue ;;
        --symbolic|--verbose|--interactive|--logical|--physical|--relative|--no-dereference) continue ;;
        --*) __odd=1; continue ;;
        -?*)
          case "$__a" in *t*) __odd=1 ;; esac
          case "$__a" in *f*) __force=1 ;; esac
          case "$__a" in *T*) __notd=1 ;; esac
          continue ;;
      esac
    fi
    __pos+=("$__a")
  done
  local __out __st
  __out=$(command ln "$@" 2>&1); __st=$?
  if [ $__st -eq 0 ]; then [ -z "$__out" ] || printf '%s\n' "$__out"; return 0; fi
  local __target __link __src
  if [ $__odd -eq 1 ] || [ ${#__pos[@]} -lt 1 ] || [ ${#__pos[@]} -gt 2 ]; then
    printf '%s\n' "$__out" >&2; return $__st
  fi
  __target=${__pos[0]}
  __link=${__pos[1]:-${__target##*/}}
  if [ -d "$__link" ] && [ $__notd -eq 0 ]; then __link="${__link%/}/${__target##*/}"; fi
  local __ld=${__link%/*}; [ "$__ld" = "$__link" ] && __ld=.
  if ! __vscodroid_is_shared "$(cd "$__ld" 2>/dev/null && pwd -P || printf '%s' "$__ld")"; then
    printf '%s\n' "$__out" >&2; return $__st
  fi
  case "$__target" in /*) __src=$__target ;; *) __src="$__ld/$__target" ;; esac
  if [ ! -e "$__src" ]; then printf '%s\n' "$__out" >&2; return $__st; fi
  if [ -e "$__link" ] || [ -L "$__link" ]; then
    if [ $__force -eq 1 ]; then rm -rf -- "$__link"
    else echo "ln: failed to create link '$__link': File exists" >&2; return 1; fi
  fi
  if command cp -R -- "$__src" "$__link" 2>/dev/null; then
    echo "vscodroid: this folder cannot hold links, so '$__link' is a copy of '$__target'" >&2
    return 0
  fi
  printf '%s\n' "$__out" >&2
  return $__st
}
