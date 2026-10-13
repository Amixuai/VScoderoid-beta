# Symbolic links on public storage

Shared storage (`/storage/emulated/0/...`) is served through FUSE and refuses
symbolic links; nothing in it can be executed. A workspace there is what makes
`node_modules` visible in a file manager, so the app works around the missing
links instead of moving the workspace.

## What was checked

- **proot cannot add links to a folder.** Its `--link2symlink` does the opposite
  job: it fakes *hard* links by using symbolic links, and so needs a filesystem
  that already has them. proot has no mode that emulates symlinks on one that
  does not. Routing commands through proot therefore does not remove the limit;
  proot is used for compilers, not for this.

## Layers (all in `assets/command-wrapper.sh`)

1. **Probe.** A folder counts as link-less only if a test link made in it fails.
   Folder names are just a first filter. On a phone or Android release where
   links work, every command runs exactly as typed.
2. **npm:** `--no-bin-links` is added to `install`/`ci`/`update`; package commands
   (`vite`, `tsc`) are provided as shell functions from `node_modules/.vscodroid-bins`.
3. **Python:** `python -m venv <dir>` is created in app storage and `<dir>/bin/activate`
   points to it.
4. **`ln`:** where a link cannot be made, a copy is made and one line says so.
5. **git** decides for itself (`core.symlinks=false` when a link cannot be made).

## Known gaps

- `ln -s` to a target that does not exist yet cannot be copied; the normal error shows.
- A copy is not a link: later changes to the original are not seen in it.
- `tar` extracting an archive that holds links still reports them as failed.
- pnpm, yarn and Go binaries are not covered (Go calls the kernel directly).
- Programs started inside proot (Alpine) see the same shared storage and the same limit.

## Next step if more is needed

An `LD_PRELOAD` library that stores a link as a tiny marker file and reads it
back, as Cygwin does. It would cover any program that uses libc, including `tar`,
but not Go, and not programs inside proot. It needs testing on a real device first.
