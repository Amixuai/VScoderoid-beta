# VSCodroid: keep Git tokens out of project files, output and history.
#
# Used by two callers with the same code: the phone's own `git` (a shell function in
# ubuntu-env.sh) and the `git` inside Ubuntu (/usr/local/bin/git, written from this file).
# Defines functions only; prints nothing when sourced.
#
# What it does:
#  - refuses clone, fetch, pull, push, ls-remote, remote, config and submodule commands
#    whose arguments carry a remote address with a password or token
#    (https://user:password@host/..., https://ghp_...@host/...), and any `-c name=value`
#    that does. Git would otherwise write such an address into .git/config, inside the
#    project. Global options such as -C <path> and -c are skipped to find the command.
#  - hides a password or token already stored in a remote when `git remote -v|show|get-url`
#    or `git config --list|--get...` print it.
#  - drops a typed line that carries such an address from the shell history.
# Ordinary HTTPS, SSH and scp-style addresses, and a user name with no password, are not
# touched. VSCODROID_NO_TOKEN_GUARD=1 turns it all off.

__vscodroid_tg_has_token() {
  printf '%s' "$1" | grep -Eq '://[^/@[:space:]]+:[^/@[:space:]]+@|://(gh[pousr]_|github_pat_)[A-Za-z0-9_]+@'
}

__vscodroid_tg_mask() {
  sed -E 's#(://)[^/@[:space:]]+:[^/@[:space:]]+@#\1***@#g; s#(://)(gh[pousr]_|github_pat_)[A-Za-z0-9_]+@#\1***@#g'
}

# Finds git's command word past the global options. Sets __tg_sub, __tg_rest (the words
# after it) and __tg_bad=1 if a global `-c name=value` carries a token address.
__vscodroid_tg_parse() {
  local -a a=("$@")
  local i=0 n=${#a[@]} w
  __tg_sub=""; __tg_rest=(); __tg_bad=0
  while [ $i -lt $n ]; do
    w=${a[$i]}
    case "$w" in
      -C|--git-dir|--work-tree|--namespace|--super-prefix|--config-env) i=$((i + 2)) ;;
      -c)
        if __vscodroid_tg_has_token "${a[$((i + 1))]-}"; then __tg_bad=1; fi
        i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) __tg_sub=$w; __tg_rest=("${a[@]:$((i + 1))}"); return 0 ;;
    esac
  done
  return 0
}

# Returns 0 (and says why) when the command must be refused; the address is never printed.
__vscodroid_tg_check() {
  local w refuse=0
  __vscodroid_tg_parse "$@"
  [ "$__tg_bad" = 1 ] && refuse=1
  case "$__tg_sub" in
    clone|fetch|pull|push|ls-remote|remote|config|submodule)
      for w in "${__tg_rest[@]}"; do
        if __vscodroid_tg_has_token "$w"; then refuse=1; break; fi
      done ;;
  esac
  [ $refuse -eq 1 ] || return 1
  echo "vscodroid: that command carries a password or token in a remote address. Git would write it into .git/config, inside your project." >&2
  echo "          Use the plain address (https://github.com/OWNER/REPO.git) and sign in instead: through VS Code (Source Control)," >&2
  echo "          or let Ubuntu's git ask for the username and token itself when it needs them   (override: VSCODROID_NO_TOKEN_GUARD=1)" >&2
  return 0
}

# Does this command print remotes or configuration? Then its output is masked.
__vscodroid_tg_wants_mask() {
  local w
  __vscodroid_tg_parse "$@"
  case "$__tg_sub" in
    remote)
      for w in "${__tg_rest[@]}"; do case "$w" in -v|--verbose|show|get-url) return 0 ;; esac; done ;;
    config)
      for w in "${__tg_rest[@]}"; do
        case "$w" in -e|--edit|--unset|--unset-all|--add|--replace-all|--remove-section|--rename-section) return 1 ;; esac
      done
      for w in "${__tg_rest[@]}"; do
        case "$w" in -l|--list|--get|--get-all|--get-regexp|--get-urlmatch|--show-origin) return 0 ;; esac
      done ;;
  esac
  return 1
}

# __vscodroid_tg_run <real git: a path or a function> args...  ->  the real result
__vscodroid_tg_run() {
  local real=$1
  shift
  if [ -z "${VSCODROID_NO_TOKEN_GUARD-}" ]; then
    __vscodroid_tg_check "$@" && return 1
    if __vscodroid_tg_wants_mask "$@"; then
      "$real" "$@" | __vscodroid_tg_mask
      return "${PIPESTATUS[0]}"
    fi
  fi
  "$real" "$@"
}

# For PROMPT_COMMAND: forget the line just typed if it carries such an address.
__vscodroid_tg_scrub_history() {
  local l
  l=$(HISTTIMEFORMAT= history 1 2>/dev/null) || return 0
  if __vscodroid_tg_has_token "$l"; then history -d $((HISTCMD - 1)) 2>/dev/null; fi
  return 0
}
