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
__vscodroid_ln_impl() {
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

# ---- Ubuntu routing (gcc, g++, make, python, cargo, go, apt ...) ---------------
# Defined last, so it can wrap the python functions above.
[ -f "$HOME/.vscodroid/ubuntu-env.sh" ] && . "$HOME/.vscodroid/ubuntu-env.sh"

# ---- Open the browser for a dev server ----------------------------------------
# VS Code normally spots a running server by reading /proc/net/tcp, which Android
# has closed to apps, so nothing opens by itself. After `npm start`, `npm run dev`
# and friends (and `python -m http.server`, `manage.py runserver`), the likely
# ports are tried once a second; the first one that starts answering (and was not
# answering before the command began) is opened in the phone's browser.
#
#   VSCODROID_NO_PREVIEW=1   turns this off
#   VSCODROID_OPEN_CMD=...   how a page is opened (default: Android's VIEW intent)
#   xdg-open <web address>   opens an address by hand

__vscodroid_open_url() {
  [ -z "${VSCODROID_NO_PREVIEW-}" ] || return 1
  if [ -n "${VSCODROID_OPEN_CMD-}" ]; then ${VSCODROID_OPEN_CMD} "$1"; return $?; fi
  command -v am >/dev/null 2>&1 || return 1
  am start -a android.intent.action.VIEW -d "$1" >/dev/null 2>&1
}

xdg-open() {
  case "${1-}" in
    http://*|https://*) __vscodroid_open_url "$1" || { printf '%s\n' "$1"; return 1; } ;;
    *) echo "vscodroid: only web addresses can be opened from the terminal" >&2; return 1 ;;
  esac
}

__vscodroid_port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# The port named in a command line (--port 4000, --port=4000, -p 4000), if any.
__vscodroid_port_arg() {
  local prev="" a
  for a in "$@"; do
    case "$a" in --port=*) a=${a#--port=}; case "$a" in ''|*[!0-9]*) ;; *) printf '%s' "$a"; return 0 ;; esac ;; esac
    case "$prev" in
      --port|-p) case "$a" in ''|*[!0-9]*) ;; *) printf '%s' "$a"; return 0 ;; esac ;;
    esac
    prev=$a
  done
  return 1
}

# The watcher runs only while the flag file exists; the command's end (or Ctrl+C)
# removes it, so nothing is left polling after a server is stopped.
__vscodroid_preview_watch() {
  local flag=$1 waited=0 p
  shift
  while [ -e "$flag" ] && [ $waited -lt "${VSCODROID_PREVIEW_SECONDS:-120}" ]; do
    for p in "$@"; do
      if __vscodroid_port_open "$p"; then
        if __vscodroid_open_url "http://localhost:$p"; then
          echo "vscodroid: opened http://localhost:$p in the browser" >&2
        else
          echo "vscodroid: your app is running at http://localhost:$p" >&2
        fi
        return 0
      fi
    done
    sleep 1; waited=$((waited + 1))
  done
}

# __vscodroid_with_preview "default ports" command args...
__vscodroid_with_preview() {
  local ports=$1 p hint; shift
  if [ -n "${VSCODROID_NO_PREVIEW-}" ]; then "$@"; return $?; fi
  hint=$(__vscodroid_port_arg "$@")
  [ -n "$hint" ] || case "${PORT-}" in ''|*[!0-9]*) ;; *) hint=$PORT ;; esac
  [ -n "$hint" ] && ports=$hint
  local -a fresh=()
  for p in $ports; do __vscodroid_port_open "$p" || fresh+=("$p"); done
  if [ ${#fresh[@]} -eq 0 ]; then "$@"; return $?; fi
  local flag st old
  flag=$(mktemp "${TMPDIR:-/tmp}/vscodroid-pv.XXXXXX" 2>/dev/null) || { "$@"; return $?; }
  ( __vscodroid_preview_watch "$flag" "${fresh[@]}" & ) >/dev/null 2>&1
  # With a trap on INT the shell carries on after Ctrl+C stopped the command, so the
  # cleanup below always runs and the prompt comes back.
  old=$(trap -p INT)
  trap "rm -f '$flag'" INT
  "$@"; st=$?
  rm -f "$flag"
  if [ -n "$old" ]; then eval "$old"; else trap - INT; fi
  return $st
}

# Keep what npm, python3 and python are now (they may already be wrappers).
for __n in npm python3 python; do
  if declare -F "$__n" >/dev/null 2>&1; then
    eval "$(declare -f "$__n" | sed "1s/^$__n *()/__vscodroid_pv_$__n ()/")"
  else
    eval "__vscodroid_pv_$__n() { command $__n \"\$@\"; }"
  fi
done
unset __n

npm() {
  case "${1-}:${2-}" in
    start:*|run:start|run:dev|run:serve|run:preview|run:develop|run-script:start|run-script:dev)
      __vscodroid_with_preview "3000 5173 4173 8080 4200 3001 5174" __vscodroid_pv_npm "$@" ;;
    *) __vscodroid_pv_npm "$@" ;;
  esac
}

__vscodroid_py_preview() {
  local n=$1 a port=8000; shift
  case "${1-} ${2-}" in
    "-m http.server")
      for a in "${@:3}"; do case "$a" in ''|*[!0-9]*) ;; *) port=$a ;; esac; done
      __vscodroid_with_preview "$port" "__vscodroid_pv_$n" "$@"; return $? ;;
  esac
  case "${1-}:${2-}" in
    manage.py:runserver|*/manage.py:runserver)
      __vscodroid_with_preview 8000 "__vscodroid_pv_$n" "$@"; return $? ;;
  esac
  "__vscodroid_pv_$n" "$@"
}
python3() { __vscodroid_py_preview python3 "$@"; }
python() { __vscodroid_py_preview python "$@"; }

# ---- say what shared storage cannot do, accurately ------------------------------------
# Android's shared storage cannot hold symbolic or hard links, change permission bits or
# owners, or hold special files (pipes, device nodes), and nothing in it can be executed.
# When cp, mv, tar, ln, chmod, chown, chgrp, mkfifo or mknod fails there, the tool's own
# error is shown exactly as always, and ONE more line names the real cause. That line is
# added only when all of these hold: the folder is in shared storage and is writable, the
# error text is one of the kind such a limit produces, and the folder really cannot do
# that operation (checked by trying it). A missing file, a full disk, a genuine
# permission problem and everything else are left exactly as the tool printed them.
#
#   VSCODROID_NO_FS_NOTES=1   turns the extra line off

declare -A __vscodroid_fs_ok 2>/dev/null

# Is this folder under shared storage (by name)? No filesystem call.
__vscodroid_shared_name() {
  local pre
  for pre in ${VSCODROID_SHARED_PREFIXES:-/storage /sdcard /mnt/sdcard /mnt/user /mnt/media_rw}; do
    case "$1" in "$pre"|"$pre"/*) return 0 ;; esac
  done
  return 1
}

# Does <operation> work in <folder>? Asked by trying it. Test hook: VSCODROID_FS_PROBE=ok|fail.
__vscodroid_op_works() {
  local op=$1 d=$2 key t1 t2 r=1
  case "${VSCODROID_FS_PROBE-}" in ok) return 0 ;; fail) return 1 ;; esac
  key="$op:$d"
  if [ -n "${__vscodroid_fs_ok[$key]+x}" ]; then [ "${__vscodroid_fs_ok[$key]}" = 1 ]; return $?; fi
  t1="$d/.vscodroid-op.$$"; t2="$d/.vscodroid-op2.$$"
  case "$op" in
    symlink)  command ln -s . "$t1" 2>/dev/null && r=0 ;;
    hardlink) : > "$t1" 2>/dev/null && command ln "$t1" "$t2" 2>/dev/null && r=0 ;;
    chmod)    : > "$t1" 2>/dev/null && command chmod 741 "$t1" 2>/dev/null && [ "$(command stat -c %a "$t1" 2>/dev/null)" = 741 ] && r=0 ;;
    fifo)     command mkfifo "$t1" 2>/dev/null && r=0 ;;
  esac
  rm -f "$t1" "$t2" 2>/dev/null
  __vscodroid_fs_ok[$key]=$((1 - r))
  return $r
}

# __vscodroid_fs_explain <error text> <folder written to>
__vscodroid_fs_explain() {
  local text=$1 d=$2 said="" line op what hint
  __vscodroid_shared_name "$d" && [ -w "$d" ] || return 0
  while IFS= read -r line; do
    printf '%s' "$line" | grep -Eqi 'Operation not permitted|not supported|Function not implemented|Permission denied|Invalid argument' || continue
    case "$line" in
      *"symbolic link"*|*symlink*|*Symlink*) op=symlink ;;
      *"hard link"*|*"Cannot hard link"*) op=hardlink ;;
      *"preserving permissions"*|*"Cannot change mode"*|*"changing permissions"*|*"Cannot change ownership"*|*"changing ownership"*|*"Cannot chmod"*|*"Cannot chown"*) op=chmod ;;
      *mkfifo*|*mknod*|*"create node"*|*"special file"*) op=fifo ;;
      *) continue ;;
    esac
    case " $said " in *" $op "*) continue ;; esac
    __vscodroid_op_works "$op" "$d" && continue
    said="$said $op"
    case "$op" in
      symlink)  what="symbolic links"; hint="Keep what needs them in a folder outside shared storage, such as ~ in Ubuntu." ;;
      hardlink) what="hard links"; hint="A copy can stand in for one." ;;
      chmod)    what="changing permission bits or owners"; hint="Files there cannot be made executable; run a script with 'bash script.sh' or a program with 'ubuntu ./prog'." ;;
      fifo)     what="pipes and device files"; hint="Create them in a folder outside shared storage." ;;
    esac
    echo "vscodroid: Android public storage does not support $what ($d). The error above comes from that limit, not from the command. $hint" >&2
  done <<EOF
$text
EOF
  return 0
}

# Where is a command writing? The folder named by -C/--directory, else (for tar) the
# current folder, else the folder of its last path argument.
__vscodroid_fs_where() {
  local kind=$1 a last="" dir="" skip=0 p
  shift
  for a in "$@"; do
    if [ $skip -eq 1 ]; then dir=$a; skip=0; continue; fi
    case "$a" in
      -C|--directory) skip=1 ;;
      --directory=*) dir=${a#--directory=} ;;
      -*) ;;
      *) last=$a ;;
    esac
  done
  if [ -n "$dir" ]; then (cd "$dir" 2>/dev/null && pwd -P) && return; fi
  if [ "$kind" != tar ] && [ -n "$last" ]; then
    if [ -d "$last" ]; then (cd "$last" 2>/dev/null && pwd -P) && return; fi
    p=${last%/*}; [ "$p" = "$last" ] && p=.
    (cd "$p" 2>/dev/null && pwd -P) && return
  fi
  pwd -P
}

# Cheap test with no process started: does the current folder or any argument sit in shared storage?
__vscodroid_fs_touches_shared() {
  local a
  __vscodroid_shared_name "$PWD" && return 0
  for a in "$@"; do case "$a" in /*) __vscodroid_shared_name "$a" && return 0 ;; esac; done
  return 1
}

# __vscodroid_fs_run <function that runs the tool> <kind> args...
__vscodroid_fs_run() {
  local fn=$1 kind=$2 d tmp st
  shift 2
  if [ -n "${VSCODROID_NO_FS_NOTES-}" ] || ! __vscodroid_fs_touches_shared "$@"; then "$fn" "$@"; return $?; fi
  d=$(__vscodroid_fs_where "$kind" "$@")
  tmp=$(mktemp "${TMPDIR:-/tmp}/vscodroid-fs.XXXXXX" 2>/dev/null) || { "$fn" "$@"; return $?; }
  # The tool's own error text still reaches the terminal as it is written.
  "$fn" "$@" 2> >(tee "$tmp" >&2)
  st=$?
  wait $! 2>/dev/null
  [ $st -ne 0 ] && __vscodroid_fs_explain "$(cat "$tmp" 2>/dev/null)" "$d"
  rm -f "$tmp"
  return $st
}

for __n in cp mv tar chmod chown chgrp mkfifo mknod; do
  if declare -F "$__n" >/dev/null 2>&1; then
    eval "$(declare -f "$__n" | sed "1s/^$__n *()/__vscodroid_fs_orig_$__n ()/")"
  else
    eval "__vscodroid_fs_orig_$__n() { command $__n \"\$@\"; }"
  fi
  eval "$__n() { __vscodroid_fs_run __vscodroid_fs_orig_$__n $__n \"\$@\"; }"
done
unset __n
ln() { __vscodroid_fs_run __vscodroid_ln_impl ln "$@"; }
