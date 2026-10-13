# proot prototype (Alpine Linux, hidden)

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

    bash ~/.vscodroid/proot-test.sh

It downloads Alpine's minimal root filesystem (SHA-256 checked) into
`~/proot/alpine` (private storage), installs gcc inside it with `apk`, compiles
`hello.c` and runs it. It prints PASS or FAIL; on FAIL it prints the last lines
of the log and the Android version. It tries once normally and once with
`PROOT_NO_SECCOMP=1`, which some phones need.

## Not done yet

- No command is routed through proot. That comes after this passes.
- Project folders are not bound into Alpine yet.
- Public storage still cannot hold symbolic links, with or without proot.

## Storage

The Alpine system lives in private app storage, like the other engines.
Projects stay in the visible workspace.
