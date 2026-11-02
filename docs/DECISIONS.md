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

"Create Organization…" (SPEC §10's "Create New Folder…", D15) asks for the organization's name and uses the native
folder picker to choose *where*; the folder is named after the organization and must not exist yet. A native save-file dialog was rejected: it writes a file at the chosen
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

## D13. Merging edits from two computers

Whole-file "last writer wins" could lose an edit when two computers changed one project between syncs. Every project
save now compares the file's stamp (modified time and size) with what this computer last read or wrote. If it
changed, the save merges instead of overwriting (`lib/core/merge.dart`), keeps a backup of the other version, and
shows a notice:

- Per task, field by field: a field changed on one side takes that side's value; changed on both, the more
  recently updated task wins. Timestamps more than 5 minutes in the future count as "now", so a wrong clock can't win
  every conflict.
- A task deleted on one side stays deleted unless the other side edited it after (then it is kept and reported).
- Tasks created on both sides are both kept; a duplicate number goes to the newer one (as on read).
- Project fields merge the same way; the project's own labels list merges as one value (rarely edited on two
  computers at once).
- A changed file that can't be parsed yet (mid-sync) is never written over; the save fails with a message.

The watcher recognises this store's own saves by the file stamp it wrote, not by a 2-second window, so another
computer's change landing right after a local save is picked up. Deletion markers (tombstones) were not added: the
last-read version already tells "deleted here" from "created there". They would only be needed to merge the sync
service's conflict copies, which stay listed and untouched (D3). Refresh still waits while any save is running:
typical saves take 6-15 ms, so per-file tracking would add complexity without a measurable benefit.

## D14. Icons for projects and labels, 16 colors

SPEC §8.2 and §8.5 give projects a tinted cube and labels a dot in one of 8 colors. Projects and labels can now also
have an icon, and there are 16 colors.

- Icons come from Lucide (MIT/ISC, `lucide_icons_flutter`, pinned). The picker offers a curated set of about 640
  project-related icons in 14 categories, with search by name, Lucide's tags and category. The list is
  `tool/icons/catalog.txt`; `tool/icons/gen_catalog.py` turns it into const `IconData` (so release builds keep only
  these glyphs) and refuses names the font lacks or draws empty (Lucide dropped its brand icons).
- Stored as `"icon": "<lucide name>"` on the project or label, omitted when there is none. No icon, or a name this
  version doesn't know, draws the cube or dot; the name is written back unchanged (like an unknown color, D1). A
  non-string value from a newer version stays in `extra`.
- Several labels on one card still show overlapping dots (§8.5): icons don't read when stacked.
- New colors: teal, cyan, indigo, pink, lime, amber, brown, slate. Older versions show them as neutral and keep
  them (D1). Every color must reach 3:1 against every surface as a glyph, so green, orange and yellow (and the new
  colors) use darker shades in the light theme; `test/ui/design_system_test.dart` checks this.
- Quick filters keep their stacked-layers glyph with the 16 colors.

## D15. Organizations are data folders

SPEC §1 has one workspace (one folder). People who work for an employer, freelance and contribute to open source
want those kept apart, sometimes on the same day. An **organization** is one Tasklet data folder; the app opens one at
a time and switches between them from the sidebar header, the Organization menu or Ctrl+Alt+1 … 9.

- Why folders, not an organization field inside one folder: complete separation for free (projects, labels, quick
  filters, No Project, keys, backups, Today, dashboard, reports and reminders all already work per folder); each
  organization can sync through a different service, so work data can stay in the company's cloud; no data-format
  migration; an organization moves, backs up or is shared as a plain folder.
- Identity: `name`, `icon` and `color` in the folder's marker (`tasklet-workspace.json`), so they sync with it. A
  marker without a name (a folder from before organizations) shows the folder's name. Saving replaces only the fields
  the user changed, so values from a newer version and unknown keys survive. Older versions only read the marker's
  `formatVersion` and never rewrite it, so the format version stays 1.
- This computer's list: the `organizations` device pref holds the folders in the user's order, with each one's name,
  icon and color cached for the switcher; it refreshes whenever that folder opens. `dataFolder` stays the open one,
  so older settings files still work: their folder becomes the first organization. The list isn't synced: on a new
  computer, add each folder with Open Existing Folder… (its name comes from its marker). Removing an organization
  only forgets it on this computer; its folder is never deleted.
- Switching saves pending edits into the current folder first. Board filters and searches, the open task, Undo and
  repair notices belong to the folder and start empty in the other one. Reminders, badges and the tray follow the
  open organization only. Board layout preferences for All Tasks and Today stay per computer, not per organization
  (a personal preference, and project and quick-filter boards are already per folder).
- The window title and tray tooltip name the open organization ("Acme Corp - Tasklet").
- Settings → Organizations lists them; its changes go to the main window, which owns the open folder.
- Move to Organization (a project's menu) writes the project into the other folder first and only then removes it
  here (Recycle Bin or `.trash`), so a failure never leaves it in neither. Workspace labels its tasks use go along
  as the project's own labels (the other folder's labels.json is never touched); task numbers stay; the key changes
  only if a project there already has it. A folder saved by a newer version refuses it.

