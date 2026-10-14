#!/usr/bin/env bash
# VSCodroid proot prototype: can this phone compile and run C inside a hidden
# Linux system, started through proot?
#
# Run it in the app's terminal:
#   bash ~/.vscodroid/proot-test.sh            Ubuntu 24.04 (glibc, like a PC) - the default
#   bash ~/.vscodroid/proot-test.sh alpine     Alpine (musl), kept to compare against
#
# What it does, in order:
#   1. checks that the app shipped proot and its loader
#   2. downloads the distribution's root filesystem once, checks its SHA-256, and
#      unpacks it into the app's PRIVATE storage
#   3. starts proot, installs gcc inside it, compiles hello.c and runs it
#
# Prints PASS or FAIL and, on FAIL, the evidence needed to fix it. Nothing here
# touches your projects. This copy is rewritten at every launch.
#
# Ubuntu needs a few hundred MB and several minutes the first time.

set -u

DISTRO="${1:-ubuntu}"
case "$DISTRO" in
  ubuntu|alpine) ;;
  *) echo "usage: bash proot-test.sh [ubuntu|alpine]"; exit 2 ;;
esac

ROOT="$HOME/proot/$DISTRO"
PROOT="${VSCODROID_PROOT:-}"
LOG="${TMPDIR:-/tmp}/vscodroid-proot-test.log"

say() { printf '%s\n' "$*"; }
fail() { say ""; say "FAIL: $*"; exit 1; }

say "VSCodroid proot prototype ($DISTRO)"
say "Android $(getprop ro.build.version.release 2>/dev/null) / $(uname -m) / $(getprop ro.product.model 2>/dev/null)"

# ---- 1. the engine is there -------------------------------------------------
[ -n "$PROOT" ] && [ -x "$PROOT" ] ||
  fail "proot is not in this build (VSCODROID_PROOT='$PROOT'). Rebuild the app after running scripts/download-termux-tools.sh, then restart it."
[ -n "${PROOT_LOADER:-}" ] && [ -x "$PROOT_LOADER" ] ||
  fail "the proot loader is missing (PROOT_LOADER='${PROOT_LOADER:-}')."
export PROOT_TMP_DIR="${PROOT_TMP_DIR:-$HOME/.vscodroid/proot-tmp}"
mkdir -p "$PROOT_TMP_DIR"
say "[1/3] proot engine found."

# ---- 2. the root filesystem, once --------------------------------------------
if [ ! -e "$ROOT/bin/sh" ] && [ ! -L "$ROOT/bin/sh" ]; then
  say "[2/3] Downloading $DISTRO (one time)..."
  python3 - "$DISTRO" "$ROOT" <<'PY' || fail "could not download or unpack $DISTRO (see the message above)."
import hashlib, io, os, re, sys, tarfile, urllib.request

distro, root = sys.argv[1], sys.argv[2]

def get(url):
    with urllib.request.urlopen(url, timeout=300) as r:
        return r.read()

if distro == "ubuntu":
    # Ubuntu Base: the official minimal root filesystem. The file name carries the
    # point release, so it is read from the checksum list instead of guessed.
    base = os.environ.get("VSCODROID_UBUNTU_BASE",
                          "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/")
    sums = get(base + "SHA256SUMS").decode()
    m = re.search(r"^([0-9a-f]{64}) [ *](ubuntu-base-24\.04(?:\.\d+)?-base-arm64\.tar\.gz)$",
                  sums, re.M)
    if not m:
        sys.exit("no arm64 Ubuntu Base in the release's checksum list")
    want, name = m.group(1), m.group(2)
else:
    base = os.environ.get("VSCODROID_ALPINE_BASE",
                          "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/")
    index = get(base + "latest-releases.yaml").decode()
    m = re.search(r"file:\s*(alpine-minirootfs-[0-9.]+-aarch64\.tar\.gz)", index)
    if not m:
        sys.exit("no mini root filesystem in Alpine's release list")
    name = m.group(1)
    want = None
    try:
        h = re.match(r"\s*([0-9a-f]{64})", get(base + name + ".sha256").decode())
        want = h.group(1) if h else None
    except Exception:
        pass
    if want is None:
        entry = index[m.end():].split("\n-\n")[0]
        h = re.search(r"sha256:\s*([0-9a-f]{64})", entry)
        want = h.group(1) if h else None
    if want is None:
        sys.exit("could not find the SHA-256 for " + name + "; refusing to unpack an unchecked download")

print("  fetching " + name)
data = get(base + name)
if hashlib.sha256(data).hexdigest() != want:
    sys.exit("checksum mismatch for " + name + "; refusing to unpack it")

# Device nodes and pipes cannot be made without root, and proot supplies /dev
# itself, so they are skipped. Hard links the phone refuses fall back to copies
# (tarfile does that on its own).
def wanted(tf):
    for member in tf:
        if member.isdev() or member.isfifo():
            continue
        yield member

os.makedirs(root, exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as t:
    try:
        t.extractall(root, members=wanted(t), filter="tar")
    except TypeError:
        t.extractall(root, members=wanted(t))
print("  unpacked " + name)
PY
else
  say "[2/3] $DISTRO is already unpacked."
fi

mkdir -p "$ROOT/etc" "$ROOT/tmp" "$ROOT/root/hello"
# Ubuntu ships resolv.conf as a link to a file that does not exist here; replace it.
rm -f "$ROOT/etc/resolv.conf"
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > "$ROOT/etc/resolv.conf"

if [ "$DISTRO" = "ubuntu" ]; then
  mkdir -p "$ROOT/etc/apt/apt.conf.d" "$ROOT/etc/dpkg/dpkg.cfg.d"
  # apt normally drops to an unprivileged user for downloads, which proot cannot
  # allow; run them as the (fake) root instead. force-unsafe-io speeds installs.
  printf 'APT::Sandbox::User "root";\nAcquire::Retries "3";\n' > "$ROOT/etc/apt/apt.conf.d/99-vscodroid"
  printf 'force-unsafe-io\n' > "$ROOT/etc/dpkg/dpkg.cfg.d/99-vscodroid"
else
  # Plain http for the package index: apk checks every package's own signature.
  sed -i 's#https://#http://#' "$ROOT/etc/apk/repositories" 2>/dev/null
fi

cat > "$ROOT/root/hello/hello.c" <<'EOF'
#include <stdio.h>
int main(void) {
    printf("Hello from C, built inside Linux on Android!\n");
    return 0;
}
EOF

# ---- 3. compile and run inside proot -------------------------------------------
run_proot() {
  "$PROOT" --link2symlink -0 -r "$ROOT" -b /dev -b /proc -b /sys \
    --kernel-release=6.2.1-vscodroid \
    -w /root --kill-on-exit \
    /usr/bin/env -i HOME=/root TERM=xterm LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/sh -c "$1"
}

if [ "$DISTRO" = "ubuntu" ]; then
  INNER='apt-get update -qq && apt-get install -y -qq --no-install-recommends gcc libc6-dev && ldd --version | head -n 1 && cd /root/hello && gcc hello.c -o hello && ./hello'
  EXPECT='GLIBC'
else
  INNER='apk add --no-cache gcc musl-dev && cd /root/hello && gcc hello.c -o hello && ./hello'
  EXPECT='Hello from C'
fi

try() {
  say "[3/3] Installing gcc and compiling inside proot ($1)... this can take several minutes the first time."
  shift
  ( "$@" ) > "$LOG" 2>&1
  local st=$?
  if [ $st -eq 0 ] && grep -q "Hello from C" "$LOG" && grep -q "$EXPECT" "$LOG"; then return 0; fi
  return 1
}

if try "default mode" run_proot "$INNER"; then
  MODE="default"
elif PROOT_NO_SECCOMP=1 try "without seccomp acceleration, for phones that need it" run_proot "$INNER"; then
  MODE="PROOT_NO_SECCOMP=1"
else
  say ""
  say "Last lines of what happened:"
  tail -n 25 "$LOG"
  fail "C did not build and run inside proot on this phone. Send the lines above, plus the Android version printed at the top, to the developer."
fi

# Remember which mode worked, so the app's commands start proot the same way.
if [ "$MODE" = "default" ]; then rm -f "$HOME/.vscodroid/proot-mode"; else printf 'noseccomp\n' > "$HOME/.vscodroid/proot-mode"; fi

say ""
tail -n 3 "$LOG"
say ""
say "PASS: C compiled and ran inside $DISTRO through proot (mode: $MODE)."
say "The system lives in private app storage: $ROOT"
