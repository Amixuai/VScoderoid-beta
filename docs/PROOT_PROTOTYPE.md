# proot prototype (hidden Ubuntu, with Alpine to compare)

Goal: C, C++, Rust and Go build on a phone where Android will not run them
natively, with the user seeing only the normal VS Code terminal.

This prototype answers one question first: does proot start and run a compiler on
the target phone?

## Build

1. `scripts/download-termux-tools.sh` now also fetches `proot` and `libtalloc`
   from Termux (signature-checked like the other packages). `libproot.so` and
   `libproot-loader.so` land in `jniLibs/arm64-v8a`, `libtalloc.so.2` and
   `libandroid-shmem.so` (which `libproot.so` links) in `assets/usr/lib`.
2. Build the app as usual and install it.

## Test on the phone

In the app's terminal, after restarting the app once:

    bash ~/.vscodroid/proot-test.sh            # Ubuntu 24.04, the default
    bash ~/.vscodroid/proot-test.sh alpine     # Alpine, to compare against

Why Ubuntu is the default: it uses glibc, as a PC does. Alpine uses musl, so
prebuilt PC binaries, many Python wheels and native Node modules fail on it.

It downloads the official root filesystem (Ubuntu Base, arm64; the file name is
read from the release's `SHA256SUMS`, and the download is checked against it)
into `~/proot/ubuntu` (private storage), installs gcc inside it with `apt`,
compiles `hello.c`, prints the glibc version and runs the program. It prints PASS
or FAIL; on FAIL it prints the last lines of the log and the Android version. It
tries once normally and once with `PROOT_NO_SECCOMP=1`, which some phones need.
Budget a few hundred MB and several minutes the first time.

Things likely to need attention on a phone, which the log will show: newer glibc
calls system calls (`clone3`, `faccessat2`) that some Android versions block
unless proot translates them; and `apt` must run its downloads as the fake root,
which the script sets in `/etc/apt/apt.conf.d/99-vscodroid`.

## Not done yet

- No command is routed through proot. That comes after this passes.
- Project folders are not bound into Alpine yet.
- Public storage still cannot hold symbolic links, with or without proot.

## Storage

The Alpine system lives in private app storage, like the other engines.
Projects stay in the visible workspace.
