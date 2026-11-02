# Design decisions

Choices made where [SPEC.md](SPEC.md) is silent or ambiguous. Each one favors the spec's core promise: never lose or
hide the user's data, and never surprise them.

## D1. Data from newer versions or hand edits: hide the entry, never the file

**Problem.** A newer Tasklet on another machine may write values this version doesn't know (a new status, a new
color), and a hand edit can break one task. Treating any odd value as "file unreadable" would hide a whole project and
block all edits to it.

**Decision.** Mirror how open enums work in protobuf (proto3): keep what you don't understand and write it back
unchanged.

- Unknown *fields* are kept in `extra` (already required by SPEC §2.5).
- A *list entry* (task, project label, workspace label, saved view) that doesn't parse, or repeats an id already
  seen, is kept verbatim as an opaque entry, hidden from the UI, counted in `Workspace.hiddenEntryCount`, and written
  back unchanged on every save. Its task number still counts toward `nextNumber`, so numbers are never reused.
- An unknown *color* displays as neutral and is written back until the user picks a color.
- Only damage to the file itself (invalid JSON, or a project missing its id/name/createdAt) makes a file unreadable, and unreadable files are never overwritten.

The UI will show a non-blocking notice when `hiddenEntryCount > 0` ("Some items were created by a newer version of
Tasklet, update to see them").

## D2. Format version: newer format = read-only

`tasklet-workspace.json` stores `formatVersion` (currently 1). It is bumped only for changes older versions can't
safely write; additive changes rely on D1. If the marker says a newer version, or can't be read right now (likely
mid-sync), the workspace opens **read-only** for that read: everything is shown, nothing is saved (including key
self-healing). A missing marker means a fresh or legacy folder and is writable.

## D3. Sync conflict copies

Providers name copies differently, Dropbox `name (Ada's conflicted copy 2026-10-01).json`, OneDrive
`name-DEVICE.json`, Google Drive `name (1).json`, iCloud `name 2.json`, Syncthing
`name.sync-conflict-20261001-101010-ABCDEFG.json`, Synology `name_Conflict...`. Tasklet doesn't parse names: a project
file is canonical only if its file name equals the id inside it; every other parsable file with that id is a copy.
This works for every provider.

- Copies are never written, renamed, or deleted by sync logic (SPEC §2.5) and are reported in `Workspace.conflicts`.
- **Main file missing** (only copies exist): the newest copy (by `updatedAt`) is shown instead of hiding the project,
  flagged `mainFileMissing`; the first save recreates the canonical file and the copy stays untouched. Not done when
  the main file exists but is merely unreadable (it may be mid-download).
- Copies of `labels.json` / `views.json` (files in the folder root starting with `labels` / `views`) are reported too.

## D4. Deleting a project

SPEC §4.5 promises the file goes to the Recycle Bin/Trash. Windows only has a Recycle Bin on fixed local drives;
`SHFileOperation` with `FOF_ALLOWUNDO` silently deletes permanently on network and removable drives.

- Windows: recycle only when `GetDriveType` reports a fixed drive. macOS: `FileManager.trashItem` (fails on volumes
  without a Trash).
- Otherwise the file is moved to `<data folder>/.trash/` (never read by Tasklet, syncs like the rest, recoverable by
  hand). Deletion is never permanent.
- The project's conflict copies are trashed with it, otherwise it would reappear from a copy (D3).
- After deletion the store refuses to write that project again in the session, so a late save can't resurrect it.

## D5. Project ids are file names

Ids must match `[A-Za-z0-9_-]{1,64}` and must not be a Windows reserved device name (`CON`, `PRN`, `AUX`, `NUL`,
`COM0–9`, `LPT0–9`, any case, these are invalid even with an extension). Files with other ids are treated as unreadable
and never written. New ids are lowercase UUID v4.

## D6. Priority sort with "None"

SPEC §5.3 says None sorts last regardless of direction but also suggests "rank None as 5, then apply the direction",
which would put None first when descending. The explicit rule wins: None is always last.

## D7. Code style

Standard `dart format` (80 columns, the Dart default) and `flutter_lints` plus a few strict rules. No custom page
width, so contributors need no special editor setup and diffs fit side by side.

## D8. Confirmation dialogs

SPEC §4.5/§4.6/§4.8 ask for native confirms with **Cancel as the default button**. The native alert APIs available to
Flutter on Windows don't let us choose the default button for custom labels ("Delete" / "Cancel"), so confirms are a
small in-app dialog styled like a system alert: Cancel has initial focus, Enter/Space activate it, Escape cancels,
and the destructive button is red. Task deletion never confirms (SPEC §7.4).

## D9. Creating a new data folder

"Create New Folder…" (SPEC §10) uses the native folder picker to choose *where*, then a small name prompt (default
"Tasklet") that refuses names already in use. A native save-file dialog was rejected: it writes a file at the chosen
path, and confirming its "replace existing file?" prompt would destroy whatever file had that name.

## D10. macOS sandbox

v1 ships as a non-sandboxed, notarized app (like most sync-folder tools), so Tasklet can keep using any folder the user
picked across launches without security-scoped bookmarks. An App Store build would need the sandbox plus bookmarks.

## D11. "Quick Filters" label

The spec calls saved filter sets "Views". With a Board/List view switch on every board, plain "Views" read as
ambiguous, and "Saved Views" still didn't say what the page does. The app calls them **Quick Filters** everywhere a
user reads it: the sidebar item and section, the page, menus, What's New and Settings → Sidebar. Routes (`/views`),
`views.json`, its fields and code names (`SavedView`) are unchanged, so existing data folders keep working.

## D12. Local backups and data repairs after sync

The data folder is the only copy of the user's work and may be rewritten by a sync client, another computer or a
bug. Two additions protect it:

- **Backups.** Before a project, labels or views file is overwritten, its current version is copied to
  `<app support>/backups/<workspace key>/<file>/`, at most once per 10 minutes per file, keeping the newest 20. They
  live outside the data folder on purpose: they don't sync, don't clutter a shared folder and survive damage to it.
  "Restore Previous Version…" on a project replaces it with a backup after backing up the current version, keeps the
  project's current key and never lowers `nextNumber`, so task numbers are still never reused (SPEC §2.4). Backups
  are per computer and are not a replacement for the sync service's own version history.
- **Repairs on read**, like the project-key self-heal in SPEC §2.4: duplicate task numbers in one project (two
  computers both creating WEB-13 offline) are renumbered, oldest task first; stored keys that aren't valid keys are
  regenerated; a marker without `formatVersion` (or `1.0`) counts as version 1; files over 100 MB are treated as
  unreadable. Manual order (SPEC §5.1) re-spaces only the neighbours around a drop when they share a position, so a
  card always lands where it's dropped.
