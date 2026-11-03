# Shared workspaces for small teams (Phase 3, not built yet)

Status: idea, agreed November 3, 2026. Planned for Phase 3 of the [roadmap](ROADMAP.md), after the mobile apps. When
work starts, update SPEC §1 and §17 and add decision D17 in [DECISIONS.md](DECISIONS.md) first.

## Goal

Tasklet stays personal by default. A workspace whose folder is shared (a OneDrive, Dropbox or Google Drive shared
folder, or a network drive) can also be used by a small team, about 2 to 10 people:

- people assign a task to themselves or to someone else;
- everyone sees who is doing what (on cards, in the task panel, on the boards);
- boards, lists and quick filters can be filtered by person, including "Me" and "Unassigned";
- someone running the project sees everyone's work and assigns it, like everyone else can.

A workspace without members looks and works exactly like today: no assignee chips, filters or pages anywhere.

Decisions already taken:

- **No roles.** A shared folder can't enforce permissions, so Tasklet doesn't pretend to (see Limits).
- **One assignee per task**, like Linear: clear ownership, simple cards, filters and merges. Two people pairing on a
  task can use a label.

## Why it fits the current design

- A workspace is already one folder that can be synced and shared (D15).
- Edits from two computers are already merged field by field per task, with a backup and a notice (D13). Two people
  changing different tasks in the same project already works today.
- Older versions keep fields they don't know (D1), so a new task field needs no format version bump: Tasklet 1.1
  opens a shared workspace and keeps every assignee intact when it saves.
- Settings already has "Your Name".

## Limits (say these in the app and the docs, don't hide them)

- **No permissions.** Anyone who can write to the shared folder can change or delete anything. A "manager" role
  that only hides buttons would be fake security, so there is none. People who need real permissions need a server.
- **Not real-time.** A change shows up on the other computers when the sync service delivers the file, which can
  take seconds or minutes. Edits that overlap are merged (D13); conflict copies made by the sync service stay listed
  and untouched (D3).
- **One file per project.** The more people work in one busy project, the more often saves merge. If merge notices
  become frequent, split project files into chunks (SYSTEM_DESIGN option F, a format version bump).
- **Out of scope:** accounts, login, a server, instant updates, comments, mentions, permissions. Those make Tasklet
  a different product.

## Data

All additive: no format version bump.

### `members.json` in the workspace folder

Synced with the folder, next to `labels.json` and `views.json`, and handled the same way:

```json
{
  "members": [
    { "id": "m_3f2a", "name": "Aasif", "color": "blue" },
    { "id": "m_9c1d", "name": "Sara", "color": "teal" }
  ]
}
```

- Fields: `id` (random, never reused), `name` (required, 40 characters, unique ignoring case), `color` (one of the
  16 named colors), plus unknown fields kept in `extra`.
- Missing file: no members, the workspace is personal. Unparsable file: read-only, writes refused, shown as a notice
  (same as labels.json).
- Local backups and Restore Previous Version through the existing D12 path.
- The file is created only when the first member is added (like the lazy No-Project file).

### Task fields

- `assigneeId` (string, optional): the member doing the task. Merged as a normal field by `lib/core/merge.dart`.
- `updatedBy` (string, optional, last step of Phase 3): the member who last changed the task, set on every edit from
  this computer. Lets the task panel say "Changed by Sara, 5 min ago".
- An `assigneeId` that matches no member shows as "Unknown person" and is kept, so a member list restored from a
  backup brings the names back.

### Which member am I

A device pref, never synced: workspace folder → member id. Chosen the first time a shared workspace opens ("Which one
are you?", or "Add Me" using Your Name). Changeable in Settings > Workspaces. Until it's set, "Me" matches nothing
and the app asks again.

## Filters

- New category **Assignee** in `BoardFilters`: member ids, plus `Unassigned` and `Me`.
- OR within the category, AND with the others, like labels (`lib/core/filters.dart`).
- `Me` is stored as a marker, not as an id, and resolved on each computer, so one "Assigned to Me" quick filter
  works for everyone who opens it.
- Removing a member prunes their id from filters, like a deleted label.

## UI

Everything below appears only when the workspace has members.

- **Assignee chip**: initials in the member's color. On cards and list rows (a display property that can be hidden),
  in the New Task dialog and in the task panel's chip band. Built on `PropChip` and the picker pattern in
  `lib/ui/task/pickers.dart`; the picker lists members, "Unassigned" and "Assign to Me" first.
- **Context menu**: "Assign to ▸" (with `submenuItem`) and "Assign to Me", with a keyboard shortcut.
- **Filter menu**: the Assignee category, with Me and Unassigned at the top.
- **Quick filter**: "Assigned to Me" added to a workspace when its first member is added (only if no quick filter
  with that name exists).
- **Members page** (sidebar, or a section in Settings > Workspaces): add, rename, change color, remove (asks first,
  then unassigns their tasks), and "This is me".
- **New Task defaults**: the assignee from a single-person filter, else Me when the workspace has a "me", else
  nobody.

## Scoping in a shared workspace

- **Today and Dashboard** show my tasks and unassigned ones by default, with a toggle for everyone's.
- **Reminders** only count my tasks (and unassigned ones, if the toggle says so), so nobody is notified about a
  colleague's work (`lib/core/reminder.dart`, `lib/core/today_rules.dart`).
- **Reports** get totals per person and an assignee filter (`lib/core/report.dart`).

## Build order inside Phase 3

1. Members file, `assigneeId`, the assignee picker and chip, the Assignee filter with Me and Unassigned.
2. "Which member am I", Today/Dashboard/reminders scoped to me, the Assigned to Me quick filter, the Members page.
3. `updatedBy` in the task panel, per-person report totals. Look at merge-notice frequency and decide on chunked
   project files.

## Tests to write then

- `test/core/`: task round-trip with and without `assigneeId` (a file without it is unchanged apart from the new
  field after editing); Assignee filter (member, Unassigned, Me, combinations); pruning when a member is removed;
  merge of an assignee changed on two computers (newer wins, D13 rules); New Task defaults.
- `test/data/`: `members.json` missing, unreadable (read-only, never overwritten), backups and restore.
- Widget tests: a workspace without members shows no assignee UI anywhere; with members, assign from the chip and
  the context menu, filter by Me.
- Two stores on one temp folder (like the D13 tests): each assigns a different task and both survive; both assign
  the same task and the newer one wins.
- Run the app (tasklet-run skill) on a demo workspace with three members, in both themes and at 900x600.
