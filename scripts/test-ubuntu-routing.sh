#!/usr/bin/env bash
# Sandbox test for the Ubuntu routing (ubuntu-env.sh) and the shared-storage notes
# (command-wrapper.sh). It runs the real scripts with a STAND-IN for proot, so it
# proves the shell logic (what is called, in what order, with which arguments and
# exit codes). It does not prove anything about Android, SELinux, real proot or a
# real Ubuntu; those need a phone (see docs/DEVICE_TESTS_*.md).
#
#   bash scripts/test-ubuntu-routing.sh
#
# Exit status 0 when every check passes.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ASSETS=${ASSETS:-$HERE/../android/app/src/main/assets}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2-}" ] && printf '        %s\n' "$2"; }
check() { # check <name> <condition status 0=true>
  if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1" "${3-}"; fi
}
contains() { grep -qF -- "$2" "$1" 2>/dev/null; }

# ---- stand-ins ------------------------------------------------------------------
mkdir -p "$T/bin" "$T/guest"
cat > "$T/bin/proot" <<'EOF'
#!/bin/bash
# Stand-in for proot: skips its options, then runs the command on the host with a fake
# "guest" folder first on PATH. The guest's /root (and /proc/ubuntu-root, a path no phone
# can create) is mapped to a test folder, and the environment the caller passes to
# `env -i` is applied, so what the real routing hands to Ubuntu can be observed.
GH=${GUEST_HOME:?}
rew() {
  local x=$1
  x=${x//\/proc\/ubuntu-root\//$GH/}; x=${x//\/root\//$GH/}; [ "$x" = /root ] && x=$GH
  [ -n "${UB_ROOT-}" ] && x=${x//\/tmp\/vsc-run\//$UB_ROOT/tmp/vsc-run/}
  printf '%s' "$x"
}
cwd=.
while [ $# -gt 0 ] && [ "$1" != /usr/bin/env ]; do
  [ "$1" = -w ] && { cwd=$2; shift; }
  shift
done
shift 2   # /usr/bin/env -i
envs=(); gpath=""
while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do
  k=${1%%=*}; v=$(rew "${1#*=}")
  case "$k" in PATH) gpath=$v ;; HOME) ;; *) envs+=("$k=$v") ;; esac
  shift
done
args=(); for a in "$@"; do args+=("$(rew "$a")"); done
front=""
IFS=: read -ra parts <<< "$gpath"
for d in "${parts[@]}"; do
  case "$d" in /usr/local/*|/usr/*|/bin|/sbin|"") ;; *) [ -d "$d" ] && front+="$d:" ;; esac
done
cd "$cwd" 2>/dev/null
printf '%s\n' "$*" >> "${PROOT_LOG:-/dev/null}"
exec env -i "${envs[@]}" HOME="$GH" PATH="$front$FAKE_GUEST:${GUEST_EXTRA_PATH:+$GUEST_EXTRA_PATH:}$PATH" ${GUEST_KEEP_LANG:+LANG=C.UTF-8} "${args[@]}"
EOF
cat > "$T/bin/loader" <<'EOF'
#!/bin/sh
EOF
cat > "$T/guest/python3" <<'EOF'
#!/bin/bash
# Real Python, except where a test asks for a broken `-m venv`.
if [ "$1" = -m ] && [ "$2" = venv ]; then
  [ "${FAKE_VENV_FAIL-}" = 1 ] && { echo "Error: fake venv failure" >&2; exit 3; }
  [ "${FAKE_VENV_EMPTY-}" = 1 ] && exit 0
fi
exec /usr/bin/python3 "$@"
EOF
cat > "$T/guest/gcc" <<'EOF'
#!/bin/bash
printf 'gcc-arg:%s\n' "$@"
exit "${FAKE_GCC_STATUS:-0}"
EOF
cat > "$T/guest/apt-get" <<'EOF'
#!/bin/bash
echo "apt-get $*" >> "$APT_LOG"
exit "${FAKE_APT_STATUS:-0}"
EOF
cat > "$T/guest/dpkg" <<'EOF'
#!/bin/bash
echo "dpkg $*" >> "$APT_LOG"
case "$1" in
  --audit) [ -f "$AUDIT" ] && cat "$AUDIT" ;;
  --configure) rm -f "$AUDIT" ;;
esac
exit 0
EOF
cat > "$T/guest/qemu-x86_64-static" <<'EOF'
#!/bin/bash
echo "qemu-ran:$*" >> "$APT_LOG"
exit 0
EOF
cat > "$T/guest/cmake" <<'EOF'
#!/bin/bash
echo "cmake-ran:$*"
EOF
cat > "$T/setup-stub.sh" <<'EOF'
#!/bin/bash
# Stand-in for proot-test.sh: unpacks a fake Ubuntu the way the real one marks it.
echo "setup-called $1" >> "$SETUP_LOG"
sleep "${FAKE_SETUP_SLEEP:-0}"
ROOT="$HOME/proot/$1"
mkdir -p "$ROOT/bin" "$ROOT/etc"
: > "$ROOT/.vscodroid-installing"
[ -n "${FAKE_SETUP_FAIL-}" ] && exit 1
: > "$ROOT/bin/sh"
echo 'ID=ubuntu' > "$ROOT/etc/os-release"
if [ "$1" = ubuntu-amd64 ]; then mkdir -p "$ROOT/lib64" "$ROOT/usr"; : > "$ROOT/lib64/ld-linux-x86-64.so.2"; fi
rm -f "$ROOT/.vscodroid-installing"
echo "$1" > "$ROOT/.vscodroid-ubuntu"
exit 0
EOF
cat > "$T/guest/javac" <<'EOF'
#!/bin/bash
printf 'javac-arg:%s\n' "$@"
echo "cwd:$PWD"
exit "${FAKE_JAVAC_STATUS:-0}"
EOF
cat > "$T/guest/slowtool" <<'EOF'
#!/bin/bash
echo "SLOW-""RUNNING"
exec sleep 64
EOF
cat > "$T/guest/apt" <<'EOF'
#!/bin/bash
echo "apt $*" >> "$APT_LOG"
exit "${FAKE_APT_STATUS:-0}"
EOF
chmod +x "$T/bin/"* "$T/guest/"* "$T/setup-stub.sh"

# The phone has no gcc, apt or dpkg of its own, so the sandbox must not either: a PATH
# holding only the plain tools the scripts use.
mkdir -p "$T/hostbin"
for c in bash env cat sleep grep sed awk df cksum od dd head tr find rm mkdir cp mv mktemp tee date stat \
         readlink ls touch chmod cut wc kill true false printf python3 python dirname basename sort uniq \
         tail ln id pwd ps pgrep xargs expr test timeout node npm npx sh uname; do
  p=$(command -v "$c" 2>/dev/null) && [ -x "$p" ] && ln -sf "$p" "$T/hostbin/$c"
done
ln -sf /usr/bin/test "$T/hostbin/test"; ln -sf /usr/bin/test "$T/hostbin/["
BASE_PATH="$T/hostbin"

# A guest with the container's real compilers and make (for real build tests) ...
mkdir -p "$T/guestreal" "$T/guest2"
for c in gcc g++ cc c++ make pip pip3 as ld ld.bfd ar ranlib nm strip objcopy sh; do p=$(command -v "$c" 2>/dev/null) && ln -sf "$p" "$T/guestreal/$c"; done
cat > "$T/guestreal/python3" <<'EOF'
#!/bin/bash
exec /usr/bin/python3 "$@"
EOF
cat > "$T/guestreal/qemu-x86_64-static" <<'EOF'
#!/bin/bash
# Stand-in for qemu-user: this container is itself x86_64, so run the program directly.
[ "$1" = -L ] && shift 2
exec "$@"
EOF
chmod +x "$T/guestreal/"*
# ... and one whose commands only report how they were called (for the command audit).
cat > "$T/guest2/audit-tool" <<'EOF'
#!/bin/bash
n=${0##*/}
[ "$n" = dpkg ] && [ "$1" = --audit ] && exit 0
printf '%s-args:' "$n"; printf ' [%s]' "$@"; echo
echo "$n-cwd:$PWD"
echo "$n-env:${AUDIT_VAR-unset}"
echo "$n-err" >&2
[ "${AUDIT_STDIN-}" = 1 ] && echo "$n-stdin:$(cat)"
exit "${AUDIT_STATUS:-0}"
EOF
chmod +x "$T/guest2/audit-tool"
for c in python python3 pip pip3 gcc g++ cc c++ make cmake rustc apt apt-get dpkg; do ln -sf audit-tool "$T/guest2/$c"; done

N=0
newenv() {
  export PATH="$BASE_PATH"
  N=$((N + 1))
  H="$T/h$N"; WS="$T/shared/ws$N"
  mkdir -p "$H/.vscodroid" "$WS"
  cp "$ASSETS/command-wrapper.sh" "$ASSETS/ubuntu-env.sh" "$ASSETS/git-token-guard.sh" "$H/.vscodroid/" 2>/dev/null
  cp "$T/setup-stub.sh" "$H/.vscodroid/proot-test.sh"
  : > "$T/setup.log"; : > "$T/apt.log"; : > "$T/proot.log"; rm -f "$T/audit"
  export HOME="$H" VSCODROID_PLATFORM=android VSCODROID_PROOT="$T/bin/proot" PROOT_LOADER="$T/bin/loader"
  export GUEST_HOME="$T/guesthome$N"; mkdir -p "$GUEST_HOME"
  export UB_ROOT="$H/proot/ubuntu"; unset GUEST_EXTRA_PATH
  export FAKE_GUEST="$T/guest" SETUP_LOG="$T/setup.log" APT_LOG="$T/apt.log" PROOT_LOG="$T/proot.log" AUDIT="$T/audit"
  export VSCODROID_SHARED_PREFIXES="$T/shared" VSCODROID_NO_PREVIEW=1 TMPDIR="$T"
  unset FAKE_SETUP_FAIL FAKE_SETUP_SLEEP FAKE_GCC_STATUS FAKE_APT_STATUS FAKE_VENV_FAIL FAKE_VENV_EMPTY VSCODROID_NO_UBUNTU VSCODROID_UB_MIN_KB VSCODROID_FS_PROBE VSCODROID_SYMLINK_PROBE
}
# run <script>: a non-interactive shell with the wrapper loaded, as a task or `bash -c` has it.
run() {
  ( cd "$WS" && bash -c ". \"\$HOME/.vscodroid/command-wrapper.sh\"; __vscodroid_ub_git_started=1; $1" >"$T/out" 2>"$T/err" )
  RC=$?
}
ready_ubuntu() { # an installed fake Ubuntu, with the toolchain markers set
  mkdir -p "$H/proot/ubuntu/bin" "$H/proot/ubuntu/etc" "$H/proot/ubuntu/var/lib/vscodroid/provisioned"
  : > "$H/proot/ubuntu/bin/sh"; echo ID=ubuntu > "$H/proot/ubuntu/etc/os-release"
  echo ubuntu > "$H/proot/ubuntu/.vscodroid-ubuntu"
  : > "$H/proot/ubuntu/var/lib/vscodroid/provisioned/build"
  : > "$H/proot/ubuntu/var/lib/vscodroid/provisioned/python"
  : > "$H/proot/ubuntu/var/lib/vscodroid/provisioned/rust"
  : > "$H/proot/ubuntu/var/lib/vscodroid/provisioned/go"
}

echo "== 1. first use installs Ubuntu by itself"
newenv
run 'gcc a.c -o a'
check "gcc ran and its output arrived" "$(contains "$T/out" 'gcc-arg:a.c'; echo $?)"
check "the install ran exactly once" "$([ "$(grep -c '^setup-called ubuntu$' "$T/setup.log")" = 1 ]; echo $?)"
check "no custom command was asked for" "$(! grep -q 'ubuntu setup\|ubuntu reset\|ubuntu repair' "$T/err" "$T/out"; echo $?)"
check "the first-use notice was shown" "$(contains "$T/err" 'first use of a Linux tool'; echo $?)"

echo "== 2. exit code, arguments and quoting survive"
newenv; ready_ubuntu
FAKE_GCC_STATUS=7 run 'gcc "a b.c" '"'"'c;d'"'"' -o "x y"'
check "exit status 7 comes back unchanged" "$([ $RC -eq 7 ]; echo $?)"
check "an argument with a space stays one argument" "$(contains "$T/out" 'gcc-arg:a b.c'; echo $?)"
check "an argument with ; stays literal" "$(contains "$T/out" 'gcc-arg:c;d'; echo $?)"
FAKE_GCC_STATUS=0 run 'gcc x.c | cat; echo "pipe-status=${PIPESTATUS[0]}"; gcc y.c > "$HOME/redir.txt"; echo done'
check "pipes and redirects work" "$(contains "$T/out" 'done'; echo $?)"
check "redirected output went to the file" "$(contains "$H/redir.txt" 'gcc-arg:y.c'; echo $?)"
run 'gcc ok.c && echo chained-and; false || gcc two.c; echo end'
check "command chaining works" "$(contains "$T/out" 'chained-and'; echo $?)"

echo "== 3. an interrupted install is cleaned up and redone, only when it is the app's own"
newenv
mkdir -p "$H/proot/ubuntu/bin"; : > "$H/proot/ubuntu/bin/sh"; : > "$H/proot/ubuntu/.vscodroid-installing"
: > "$H/proot/ubuntu/stale-file"
run 'gcc a.c'
check "the half-unpacked folder was removed and Ubuntu installed again" "$([ ! -e "$H/proot/ubuntu/stale-file" ] && [ -f "$H/proot/ubuntu/.vscodroid-ubuntu" ]; echo $?)"
newenv
export VSCODROID_UBUNTU_ROOT="$T/elsewhere"
mkdir -p "$T/elsewhere/bin"; : > "$T/elsewhere/bin/sh"; : > "$T/elsewhere/.vscodroid-installing"; : > "$T/elsewhere/keep-me"
run 'gcc a.c'
check "a folder that is not <home>/proot/ubuntu is never removed" "$([ -e "$T/elsewhere/keep-me" ]; echo $?)"
unset VSCODROID_UBUNTU_ROOT

echo "== 4. real problems are reported honestly"
newenv
FAKE_SETUP_FAIL=1 run 'gcc a.c'
check "a failed install returns a failure status" "$([ $RC -ne 0 ]; echo $?)"
check "the message names the cause, not a custom command" "$(contains "$T/err" 'is the phone online'; echo $?)"
check "gcc itself was not run" "$(! contains "$T/out" 'gcc-arg'; echo $?)"
newenv
VSCODROID_UB_MIN_KB=999999999999 run 'gcc a.c'
check "not enough storage stops before the download" "$(contains "$T/err" 'not enough free storage' && [ ! -s "$T/setup.log" ]; echo $?)"

echo "== 5. two terminals at once install once"
newenv
export FAKE_SETUP_SLEEP=2
( cd "$WS" && bash -c ". \"\$HOME/.vscodroid/command-wrapper.sh\"; __vscodroid_ub_git_started=1; gcc one.c" >"$T/o1" 2>"$T/e1" ) &
( cd "$WS" && bash -c ". \"\$HOME/.vscodroid/command-wrapper.sh\"; __vscodroid_ub_git_started=1; gcc two.c" >"$T/o2" 2>"$T/e2" ) &
wait
check "the install ran once" "$([ "$(grep -c '^setup-called ubuntu$' "$T/setup.log")" = 1 ]; echo $?)"
check "both commands ran" "$(contains "$T/o1" 'gcc-arg:one.c' && contains "$T/o2" 'gcc-arg:two.c'; echo $?)"
unset FAKE_SETUP_SLEEP

echo "== 6. a half-configured package is finished before apt, nothing is removed"
newenv; ready_ubuntu
echo "iUR  somepkg" > "$T/audit"
run 'apt install -y foo'
check "dpkg --configure -a ran first" "$(grep -n 'dpkg --configure' "$T/apt.log" | head -1 | grep -q .; echo $?)"
check "apt ran afterwards" "$(contains "$T/apt.log" 'apt install -y foo'; echo $?)"
FAKE_APT_STATUS=100 run 'apt install -y foo'
check "apt's own exit status 100 comes back" "$([ $RC -eq 100 ]; echo $?)"

echo "== 7. Intel programs are told apart and routed to qemu on their own"
newenv; ready_ubuntu
printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\002\000\076\000' > "$WS/intelprog"
printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000\002\000\267\000' > "$WS/armprog"
chmod 644 "$WS/intelprog" "$WS/armprog"
run '__vscodroid_ub_elf_arch ./intelprog; __vscodroid_ub_elf_arch ./armprog'
check "e_machine 0x3e is x86_64 and 0xb7 is aarch64" "$([ "$(tr '\n' ' ' < "$T/out")" = 'x86_64 aarch64 ' ]; echo $?)"
run '__vscodroid_ub_scan; ./intelprog one two'
check "./intelprog set up the emulator by itself" "$(grep -q '^setup-called ubuntu-amd64$' "$T/setup.log"; echo $?)"
check "and ran it through qemu with its arguments" "$(contains "$T/apt.log" 'qemu-ran:-L /opt/amd64' && grep -q 'one two' "$T/apt.log"; echo $?)"
run '__vscodroid_ub_scan; ./armprog'
check "an arm program does not go to qemu" "$(! grep -q 'armprog' "$T/apt.log"; echo $?)"

echo "== 8. graphical programs are recognised; a task is not asked a question"
newenv; ready_ubuntu
printf 'import tkinter as tk\nprint(1)\n' > "$WS/win.py"
printf 'import os\nprint(1)\n' > "$WS/plain.py"
printf 'x = 1  # import pygame\n' > "$WS/comment.py"
run '__vscodroid_ub_wants_gui win.py && echo yes1; __vscodroid_ub_wants_gui -u plain.py || echo no2; __vscodroid_ub_wants_gui comment.py || echo no3; __vscodroid_ub_wants_gui -m http.server || echo no4'
check "tkinter import is detected, others are not" "$([ "$(tr '\n' ' ' < "$T/out")" = 'yes1 no2 no3 no4 ' ]; echo $?)"
run '__vscodroid_ub_gui_ensure </dev/null'
check "no terminal means a notice, not a hang or a download" "$(contains "$T/err" 'Run the program once from a terminal'; echo $?)"

echo "== 9. sudo as on a PC, and Ubuntu's own shell without a custom command"
newenv; ready_ubuntu
printf 'echo inside-shell\nexit 3\n' | ( cd "$WS" && bash -c ". \"\$HOME/.vscodroid/command-wrapper.sh\"; __vscodroid_ub_git_started=1; sudo -i" >"$T/out" 2>"$T/err" ); RC=$?
check "sudo -i opens a shell in Ubuntu" "$(contains "$T/out" 'inside-shell'; echo $?)"
run 'sudo -E apt install -y bar'
check "sudo -E apt install reaches apt" "$(contains "$T/apt.log" 'apt install -y bar'; echo $?)"
run 'sudo -u root gcc z.c'
check "sudo -u root gcc reaches gcc" "$(contains "$T/out" 'gcc-arg:z.c'; echo $?)"
run 'sudo'
check "sudo with nothing prints usage and fails" "$([ $RC -ne 0 ]; echo $?)"

echo "== 10. the app's own launcher on PATH is not mistaken for a phone tool"
newenv
mkdir -p "$T/tcbin/usr/libexec/tcbin"
printf '#!/bin/sh\nexit 99\n' > "$T/tcbin/usr/libexec/tcbin/gcc"; chmod +x "$T/tcbin/usr/libexec/tcbin/gcc"
FAKE_SETUP_FAIL=1 PATH="$T/tcbin/usr/libexec/tcbin:$PATH" run 'gcc a.c'
check "no loop: it asks Ubuntu, fails once, and stops" "$([ $RC -eq 1 ]; echo $?)"

echo "== 11. internal self check (not a command)"
newenv; ready_ubuntu
run 'VSCODROID_SELFCHECK_VERBOSE=1 __vscodroid_ub_selfcheck; echo "rc=$?"'
check "healthy system: status 0" "$(contains "$T/out" 'rc=0'; echo $?)"
echo "iUR  somepkg" > "$T/audit"
run '__vscodroid_ub_selfcheck; echo "rc=$?"'
check "an unfinished package install is reported: status 1" "$(contains "$T/out" 'rc=1'; echo $?)"
run 'ubuntu doctor'
check "'ubuntu doctor' is no longer a command of its own (no undefined-function error)" "$(! contains "$T/err" '__vscodroid_ub_doctor'; echo $?)"

echo "== 12. shared-storage notes keep the tool's error and exit status"
newenv
mkdir -p "$T/fakecp"
cat > "$T/fakecp/cp" <<'EOF'
#!/bin/bash
case "$1" in
  missing) echo "cp: cannot stat 'missing': No such file or directory" >&2; exit 1 ;;
  *) echo "cp: cannot create symbolic link '$2': Operation not permitted" >&2; exit 1 ;;
esac
EOF
chmod +x "$T/fakecp/cp"
export PATH="$T/fakecp:$BASE_PATH"
VSCODROID_FS_PROBE=fail run 'cp a b; echo "rc=$?"'
check "the original error text is kept" "$(contains "$T/err" "cp: cannot create symbolic link 'b': Operation not permitted"; echo $?)"
check "one extra line names the real limit" "$(contains "$T/err" 'does not support symbolic links'; echo $?)"
check "exit status 1 is kept" "$(contains "$T/out" 'rc=1'; echo $?)"
VSCODROID_FS_PROBE=ok run 'cp a b; echo "rc=$?"'
check "no note when the folder can do the operation" "$(! contains "$T/err" 'does not support'; echo $?)"
VSCODROID_FS_PROBE=fail run 'cp missing b; echo "rc=$?"'
check "a missing file is not blamed on Android" "$(! contains "$T/err" 'does not support'; echo $?)"
VSCODROID_FS_PROBE=fail VSCODROID_NO_FS_NOTES=1 run 'cp a b; echo "rc=$?"'
check "the note can be switched off" "$(! contains "$T/err" 'does not support'; echo $?)"
VSCODROID_FS_PROBE=fail run 'cp a b 2>"$HOME/e.txt" | cat; echo "rc=${PIPESTATUS[0]}"'
check "a redirect of stderr still gets the error" "$(contains "$H/e.txt" 'Operation not permitted'; echo $?)"
check "no stray probe files are left behind" "$([ -z "$(ls -A "$WS" | grep vscodroid-op)" ]; echo $?)"

echo "== 14. tools installed in Ubuntu run by their own name"
newenv; ready_ubuntu
FAKE_JAVAC_STATUS=4 run 'javac "My File.java" -d out; echo "rc=$?"'
check "javac, which is not a routed name, ran in Ubuntu with its arguments" "$(contains "$T/out" 'javac-arg:My File.java' && contains "$T/out" 'javac-arg:-d'; echo $?)"
check "in the same working folder" "$(contains "$T/out" "cwd:$WS"; echo $?)"
check "and its exit status 4 came back" "$(contains "$T/out" 'rc=4'; echo $?)"
run 'javac a.java | cat; javac b.java > "$HOME/j.txt"; echo done'
check "pipes and redirects work for it" "$(contains "$T/out" 'javac-arg:a.java' && contains "$H/j.txt" 'javac-arg:b.java'; echo $?)"
run 'nosuchtool x; echo "rc=$?"'
check "a name that exists nowhere gives the usual message and 127" "$(contains "$T/err" 'nosuchtool: command not found' && contains "$T/out" 'rc=127'; echo $?)"
run 'VSCODROID_NO_UBUNTU=1 javac x; echo "rc=$?"'
check "VSCODROID_NO_UBUNTU keeps it on the phone (127)" "$(contains "$T/out" 'rc=127'; echo $?)"
run 'command -v javac || echo phone-has-none'
check "command -v reports only what the phone has" "$(contains "$T/out" 'phone-has-none'; echo $?)"
newenv
run 'javac x; echo "rc=$?"'
check "with no Ubuntu yet a mistyped or unknown name downloads nothing" "$([ ! -s "$T/setup.log" ] && contains "$T/out" 'rc=127'; echo $?)"

echo "== 13. Ctrl+C reaches only the running command (real pseudo-terminal, stand-in proot)"
newenv; ready_ubuntu
cat > "$T/ctrlc.py" <<'PY'
import os, pty, re, select, sys, time

ws = sys.argv[1]
proj = sys.argv[2]
home = os.environ["HOME"]

def procs(needle):
    """Pids of python/sleep/helper programs whose command line contains needle (from /proc)."""
    found = []
    for d in os.listdir("/proc"):
        if not d.isdigit() or int(d) == os.getpid():
            continue
        try:
            with open("/proc/%s/cmdline" % d, "rb") as f:
                raw = f.read()
            argv0 = os.path.basename(raw.split(b"\0")[0])
            if needle in raw.replace(b"\0", b" ") and (argv0.startswith(b"python") or argv0 == b"sleep"):
                found.append(int(d))
        except OSError:
            pass
    return found

class Term:
    def __init__(self, cwd=None):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(cwd or ws)
            os.execvp("bash", ["bash", "--noprofile", "--norc", "-i"])
        self.buf = b""
        self.send('. "%s/.vscodroid/command-wrapper.sh"; __vscodroid_ub_git_started=1\n' % home)
        self.send("PS1='$ '\n")
    def send(self, text):
        os.write(self.fd, text.encode() if isinstance(text, str) else text)
    def read_until(self, pattern, timeout=20):
        end = time.time() + timeout
        rx = re.compile(pattern.encode())
        while time.time() < end:
            if rx.search(self.buf):
                return True
            r, _, _ = select.select([self.fd], [], [], 0.2)
            if r:
                try:
                    chunk = os.read(self.fd, 4096)
                except OSError:
                    return False
                if not chunk:
                    return False
                self.buf += chunk
        return bool(rx.search(self.buf))
    def close(self):
        try:
            self.send("exit\n"); time.sleep(0.2); os.close(self.fd)
        except OSError:
            pass

results = []
def check(name, cond):
    results.append((name, bool(cond)))

# A second, unrelated terminal with its own long command.
other = Term()
other.send("python3 -c \"import time; print('OTHER-'+'RUNNING', flush=True); time.sleep(63)\"\n")
check("the other terminal's command started", other.read_until("OTHER-RUNNING"))

a = Term()
# 1. a foreground command
a.send("python3 -c \"import time; print('RUN'+'NING', flush=True); time.sleep(60)\"\n")
check("the foreground command started", a.read_until("RUNNING"))
a.send(b"\x03")
time.sleep(1.0)
a.send("echo MARK-$?\n")
check("the shell is usable after Ctrl+C", a.read_until(r"MARK-\d+"))
m = re.search(rb"MARK-(\d+)", a.buf)
check("the status says it was interrupted (130)", m and m.group(1) == b"130")
check("the interrupted command is gone", not procs(b"time.sleep(60)"))

# 2. a command that starts a child, and an unrelated background job
a.buf = b""
a.send("sleep 62 &\n")
a.send("python3 -c \"import subprocess, time; subprocess.Popen(['sleep','61']); print('CHILD-'+'RUNNING', flush=True); time.sleep(61)\"\n")
check("the command with a child started", a.read_until("CHILD-RUNNING"))
a.send(b"\x03")
time.sleep(1.0)
a.send("echo MARK2-$?\n")
check("the shell is usable again", a.read_until(r"MARK2-\d+"))
check("the child process is gone too", not procs(b"sleep 61"))
check("an unrelated background job of this shell survives", bool(procs(b"sleep 62")))

# 3. Ctrl+C again and again at a prompt, and after the command has already ended
a.buf = b""
for _ in range(3):
    a.send(b"\x03"); time.sleep(0.2)
a.send("true; echo MARK3-$?\n")
check("repeated Ctrl+C at a prompt does no harm", a.read_until(r"MARK3-0"))

# 3b. a tool that only Ubuntu has, found by the not-found handler
a.buf = b""
a.send("slowtool\n")
check("a tool only Ubuntu has started by its own name", a.read_until("SLOW-RUNNING"))
a.send(b"\x03")
time.sleep(1.0)
a.send("echo MARK4-$?\n")
check("the shell is usable after Ctrl+C on it", a.read_until(r"MARK4-\d+"))
m = re.search(rb"MARK4-(\d+)", a.buf)
check("and the status says interrupted (130)", m and m.group(1) == b"130")
check("that tool is gone too", not procs(b"sleep 64"))

# 3c. a brand-new interactive terminal opened in a project folder knows its environment
c = Term(proj)
c.send(".venv/bin/python -c \"print('VENV-'+'OK', flush=True)\"\n")
check("a new interactive terminal in the project: .venv/bin/python runs at once", c.read_until("VENV-OK"))
c.send("source .venv/bin/activate; python -c \"import sys; print('PFX-'+sys.prefix)\"\n")
check("and after source .venv/bin/activate python reports the environment", c.read_until(r"PFX-.*\.venvs/venv-"))
c.close()

# 4. the other terminal was never touched
check("another terminal's command was not stopped", bool(procs(b"time.sleep(63)")))

for pid in procs(b"sleep 62") + procs(b"time.sleep(63)"):
    try: os.kill(pid, 9)
    except OSError: pass
a.close(); other.close()

bad = 0
for name, ok in results:
    print(("  ok    " if ok else "  FAIL  ") + name)
    bad += 0 if ok else 1
sys.exit(1 if bad else 0)
PY
mkdir -p "$WS/proj"; run 'cd proj; python3 -m venv .venv >/dev/null 2>&1'
timeout 120 python3 "$T/ctrlc.py" "$WS" "$WS/proj" > "$T/ctrlc.out" 2>&1; CRC=$?
cat "$T/ctrlc.out"
pass=$((pass + $(grep -c '^  ok' "$T/ctrlc.out")))
fail=$((fail + $(grep -c '^  FAIL' "$T/ctrlc.out")))
[ $CRC -ne 0 ] && [ "$(grep -c '^  FAIL' "$T/ctrlc.out")" = 0 ] && bad "the Ctrl+C session did not complete" "exit status $CRC"


echo "== 15. Python venv: real python3 -m venv and real pip behind the stand-in"
mkdir -p "$T/wheels"
python3 - "$T/wheels" <<'PY'
import base64, hashlib, os, sys, zipfile
d, name, ver = sys.argv[1], "vscodtest", "1.0"
files = {name + ".py": 'VALUE = "installed-ok"\n',
         "%s-%s.dist-info/METADATA" % (name, ver): "Metadata-Version: 2.1\nName: %s\nVersion: %s\n" % (name, ver),
         "%s-%s.dist-info/WHEEL" % (name, ver): "Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n"}
h = lambda b: "sha256=" + base64.urlsafe_b64encode(hashlib.sha256(b).digest()).rstrip(b"=").decode()
rec = []
with zipfile.ZipFile(os.path.join(d, "%s-%s-py3-none-any.whl" % (name, ver)), "w") as z:
    for k, v in files.items():
        b = v.encode(); z.writestr(k, b); rec.append("%s,%s,%d" % (k, h(b), len(b)))
    rec.append("%s-%s.dist-info/RECORD,," % (name, ver))
    z.writestr("%s-%s.dist-info/RECORD" % (name, ver), "\n".join(rec) + "\n")
PY

newenv; ready_ubuntu
run 'python3 -m venv /proc/ubuntu-root/vprobe; echo "rc=$?"; /proc/ubuntu-root/vprobe/bin/python --version; /proc/ubuntu-root/vprobe/bin/python -m pip --version | cut -d" " -f1,2; [ -e /proc/ubuntu-root/vprobe ] && echo phone-sees-it || echo phone-does-not-see-it'
check "an Ubuntu-only path: exit status 0" "$(contains "$T/out" 'rc=0'; echo $?)"
check "the environment really exists inside Ubuntu (python and pyvenv.cfg)" "$([ -x "$GUEST_HOME/vprobe/bin/python" ] && [ -f "$GUEST_HOME/vprobe/pyvenv.cfg" ]; echo $?)"
check "its python runs from the terminal by that path" "$(grep -q '^Python 3\.' "$T/out"; echo $?)"
check "and its pip runs" "$(contains "$T/out" 'pip 2'; echo $?)"
check "no fake file is claimed on the phone side" "$(contains "$T/out" 'phone-does-not-see-it'; echo $?)"

newenv; ready_ubuntu; mkdir -p "$WS/proj"
run 'cd proj; python3 -m venv .venv; echo "rc=$?"; ls .venv/bin | tr "\n" " "; echo; .venv/bin/python --version; .venv/bin/python -m pip --version; ./.venv/bin/python -c "import sys; print(\"prefix=\" + sys.prefix)"'
check "a project in shared storage: exit status 0" "$(contains "$T/out" 'rc=0'; echo $?)"
check "bin holds activate, python, python3, pip, pip3" "$(grep -q 'activate pip pip3 python python3' "$T/out"; echo $?)"
check "the real environment is inside Ubuntu" "$(ls "$GUEST_HOME"/.venvs/venv-*/bin/python >/dev/null 2>&1; echo $?)"
check ".venv/bin/python --version works by that path" "$(grep -q '^Python 3\.' "$T/out"; echo $?)"
check ".venv/bin/python -m pip --version names the environment's own pip" "$(grep -q 'pip .*/\.venvs/venv-' "$T/out"; echo $?)"
check "sys.prefix is the environment, not /usr" "$(grep -q 'prefix=.*/\.venvs/venv-' "$T/out"; echo $?)"
check "the files in the project are honest text, not executables" "$([ ! -x "$WS/proj/.venv/bin/python" ] && head -2 "$WS/proj/.venv/bin/python" | grep -q vscodroid-venv; echo $?)"

run 'cd proj; source .venv/bin/activate; python -c "import sys; print(\"prefix=\" + sys.prefix); print(\"exe=\" + sys.executable)"; echo "VV=${VSCODROID_VENV##*/}"; echo "PS1=$PS1"; pip install --no-index --find-links "'"$T"'/wheels" vscodtest > pip.log 2>&1; echo "pip-rc=$?"; python -c "import vscodtest; print(vscodtest.VALUE)"; pip list 2>/dev/null | grep -c vscodtest; deactivate; echo "after=${VSCODROID_VENV-unset}"; type deactivate >/dev/null 2>&1 && echo deactivate-still-there || echo deactivate-gone; python3 -c "import vscodtest" 2>&1 | tail -1; /usr/bin/python3 -c "import vscodtest" 2>&1 | tail -1'
check "activate: python reports the environment's prefix" "$(grep -q 'prefix=.*/\.venvs/venv-' "$T/out"; echo $?)"
check "activate: sys.executable is inside the environment" "$(grep -q 'exe=.*/\.venvs/venv-.*/bin/python' "$T/out"; echo $?)"
check "activate: the prompt and VSCODROID_VENV are set" "$(contains "$T/out" 'PS1=(.venv) ' && grep -q '^VV=venv-' "$T/out"; echo $?)"
check "pip install into the environment succeeds" "$(contains "$T/out" 'pip-rc=0'; echo $?)"
check "the installed package imports and runs" "$(contains "$T/out" 'installed-ok'; echo $?)"
check "pip sees it, and it landed inside the environment, not in system Python" "$(ls "$GUEST_HOME"/.venvs/venv-*/lib/python3*/site-packages/vscodtest.py >/dev/null 2>&1 && ! /usr/bin/python3 -c 'import vscodtest' 2>/dev/null; echo $?)"
check "deactivate removes VSCODROID_VENV and itself" "$(contains "$T/out" 'after=unset' && contains "$T/out" 'deactivate-gone'; echo $?)"
check "after deactivate the package is not importable (isolation)" "$(grep -c 'ModuleNotFoundError' "$T/out" | grep -q '^2$'; echo $?)"

echo "-- venv failures are reported, never turned into success"
newenv; ready_ubuntu; mkdir -p "$WS/f1"
FAKE_VENV_FAIL=1 run 'cd f1; python3 -m venv .venv; echo "rc=$?"; [ -e .venv ] && echo made || echo not-made'
check "python3 fails: its status 3 comes back, nothing is claimed" "$(contains "$T/out" 'rc=3' && contains "$T/out" 'not-made' && contains "$T/err" 'was not created'; echo $?)"
FAKE_VENV_EMPTY=1 run 'cd f1; python3 -m venv .venv2; echo "rc=$?"; [ -e .venv2 ] && echo made || echo not-made'
check "python3 says success but made nothing: status 1 and a message" "$(contains "$T/out" 'rc=1' && contains "$T/out" 'not-made' && contains "$T/err" 'is missing in Ubuntu'; echo $?)"
run 'cd f1; : > afile; python3 -m venv afile/.venv; echo "rc=$?"'
check "the project folder cannot be written: status 1 and a message" "$(contains "$T/out" 'rc=1' && contains "$T/err" 'could not create'; echo $?)"

echo "-- options and several folders pass through"
run 'cd f1; python3 -m venv --without-pip .np; echo "rc1=$?"; python3 -m venv --prompt myprompt .pp; echo "rc2=$?"; python3 -m venv .m1 .m2; echo "rc3=$?"; python3 -m venv -h | head -1; echo "rc4=${PIPESTATUS[0]}"; python3 -m venv >/dev/null 2>&1; echo "rc5=$?"'
check "--without-pip: made, and has no pip" "$(contains "$T/out" 'rc1=0' && [ ! -e "$(ls -d "$GUEST_HOME"/.venvs/np-*/bin/pip 2>/dev/null | head -1)" ]; echo $?)"
check "--prompt NAME reaches python" "$(grep -q "prompt = .myprompt" "$GUEST_HOME"/.venvs/pp-*/pyvenv.cfg; echo $?)"
check "two folders in one command are both made" "$(contains "$T/out" 'rc3=0' && [ -f "$WS/f1/.m1/bin/activate" ] && [ -f "$WS/f1/.m2/bin/activate" ]; echo $?)"
check "-h prints python's own usage, status 0" "$(contains "$T/out" 'usage: venv' && contains "$T/out" 'rc4=0'; echo $?)"
check "no folder given: python's own usage error, status 2" "$(contains "$T/out" 'rc5=2'; echo $?)"

echo "-- a project in private storage gets an ordinary environment"
newenv; ready_ubuntu; mkdir -p "$H/priv"
run 'cd "$HOME/priv"; python3 -m venv .venv; echo "rc=$?"; [ -L .venv/bin/python ] && echo real-symlink; ./.venv/bin/python -c "import sys; print(\"prefix=\" + sys.prefix)"; source .venv/bin/activate; python -c "import sys; print(\"active=\" + sys.prefix)"; deactivate'
check "private storage: a real venv with symbolic links" "$(contains "$T/out" 'rc=0' && contains "$T/out" 'real-symlink'; echo $?)"
check "its python runs by path and reports the environment" "$(grep -q "prefix=$H/priv/.venv" "$T/out"; echo $?)"
check "after its own activate script, python uses it" "$(grep -q "active=$H/priv/.venv" "$T/out"; echo $?)"

echo "-- a fresh shell sees the environment of the folder it starts in"
newenv; ready_ubuntu; mkdir -p "$WS/proj"
run 'cd proj; python3 -m venv .venv >/dev/null 2>&1'
( cd "$WS/proj" && bash -c '. "$HOME/.vscodroid/command-wrapper.sh"; __vscodroid_ub_git_started=1; .venv/bin/python --version; ./.venv/bin/python -c "print(1+1)"' >"$T/out" 2>"$T/err" ); RC=$?
check "a new shell started in the project: .venv/bin/python works at once" "$(grep -q '^Python 3\.' "$T/out" && grep -q '^2$' "$T/out"; echo $?)"

echo "-- before Ubuntu is installed, the phone's own Python makes the environment (private storage)"
newenv; mkdir -p "$WS/np"
export VSCODROID_SYMLINK_PROBE=fail   # the workspace folder cannot hold links, as on a phone
run 'cd np; python3 -m venv .venv; echo "rc=$?"; ls .venv/bin | tr "\n" " "; echo; .venv/bin/python --version; ./.venv/bin/python -c "import sys; print(\"prefix=\" + sys.prefix)"; source .venv/bin/activate; python -c "import sys; print(\"active=\" + sys.prefix)"; python -m pip install --no-index --find-links "'"$T"'/wheels" vscodtest >/dev/null 2>&1; echo "pip-rc=$?"; python -c "import vscodtest; print(vscodtest.VALUE)"; deactivate; python -c "import vscodtest" 2>&1 | tail -1'
check "phone Python: status 0, bin holds activate, python, python3, pip, pip3" "$(contains "$T/out" 'rc=0' && grep -q 'activate pip pip3 python python3' "$T/out"; echo $?)"
check "the environment is a real one in the app's private folder" "$(ls "$H"/venvs/venv-*/bin/python >/dev/null 2>&1 && [ -L "$(ls "$H"/venvs/venv-*/bin/python | head -1)" ]; echo $?)"
check "np/.venv/bin/python --version works by that path" "$(grep -q '^Python 3\.' "$T/out"; echo $?)"
check "by that path sys.prefix is the environment" "$(grep -q "prefix=$H/venvs/venv-" "$T/out"; echo $?)"
check "after activate python uses it, and pip installs into it" "$(grep -q "active=$H/venvs/venv-" "$T/out" && contains "$T/out" 'pip-rc=0' && contains "$T/out" 'installed-ok'; echo $?)"
check "after deactivate the package is gone from the picture (isolation)" "$(contains "$T/out" 'ModuleNotFoundError'; echo $?)"
newenv; export VSCODROID_SYMLINK_PROBE=fail; mkdir -p "$WS/np2"
run 'cd np2; : > afile; python3 -m venv afile/.venv; echo "rc=$?"'
check "phone Python: an unwritable project folder gives status 1 and a message, not success" "$(contains "$T/out" 'rc=1' && contains "$T/err" 'could not create'; echo $?)"
newenv; export VSCODROID_SYMLINK_PROBE=fail; mkdir -p "$WS/np3"; : > "$H/venvs"
run 'cd np3; python3 -m venv .venv; echo "rc=$?"'
check "phone Python: no place for the environment gives status 1, not success" "$(contains "$T/out" 'rc=1' && contains "$T/err" 'cannot create'; echo $?)"

echo "== 16. environment variables reach Ubuntu (as on a PC), phone-only ones do not"
newenv; ready_ubuntu
run 'export FOO=bar KEEP="a b"; python3 -c "import os; print(os.environ.get(\"FOO\")); print(os.environ.get(\"KEEP\"))"; CC=clang python3 -c "import os; print(os.environ.get(\"CC\"))"; export LD_LIBRARY_PATH=/x PYTHONHOME=/data/data/app/files/usr JAVA_HOME=/data/user/0/app/files/jdk; python3 -c "import os; print(os.environ.get(\"LD_LIBRARY_PATH\"), os.environ.get(\"PYTHONHOME\"), os.environ.get(\"JAVA_HOME\"))"; export JAVA_HOME=/usr/lib/jvm/java-21; python3 -c "import os; print(os.environ.get(\"JAVA_HOME\"))"; python3 -c "import os; print(os.environ[\"HOME\"] == \"'"$GUEST_HOME"'\")"'
check "an exported variable reaches the command (FOO, and one with a space)" "$(grep -q '^bar$' "$T/out" && grep -q '^a b$' "$T/out"; echo $?)"
check "a one-command assignment reaches it (CC=clang python3)" "$(grep -q '^clang$' "$T/out"; echo $?)"
check "phone-only variables are withheld (LD_LIBRARY_PATH, PYTHONHOME, a phone JAVA_HOME)" "$(grep -q '^None None None$' "$T/out"; echo $?)"
check "an Ubuntu-side JAVA_HOME is passed" "$(grep -q '^/usr/lib/jvm/java-21$' "$T/out"; echo $?)"
check "HOME inside Ubuntu is still Ubuntu's" "$(grep -q '^True$' "$T/out"; echo $?)"

echo "== 17. command audit: arguments, status, streams, folder, variables, pipes, stdin"
newenv; ready_ubuntu; export FAKE_GUEST="$T/guest2"
: > "$T/audit-table.txt"
for t in python python3 pip pip3 gcc g++ cc c++ make cmake rustc apt apt-get dpkg; do
  AUDIT_STATUS=5 run "mkdir -p 'sub dir' && cd 'sub dir' && AUDIT_VAR=v1 $t one 'two words' '\$x;y' >o.txt 2>e.txt; echo rc=\$?; cat o.txt; cat e.txt >&2"
  a1=1; a2=1; a3=1; a4=1; a5=1
  contains "$T/out" 'rc=5' && a1=0
  contains "$T/out" "$t-args: [one] [two words] [\$x;y]" && a2=0
  contains "$T/out" "$t-cwd:$WS/sub dir" && a3=0
  contains "$T/out" "$t-env:v1" && a4=0
  contains "$T/err" "$t-err" && ! contains "$T/out" "$t-err" && a5=0
  check "$t: arguments, exit status 5, folder, variable and stream separation" "$((a1 + a2 + a3 + a4 + a5))" "args=$a2 status=$a1 cwd=$a3 env=$a4 streams=$a5"
  printf '%-9s status:%s args:%s cwd:%s env:%s streams:%s\n' "$t" "$a1" "$a2" "$a3" "$a4" "$a5" >> "$T/audit-table.txt"
done
echo "   (0 = as on Ubuntu, 1 = differs)"; cat "$T/audit-table.txt"
AUDIT_STDIN=1 run 'echo hello | gcc - ; echo "rc=$?"; gcc x | cat; gcc y > "$HOME/redir.txt"; echo done'
check "gcc: stdin, a pipe and a redirect work" "$(contains "$T/out" 'gcc-stdin:hello' && contains "$T/out" 'gcc-args: [x]' && contains "$H/redir.txt" 'gcc-args: [y]'; echo $?)"
unset AUDIT_STATUS
echo "-- how each name resolves in a fresh shell (the phone's PATH here has none of them)"
run 'for n in python python3 pip pip3 gcc g++ cc c++ node npm apt apt-get dpkg make cmake rustc ls cat find grep sed; do printf "%s: " $n; type -t $n || echo none; done'
cp "$T/out" "$T/resolve-table.txt"
sed 's/^/   /' "$T/resolve-table.txt"
check "python, python3, pip, pip3, gcc, g++, cc, c++, apt, apt-get, dpkg, make, cmake, rustc and npm are shell functions" "$(for n in python python3 pip pip3 gcc g++ cc c++ apt apt-get dpkg make cmake rustc npm; do grep -q "^$n: function$" "$T/resolve-table.txt" || echo missing; done | grep -q missing; [ $? -ne 0 ]; echo $?)"
check "node and the plain utilities (ls cat find grep sed) are not intercepted" "$(for n in node ls cat find grep sed; do grep -q "^$n: function$" "$T/resolve-table.txt" && echo wrapped; done | grep -q wrapped; [ $? -ne 0 ]; echo $?)"

echo "== 18. C and C++ builds with the real compilers; Node.js and npm for real"
newenv; ready_ubuntu
mkdir -p "$UB_ROOT/proot-x"; mkdir -p "${UB_ROOT%/*}/ubuntu-amd64/lib64"; : > "${UB_ROOT%/*}/ubuntu-amd64/lib64/ld-linux-x86-64.so.2"
: > "$UB_ROOT/var/lib/vscodroid/provisioned/qemu"
export FAKE_GUEST="$T/guestreal"
printf '#include <stdio.h>\nint main(void){printf("hello-c %%d\\n", 6*7);return 0;}\n' > "$WS/hello.c"
printf '#include <iostream>\nint main(){std::cout << 123 << std::endl;return 0;}\n' > "$WS/hello.cpp"
printf 'int main(void){return 7;}\n' > "$WS/ret7.c"
printf 'int main(void){ this is not C }\n' > "$WS/bad.c"
run 'gcc hello.c -o hello; echo "gcc-rc=$?"; ./hello; echo "run-rc=$?"; g++ hello.cpp -o hellopp; echo "gpp-rc=$?"; ./hellopp; gcc ret7.c -o ret7; ./ret7; echo "ret7-rc=$?"; gcc bad.c -o bad 2>"$HOME/bad.err"; echo "bad-rc=$?"; [ -e bad ] && echo bad-built || echo bad-not-built'
check "gcc compiles; ./hello runs and prints" "$(contains "$T/out" 'gcc-rc=0' && contains "$T/out" 'hello-c 42' && contains "$T/out" 'run-rc=0'; echo $?)"
check "g++ compiles; ./hellopp prints 123" "$(contains "$T/out" 'gpp-rc=0' && grep -q '^123$' "$T/out"; echo $?)"
check "the program's own exit status 7 comes back" "$(contains "$T/out" 'ret7-rc=7'; echo $?)"
check "a compile error gives status 1 and no program" "$(contains "$T/out" 'bad-rc=1' && contains "$T/out" 'bad-not-built' && contains "$H/bad.err" 'error'; echo $?)"
check "the private copy is executable (mode 755)" "$([ "$(stat -c %a "$UB_ROOT"/tmp/vsc-run/*/hello | head -1)" = 755 ]; echo $?)"
run 'cd "$HOME"; mkdir -p "dir with space"; cd "dir with space"; printf "int main(void){return 3;}\n" > "my file.c"; gcc "my file.c" -o "my prog"; echo "space-rc=$?"; [ -f "my prog" ] && echo built-with-space'
check "a source file and output name with spaces compile" "$(contains "$T/out" 'space-rc=0' && contains "$T/out" 'built-with-space'; echo $?)"

unset FAKE_GUEST; export FAKE_GUEST="$T/guest"
mkdir -p "$T/npm/localdep" "$WS/app"
python3 - "$T/npm" "$WS/app" <<'PY'
import json, sys
d, a = sys.argv[1], sys.argv[2]
json.dump({"name": "localdep", "version": "1.0.0", "main": "index.js"}, open(d + "/localdep/package.json", "w"))
open(d + "/localdep/index.js", "w").write('module.exports = "dep-ok";\n')
json.dump({"name": "app", "version": "1.0.0",
           "scripts": {"hello": "node -e \"console.log(require('localdep'))\"", "fail": "node -e \"process.exit(4)\""},
           "dependencies": {"localdep": "file:" + d + "/localdep"}}, open(a + "/package.json", "w"))
PY
run 'node --version; npm --version; cd app; npm install --no-audit --no-fund > npm.log 2>&1; echo "install-rc=$?"; npm run hello; echo "run-rc=$?"; node -e "console.log(require(\"localdep\"))"; npm run fail >/dev/null 2>&1; echo "fail-rc=$?"'
check "node --version and npm --version" "$(grep -q '^v[0-9]' "$T/out" && grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' "$T/out"; echo $?)"
check "npm install of a dependency succeeds" "$(contains "$T/out" 'install-rc=0' && [ -e "$WS/app/node_modules/localdep" ]; echo $?)"
check "npm run runs a script and the dependency imports" "$(contains "$T/out" 'dep-ok' && contains "$T/out" 'run-rc=0'; echo $?)"
check "a failing npm script's status reaches the shell" "$(contains "$T/out" 'fail-rc=1' || contains "$T/out" 'fail-rc=4'; echo $?)"

echo "== 19. project files in shared storage, from a fresh shell each time"
newenv; ready_ubuntu
run 'echo "from-phone" > "$HOME/../ws-note.txt" 2>/dev/null; echo "written-by-phone" > note.txt; python3 -c "
d = open(\"note.txt\").read().strip()
open(\"made-in-ubuntu.txt\", \"w\").write(d + \"+ubuntu\\n\")"; cat made-in-ubuntu.txt; rm -f note.txt made-in-ubuntu.txt; [ ! -e note.txt ] && echo deleted'
check "a file written by the phone is read inside Ubuntu, and what Ubuntu writes is seen by the phone" "$(contains "$T/out" 'written-by-phone+ubuntu' && contains "$T/out" 'deleted'; echo $?)"
run 'echo persisted > keep.txt'
run 'cat keep.txt'
check "a file is still there in a brand-new shell" "$(contains "$T/out" 'persisted'; echo $?)"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
