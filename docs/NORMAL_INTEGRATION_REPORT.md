# Integrating the Normal build's mobile-editor work into Beta Pro

Beta Pro stayed the foundation. Both trees pin VS Code 1.139.1 (commit `04c0d99f`) and share patches
0001-0027 (0019 differs, see below), so Normal's 0028-0034 were applied to Pro's own patched tree
rather than copied blind. Nothing was removed from Pro and the Public Workspace design is untouched.

## What was run, and where

| Check | Environment | Result |
|-------|-------------|--------|
| Patches 0001-0034 applied in order to upstream `04c0d99f` | Host (Linux sandbox, `git apply`) | All 33 apply cleanly. 0031 was applied in a scratch tree only and is not shipped |
| `scripts/test-workbench-layout.js` (activity bar, modal, bars, panel, sash, status toggle, panel save, round trip) | Host, Node 22.23 | 8 of 8 sections pass. Executes the patched functions under `vm`; does not render the workbench |
| `scripts/test-caret-drag.js` | Host, Node 22 | 44 checks pass. Runs the real injected script against a stub editor |
| `scripts/test-keyboard-guard.js`, `test-modifier-release.js`, `test-composing-enter.js`, `test-arrow-edge-guard.js` | Host, Node 22 | 100/100, 91/91, 26/26, 60/60 |
| `scripts/test-run-file.js` | Host, Node 22 | Passes, including four hostile file names, a failed build not starting the old binary, control characters, and mutation checks |
| Every other `scripts/test-*.js` (bridge relay, server bootstrap, process monitor, ui scale, welcome, xdg-open, dns proxy, serve network, ...) | Host, Node 22 | All pass |
| `scripts/test-ubuntu-routing.sh` | Host, stand-in for proot | 142 passed, 0 failed |
| `check-bridge-api-spec`, `check-translatable-strings`, `check-instrumented-inventory`, `check-workflow-steps`, `check-toolchain-claims`, `check-no-forced-folders`, `check-checklist-totals`, `check-build-steps`, `check-patch-fingerprints` (provenance half) | Host | Pass |
| **All Kotlin unit tests** (new and existing) | **NOT RUN** | Gradle and the Android SDK cannot be fetched from the sandbox (Google Maven, Maven Central and the Gradle plugin portal answer 403) |
| **All instrumented tests** | **NOT RUN** | No emulator, no device |
| **TypeScript compile of the patched workbench** | **NOT RUN** | `npm` is blocked, upstream dependencies could not be installed. Patches apply and their logic is exercised, nothing more |
| `check-patch-fingerprints` against a packaged `workbench.js` | **NOT RUN** | Needs a build |
| Anything on a real Android device | **NOT TESTED** | |

Nothing below should be read as device-verified. The Kotlin changes were written against Normal's code,
which was tested there, but neither tree was compiled here. Build once (`./gradlew testDebugUnitTest`)
before trusting them; expect to fix an import or two if something differs.

## Task by task

| # | Task | Status | What was done |
|---|------|--------|---------------|
| 1 | Code Action list kept across keyboard resize | Added, host-checked | Patch 0028 |
| 2 | Multi-line commit as one paste | Added, host-checked | Patch 0029 (needs 0022/0024, which Pro has) |
| 3 | Short landscape windows | Added, host-checked | Patches 0033 (title and status bar), 0034 (panel yields, remembered height); the user's saved layout state is not overwritten |
| 4 | System folder picker and SAF | **Already in Pro; Normal's 0031 not taken** | See below |
| 5 | Settings on small screens | Added, host-checked | Patch 0032 |
| 6 | Activity bar touch targets | Added, host-checked | Patch 0030; a unit test holds its constant to the 44px stylesheet Pro already injects |
| 7 | Physical keyboard | Added, **not compiled** | `HardwareTyping.kt` wired into `MainActivity.dispatchKeyEvent`/`dispatchTouchEvent`/`onConfigurationChanged`; the key row stands down while typing on a hardware keyboard and comes back on touch. Keys reach the page unchanged (observation happens after delivery) |
| 8 | Soft keyboard dismissal and key row | Added, host-checked JS, Kotlin not compiled | `KeyboardDismissal.kt`: a keyboard-hidden report is held 500 ms and dropped for a turn of the phone. Also Normal's `KeyInjector` fix that lends the latched modifier to an editor focused after the latch, which is what leaves a Ctrl or Alt stuck |
| 9 | Caret dragging | **Missing in Pro, ported**, host-checked | `injectCaretDrag` plus the keyboard guard's `__vscodroidCaretDragged` check, run in lint and release workflows. Covers wrapped lines, edge bands, small editors, second finger, cancel |
| 10 | Key row density and quick actions | Added, **not compiled** | Sixth page of shortcut keys (F1, Ctrl+P, Ctrl+\`, Ctrl+B, Ctrl+J, Ctrl+S) sent to the workbench, never the row's latches; repack on density change; `density` added to MainActivity's `configChanges`; strings in all 13 languages |
| 11 | Storage | **Reviewed, nothing merged** | See below |
| 12 | Toolchain environment | Partly adopted | See below |
| 13 | C/C++ | **Evaluated, Normal's pack not taken** | See below |
| 14 | Run File | Added and adapted, host-checked | saf-bridge 1.12.1 |
| 15 | Profiles, extensions, services | Adopted, **not compiled** | See below |

### 4. Open Folder

Pro's saf-bridge already registers `workbench.action.files.openFolder` and `openFileFolder` and sends them
to the system picker. `MainActivity.handleSafFolderSelected` turns a picked tree into the real path
(`PublicStorage.pathFromTreeUri`) and opens it in place; no copy is made. With All files access off it
explains why and offers the system screen instead of falling back to a copy. Only a provider with no path
(a cloud drive) uses the older copy-and-sync route, as before. Normal's 0031 asks "on the device or in the
app's storage" and offers the typed path box, which would point people at private storage. It was
left out on purpose. If a build wants the question anyway, the patch is in Normal and applies cleanly.

Not verified, because it needs a device: a folder renamed or moved after being picked, and a revoked grant.
The code paths for both exist; their behaviour was not exercised.

### 11. Storage

`SafStorageManager`/`SafSyncEngine` were compared, not merged. They have diverged in both directions
(Normal has about 1,450 lines Pro lacks; Pro has about 460 Normal lacks, among them the upload-claim and
stale-record retirement fixes), neither could be compiled or tested here, and in Pro this engine is only
the fallback for providers that have no path. Replacing a 5,800-line sync engine unverified would risk
exactly the data loss this task exists to prevent. `PublicStorage.kt` and the Public Workspace rules are
unchanged. The follow-up, for someone who can build: port Normal's tests that Pro lacks
(`SafDirectoryDeleteTest`, `SafEventDuringSyncTest`, `SafInboundIntegrityTest`, `SafKindConflictTest`,
`SafQueuedWriteBackTest`, `SafRecordSafetyTest`, `SafStagingLeftoverTest`, `SafWriterTurnTest`,
`SafLiveUploadClaimTest`), run them against Pro's engine, and fix what fails.
`SafDataPreservationInstrumentedTest` was not copied for the same reason.

### 12. Toolchains

Taken: `RUBYOPT=-rrubygems` in the Ruby manifest and a launch-time backfill for installs that predate it
(`ToolchainEnvBackfillTest`). Without it `require "sinatra"` fails for a gem `gem install` just added.
The env file now adds an option-list variable to the caller's value instead of replacing it, so a
`bundle exec`'s `RUBYOPT` survives, and refuses an env entry that could break the file every terminal
sources (`isShellSafeEnvEntry`).

Not taken: Normal's Java 21 pack, its C/C++ pack, `ownedPaths`, its PATH rewrite, JVM launcher flags and
the superseded-install-root removal. Pro stays on Java 17 and its install root does not move, so
`ToolchainReinstallTest` and `ToolchainOwnedPathsTest` have nothing to test here. The Ubuntu reinstall
path is Pro's own and already refuses anything that is not positively the app's own folder.

### 13. C/C++

Pro already routes `gcc g++ cc c++ cpp make cmake` into Ubuntu (first use installs `build-essential` and
`cmake`; `gdb`, `clang`, `clangd` come from `apt` and run by name). Normal's pack is Termux's clang, 245 MB
unpacked and 74 MB to download, that only starts through an exec interceptor, for a second compiler that
makes bionic binaries. Pro's users would carry two compilers for the same job, so it was not integrated.

- Architecture: arm64 Ubuntu natively. Intel programs run through qemu-user (experimental, existing feature).
- Needs: internet and free space for the first install (several minutes); All files access for projects in
  the Public Workspace.
- Limits: a binary built inside shared storage cannot be started by Android; Pro starts a private copy
  inside Ubuntu (`./prog`, or the new Run button, which builds to Ubuntu's `/tmp`). GUI debuggers and
  anything needing a real display are not covered. Debugging with `gdb` is available from `apt`; it was not
  exercised here.

### 14. Run File

The Run button (and the palette entry) shows for `.js .mjs .cjs .ts .mts .cts .rb .java .c .cc .cpp .cxx
.c++ .sh .bash`, saves first and refuses to run if the save failed, and runs in a "VSCodroid Run"
terminal in the workspace folder. Paths are single-quoted; a path with a control character is refused. Ruby
and Java are gated on the installed toolchain record with a Manage Toolchains offer. C and C++ differ from
Normal on purpose: `cc FILE -o /tmp/vscodroid-run && ubuntu /tmp/vscodroid-run`, because `$TMPDIR` is a phone
path that does not exist in Ubuntu, and `&&` keeps a failed build from running the previous binary. Not
done: passing program arguments, and Python (the Python extension already has its own Run button).

### 15. Profiles, extensions and services

- Bumping saf-bridge to 1.12.1 exposed a gap: Pro deleted superseded bundled extension folders without
  asking whether a named profile still listed them, so such a profile would have lost its bridge. Pro now
  points a named profile's entries for our own extensions at the new copy (user-installed extensions are
  left alone) and removes a superseded folder only when no profile lists it and every profile manifest was
  readable (`repointOwnExtensionEntries`, `ProfileOwnExtensionRepointTest`).
- `ProcessManager`/`NodeService`/`server.js`: the editor-server note carries a run id, a stop only ends a
  server it can prove it started, a bootstrap that ignores SIGTERM is SIGKILLed by pid, and a crash report
  for a replaced run is dropped. The harmless "File not found ... settings.json" line is kept out of the
  server log. These files had no Pro-only code, so Normal's versions were taken whole (with Pro's own
  comment about API 33 kept).
- Not taken: Normal's exec-preload (`LD_PRELOAD`) work, which belongs to its Termux-based C/C++ route.
- Not taken from `server.js`: the Python proposed-API flag and the JSON-comment regex change, which are
  unrelated to the 15 tasks.
- Normal's 0019 (callback registration) differs from Pro's nonce version and was left alone.

## Keyboard shortcuts

What reaches the editor from a hardware keyboard is whatever Android delivers to the activity; the page
sees each key as dispatched. Expected not to work, from how Android behaves, and **not verified on a
device**: the system's own shortcuts (Home, Recents, Alt+Tab, Meta/Windows combinations, Ctrl+Alt+Del),
and any chord an installed keyboard app or the OEM intercepts first. The quick actions page exists so the
commands a phone needs most do not depend on any chord. A latched Ctrl is not sent with the terminal's own
Ctrl+B/S by the quick keys: they go to the workbench so the terminal does not read Ctrl+S as XOFF.

## Files

48 new and 46 changed files (the saf-bridge 1.12.1 folder counts as its files), delivered as a delta zip beside this report.
The only removal is the folder `assets/extensions/vscodroid.vscodroid-saf-bridge-1.12.0`, replaced by
`...-1.12.1` (delete the old folder by hand when copying the delta over).

## Known gaps

1. Nothing was compiled or run on Android; see the table above.
2. Storage engine not unified (task 11), documented follow-up above.
3. Task 4's revoked/renamed-folder behaviour unexercised.
4. Run File passes no arguments.
5. The workbench patches were never compiled with `tsc`; first build is the real test.
