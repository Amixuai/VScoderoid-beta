#!/usr/bin/env bash
# VSCodroid proot prototype: can this phone compile and run C inside a hidden
# Alpine Linux, started through proot?
#
# Run it in the app's terminal:   bash ~/.vscodroid/proot-test.sh
#
# What it does, in order:
#   1. checks that the app shipped proot and its loader
#   2. downloads Alpine Linux's minimal root filesystem once (about 4 MB),
#      checks its SHA-256, and unpacks it into the app's PRIVATE storage
#   3. starts proot, installs gcc inside Alpine, compiles hello.c and runs it
#
# It prints PASS or FAIL and, on FAIL, the evidence needed to fix it. Nothing
# here touches your projects. This copy is rewritten at every launch.

set -u

ROOT="$HOME/proot/alpine"
PROOT="${VSCODROID_PROOT:-}"
LOG="${TMPDIR:-/tmp}/vscodroid-proot-test.log"

say() { printf '%s\n' "$*"; }
fail() { say ""; say "FAIL: $*"; exit 1; }

say "VSCodroid proot prototype"
say "Android $(getprop ro.build.version.release 2>/dev/null) / $(uname -m) / $(getprop ro.product.model 2>/dev/null)"

# ---- 1. the engine is there -------------------------------------------------
[ -n "$PROOT" ] && [ -x "$PROOT" ] ||
  fail "proot is not in this build (VSCODROID_PROOT='$PROOT'). Rebuild the app after running scripts/download-termux-tools.sh, then restart it."
[ -n "${PROOT_LOADER:-}" ] && [ -x "$PROOT_LOADER" ] ||
  fail "the proot loader is missing (PROOT_LOADER='${PROOT_LOADER:-}')."
export PROOT_TMP_DIR="${PROOT_TMP_DIR:-$HOME/.vscodroid/proot-tmp}"
mkdir -p "$PROOT_TMP_DIR"
say "[1/3] proot engine found."

# ---- 2. Alpine, once ----------------------------------------------------------
if [ ! -e "$ROOT/bin/busybox" ]; then
  say "[2/3] Downloading Alpine Linux (one time)..."
  python3 - "$ROOT" <<'PY' || fail "could not download or unpack Alpine (see the message above)."
import hashlib, io, os, re, sys, tarfile, urllib.request

root = sys.argv[1]
base = "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/"

def get(url):
    with urllib.request.urlopen(url, timeout=120) as r:
        return r.read()

index = get(base + "latest-releases.yaml").decode()
m = re.search(r"file:\s*(alpine-minirootfs-[0-9.]+-aarch64\.tar\.gz)", index)
if not m:
    sys.exit("no mini root filesystem in Alpine's release list")
name = m.group(1)

want = None
try:
    side = get(base + name + ".sha256").decode()
    h = re.match(r"\s*([0-9a-f]{64})", side)
    want = h.group(1) if h else None
except Exception:
    pass
if want is None:
    entry = index[m.end():].split("\n-\n")[0]
    h = re.search(r"sha256:\s*([0-9a-f]{64})", entry)
    want = h.group(1) if h else None
if want is None:
    sys.exit("could not find the SHA-256 for " + name + "; refusing to unpack an unchecked download")

data = get(base + name)
got = hashlib.sha256(data).hexdigest()
if got != want:
    sys.exit("checksum mismatch for " + name + "; refusing to unpack it")

os.makedirs(root, exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as t:
    try:
        t.extractall(root, filter="tar")
    except TypeError:
        t.extractall(root)
print("  unpacked " + name)
PY
else
  say "[2/3] Alpine is already unpacked."
fi

mkdir -p "$ROOT/etc" "$ROOT/tmp" "$ROOT/root/hello"
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$ROOT/etc/resolv.conf"
# Plain http for the package index: apk checks every package's own signature,
# so this saves needing a certificate store inside the minimal system.
sed -i 's#https://#http://#' "$ROOT/etc/apk/repositories" 2>/dev/null

cat > "$ROOT/root/hello/hello.c" <<'EOF'
#include <stdio.h>
int main(void) {
    printf("Hello from C, built inside Alpine on Android!\n");
    return 0;
}
EOF

# ---- 3. compile and run inside proot -------------------------------------------
run_proot() {
  "$PROOT" --link2symlink -0 -r "$ROOT" -b /dev -b /proc -b /sys \
    -w /root --kill-on-exit \
    /usr/bin/env -i HOME=/root TERM=xterm \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/sh -c "$1"
}

INNER='apk add --no-cache gcc musl-dev && cd /root/hello && gcc hello.c -o hello && ./hello'

try() {
  say "[3/3] Compiling inside proot ($1)..."
  shift
  ( "$@" ) > "$LOG" 2>&1
  local st=$?
  if [ $st -eq 0 ] && grep -q "Hello from C" "$LOG"; then return 0; fi
  return 1
}

if try "default mode" run_proot "$INNER"; then
  MODE="default"
elif PROOT_NO_SECCOMP=1 try "without seccomp acceleration, for phones that need it" run_proot "$INNER"; then
  MODE="PROOT_NO_SECCOMP=1"
else
  say ""
  say "Last lines of what happened:"
  tail -n 20 "$LOG"
  fail "C did not build and run inside proot on this phone. Send the lines above, plus the Android version printed at the top, to the developer."
fi

say ""
tail -n 3 "$LOG"
say ""
say "PASS: C compiled and ran inside Alpine through proot (mode: $MODE)."
say "The Alpine system lives in private app storage: $ROOT"
