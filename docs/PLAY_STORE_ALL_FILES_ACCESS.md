# Play Store: the All files access declaration

Prepared 2026-10-15. Nothing here has been submitted. Check the current Play Console policy text
before submitting; a reviewer decides each case, so approval is not assured.

## What is declared

`android.permission.MANAGE_EXTERNAL_STORAGE`, in `android/app/src/main/AndroidManifest.xml`. The user
turns it on from Android's own "All files access" screen; the app asks once and explains why.

## Why the app needs it (the core-functionality answer)

VSCodroid is a code editor and terminal. A project is a tree of files that git, npm, Python and the
compilers read and write directly by path. The Storage Access Framework hands an app a `content://`
URI, not a path, so the previous design copied each chosen folder into private storage and synchronised
it back. That copy was slow, doubled the storage, and could lose edits when the app was killed mid-sync.
Real paths remove the copy and let the user see and manage their project files in any file manager, as
on a computer.

## Alternatives that were tried or considered

| Alternative | Result |
|-------------|--------|
| SAF folder picker with a mirror copy | Built and shipped; kept as the fallback. Too slow for `node_modules` and builds, and not a real path for command-line tools |
| App-private storage only | Works, but projects are invisible to other apps and file managers, and cannot be shared without an export step |
| MediaStore | Does not cover source files and folders |

## What the app does with the access

- It opens only its workspace folder (`/storage/emulated/0/vscodroid`) and folders the user picks.
- Files are read and written with ordinary file calls; nothing is uploaded and nothing is indexed.
- An empty `.nomedia` keeps the workspace out of Gallery and Recent.

## If the declaration is refused

Ship a Play build without the permission. The SAF mirror route is still in the code: the folder picker
falls back to it whenever the permission is off. Terminal commands that need real paths then work on
the mirror copy only. A build flavour that removes the permission is not made yet.

## Other Play items touched by this change

- Privacy policy names the permission (`docs/PRIVACY_POLICY.md`, checked by
  `scripts/check-permission-claims.py`).
- The listing's permission summary in `docs/10-RELEASE_PLAN.md` was updated.
- The Ubuntu system is downloaded at run time from Ubuntu's servers and runs through proot; the release
  plan's binary-execution policy row should be read again before submission, because a downloaded
  Linux system is not delivered by Play.
