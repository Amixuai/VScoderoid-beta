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
# Stand-in for proot: skips its options, then runs the command on the host with a
# fake "guest" folder first on PATH.
cwd=.
while [ $# -gt 0 ] && [ "$1" != /usr/bin/env ]; do
  [ "$1" = -w ] && { cwd=$2; shift; }
  shift
done
shift 2   # /usr/bin/env -i
while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do shift; done
cd "$cwd" 2>/dev/null
printf '%s\n' "$*" >> "${PROOT_LOG:-/dev/null}"
exec env PATH="$FAKE_GUEST:$PATH" "$@"
EOF
cat > "$T/bin/loader" <<'EOF'
#!/bin/sh
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
         tail ln id pwd ps pgrep xargs expr test timeout; do
  p=$(command -v "$c" 2>/dev/null) && [ -x "$p" ] && ln -sf "$p" "$T/hostbin/$c"
done
BASE_PATH="$T/hostbin"

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
  export FAKE_GUEST="$T/guest" SETUP_LOG="$T/setup.log" APT_LOG="$T/apt.log" PROOT_LOG="$T/proot.log" AUDIT="$T/audit"
  export VSCODROID_SHARED_PREFIXES="$T/shared" VSCODROID_NO_PREVIEW=1 TMPDIR="$T"
  unset FAKE_SETUP_FAIL FAKE_SETUP_SLEEP FAKE_GCC_STATUS FAKE_APT_STATUS VSCODROID_NO_UBUNTU VSCODROID_UB_MIN_KB VSCODROID_FS_PROBE
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

echo "== 13. Ctrl+C reaches only the running command (real pseudo-terminal, stand-in proot)"
newenv; ready_ubuntu
cat > "$T/ctrlc.py" <<'PY'
import os, pty, re, select, sys, time

ws = sys.argv[1]
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
    def __init__(self):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(ws)
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
timeout 120 python3 "$T/ctrlc.py" "$WS" > "$T/ctrlc.out" 2>&1; CRC=$?
cat "$T/ctrlc.out"
pass=$((pass + $(grep -c '^  ok' "$T/ctrlc.out")))
fail=$((fail + $(grep -c '^  FAIL' "$T/ctrlc.out")))
[ $CRC -ne 0 ] && [ "$(grep -c '^  FAIL' "$T/ctrlc.out")" = 0 ] && bad "the Ctrl+C session did not complete" "exit status $CRC"

echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]
