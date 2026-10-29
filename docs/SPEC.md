# Tasklet — Product & Technical Specification

> Derived from the "Per" product spec. Naming substitutions applied throughout:
> app name **Per → Tasklet**, marker file **`per-workspace.json` → `tasklet-workspace.json`**,
> No-Project reserved key **`PER` → `TSK`**. Behavior is otherwise unchanged.
>
> v1 targets **Windows and macOS** from one Flutter codebase; iOS/Android follow in phase 2.
> Every behavioral requirement below is what matters — if Flutter can't express something exactly, find the closest
> idiomatic platform equivalent rather than skipping it. The sections interlock (sorting rules affect both board and
> list; project-key rules affect task IDs everywhere). Treat this as a precise spec, not inspiration.

---

## 1. Product vision

Tasklet is a single-player, local-first task tracker inspired by Linear's interaction design, but intentionally
simpler: no teams, no assignees, no accounts, no server. One person's tasks, projects, and views, stored as plain files
on disk so they can live in a synced folder (OneDrive, Dropbox, Google Drive, iCloud Drive, …) and follow the user
between machines without any backend.

Design principles:

- **Fast and keyboard-first**, like Linear: quick-create, quick shortcuts, inline editing everywhere, no modal-heavy
  workflows for routine actions.
- **Calm, minimal, information-dense UI** — small text (12–13px body), compact rows, muted secondary/tertiary text,
  no heavy borders or shadows, whitespace via padding rather than large fonts.
- **Nothing is ever truly destructive without a way back** — deletes are either reversible (Undo toast) or need explicit
  confirmation, never both unnecessarily.
- **The app teaches itself** — every empty state explains what to do next; no onboarding tour.

## 2. Data model

All data is plain JSON files in a folder the user chooses (not a database, not a cloud account). This is the single most
important architectural decision — it's what lets the folder live in a synced drive.

### 2.1 Folder layout

```text
<chosen folder>/
  tasklet-workspace.json    marker file + format version, created once
  labels.json               workspace-wide labels (array), optional
  views.json                saved views (array), optional
  projects/
    <project-uuid>.json     one file per project, containing all its tasks
```

One JSON file per project (not one giant file) so a sync conflict on one project never touches another, and partial /
concurrent edits are less likely to corrupt unrelated data.

### 2.2 Entities

**Task**

| field | type | notes |
|---|---|---|
| id | string (uuid) | |
| number | int | sequential within its project, starting at 1, never reused |
| title | string | |
| description | string | plain text, may be empty, multi-line |
| status | `"backlog" \| "todo" \| "in_progress" \| "done"` | |
| priority | `0..4` | 0 none, 1 urgent, 2 high, 3 medium, 4 low |
| startDate | `"YYYY-MM-DD" \| null` | local calendar date, no time |
| dueDate | `"YYYY-MM-DD" \| null` | |
| labelIds | string[] | ids of project-owned or workspace labels |
| sortOrder | float | manual ordering position (§5.1) |
| createdAt | ISO 8601 | |
| updatedAt | ISO 8601 | bumped on every edit |
| completedAt | ISO 8601 \| null | set when status becomes done, cleared otherwise |

**Project**

| field | type | notes |
|---|---|---|
| id | string (uuid) | |
| name | string | |
| key | string | short uppercase task-ID prefix, §2.4 |
| color | one of 8 colors (§8.2) | |
| archived | bool | |
| favorite | bool | |
| sortOrder | float | position in sidebar Projects list |
| favoriteOrder | float | separate position in Favorites list |
| labels | Label[] | project-owned labels (only this project's tasks may use them) |
| nextNumber | int | next task number to hand out |
| createdAt / updatedAt | ISO 8601 | |
| tasks | Task[] | |

**Label** — `id` (uuid), `name` (max 40 chars, case-insensitive-unique within its scope), `color` (one of 8).
Labels are either workspace-wide (`labels.json`, usable by any task) or project-owned (inside the project file, usable
only by that project's tasks). A task's `labelIds` may reference either kind interchangeably.

**SavedView** — a named, reusable filtered board across every project:
`id`, `name`, `color`, `filters: { status[], priorities[], projects[], labels[], due[] }` (same shape as board filters,
§6), `display: ViewDisplay | null` (null = defaults, §5), `inSidebar: bool`, `sidebarOrder: float`,
`createdAt / updatedAt`.

**Workspace** (in-memory shape assembled by reading the whole folder):
`folder`, `projects[]`, `labels[]` (from labels.json), `labelsReadable: bool` (false if labels.json exists but can't be
parsed now), `views[]`, `viewsReadable: bool`, `conflicts: { file, projectName }[]` (§2.5).

### 2.3 The "No Project" bucket

Tasks don't require a project. A task created without one is filed into a built-in pseudo-project **"No Project"**:

- Fixed id (reserved constant, not a real uuid), fixed key **`TSK`**, fixed name "No Project", neutral color.
- Behaves like a project for task IDs (TSK-1, TSK-2, …) but never appears in the sidebar project list, the Projects page,
  or any archive/delete/rename UI. It can't be renamed, archived, or deleted.
- Its file is written only the first time a task needs it (lazy creation) — no empty file up front.
- Its key `TSK` is reserved from the start (even before the file exists) so no real project's auto key can collide.

### 2.4 Project keys & task IDs (exact algorithm)

- **Base key** = the first 3 letters only (strip spaces, numbers, punctuation) of the project name, uppercased. If that
  yields nothing, fall back to `PRJ`.
- **Uniqueness**: if the base key is taken, append 1, 2, 3, … until free (WEB, WEB1, WEB2, …).
- **One-time and sticky**: computed once (on creation, or the first time a legacy file is read) and kept forever, even if
  the project is renamed — task IDs must stay valid wherever they were pasted.
- **Resolution order** when multiple projects claim the same key (e.g. created offline on two machines): by `createdAt`
  ascending — the oldest keeps the key, newer ones get the next free suffix. Recompute this every time the whole
  workspace is read so conflicts self-heal once synced.
- Task numbers (`project.nextNumber`) are never reused, even after deletion.
- A task's visible ID is always `${project.key}-${task.number}`.

### 2.5 Storage integrity rules

The folder may be inside a syncing cloud drive, which can partially write files or produce duplicate copies.

- **Atomic writes**: write to a temp file, then rename over the real file — never write in place.
- **Unreadable files are left alone**: if a file exists but fails to parse right now, skip it silently in that read
  rather than treating it as absent (which could recreate/lose data on the next save). Surface as a non-blocking state
  (e.g. `labelsReadable: false`), never an app-blocking error.
- **Sync conflict copies**: if the provider leaves two files for one project (`abc123.json` and `abc123 2.json`, same id
  inside), only ever read/write the canonical `<id>.json`; leave the copy untouched on disk and report it once per app
  session as a dismissible informative notice — "this project has a second copy from syncing, main version shown, extra
  copy left at X, open folder to compare" — with a button to reveal it in the file explorer.
- **Forward-compatible fields**: preserve unrecognized JSON fields on tasks/projects/views and write them back unchanged.
- **Missing data folder**: if the chosen folder no longer exists, show a clear "can't find your folder" error screen with
  a way to re-pick it — never treat it as an empty workspace and never auto-recreate it.
- **Undo-safety for deletes**: deleted tasks go into an in-memory "recently deleted" cache (cap ~50, oldest evicted) so
  Undo restores the exact original id/number/fields. Not persisted — after restart, deletions are final.

## 3. App shell & navigation

### 3.1 Window

- Main window: resizable, default 1280×820, minimum 900×600 (fits sidebar + at least 2 full kanban columns).
- Separate small fixed-size non-resizable **Settings window**, 520×440, tabbed (§11).
- Native window chrome (Windows title bar on Windows, standard macOS chrome on macOS).

### 3.2 Layout

Two-pane split: **left sidebar** (resizable ~190–300px, default 220px, remembered, never collapses to icons) and
**right main area** (current page with its own header bar, plus a secondary toolbar strip on board/list pages).

### 3.3 Sidebar structure (top to bottom)

1. **Top toolbar row**: "New Task" button (compose icon) — creates in the project being viewed, or with no project on a
   non-project page.
2. **Primary navigation** (in order): Dashboard · Today (count badge) · All Tasks (count badge) · Projects · Views ·
   Labels · Reports (hidden by default, §11.2).
3. **Views section** (only if ≥1 view pinned) — collapsible; pinned saved views with colored stacked-layers icon.
4. **Favorites section** (only if ≥1 favorited project) — collapsible; colored cube icons. A favorited project appears
   only here, not also under Projects.
5. **Projects section** (only if ≥1 non-archived, non-favorited project) — collapsible, drag-reorderable.
6. **Archived section** (only if ≥1 archived project) — collapsible, collapsed by default.

Empty sections are omitted entirely. Nav items, Favorites, and Projects reorder by drag within their section; order
persists.

Right-click a project row: Add/Remove Favorite, Rename, New Project…, Move Up, Move Down, Archive/Unarchive,
Delete Project… Right-click a view row: Rename, Remove from Sidebar, Move Up, Move Down, Delete View…

Footer: a **"What's New"** row (sparkle icon + small unread dot), only when there are unread release notes (§13).
Clicking opens the What's New dialog; once dismissed it disappears until the next update ships new notes.

### 3.4 Count badges

- Today = open (non-done) tasks matching the Today rules (§4.2).
- All Tasks = open tasks across all non-archived projects (including No-Project).
- Both update live.

### 3.5 Customizable sidebar (Settings → Sidebar)

The primary nav items except Dashboard (pinned first, can't be hidden/moved) can be reordered by drag and hidden/shown
via a toggle per row. Reports defaults to hidden. Changes apply live (no restart, no Apply button).

## 4. Pages

### 4.1 Dashboard (`/`)

- Header: title "Dashboard" + top-right pill project filter ("All Projects" or one project), remembered.
- Greeting: "Good morning/afternoon/evening[, Name]" (hour < 12 morning, < 18 afternoon, else evening), name from
  Settings → General. Below: today's full date ("Friday, October 23"). Both update live on a timer (30–60s) so leaving
  the app open overnight rolls over.
- Zero tasks in current filter → empty state ("No tasks yet" / "This project has no tasks").
- Otherwise four stacked sections, each rendered only if it has content:
  - **Glance strip** — 4 big numbers: Overdue (red if > 0), Due today (orange if > 0), Due this week, Done this week.
    "This week" = today + next 6 days. "Done this week" = completed within the last 7 days.
  - **Up Next** — up to 6 open tasks overdue or due within the next 7 days, sorted by due date asc (needs a due date),
    tie-break priority (urgent→low, none last), then manual order. Row: status icon, ID, title, project name+icon (only
    when filter = All Projects), colored due pill (red overdue, orange today).
  - **Overview** — one "Status" card: thin segmented progress bar (Backlog/Todo/In Progress/Done, color-coded) + an
    icon+label+count+percentage line per status.
  - **Recently Completed** — up to 5 tasks completed in the last 7 days, most recent first; same rows, showing completed
    relative date.
- Every Up Next / Recently Completed row opens the detail panel on click and has the full card context menu (§7.3).

### 4.2 Today (`/today`)

- A flat list (no board) grouped by status in workflow order, of every task matching any of three toggleable rules
  (via a "Filter" toolbar button, persisted): **Due today**, **Starts today**, **Overdue** (due in the past, not done).
- At least one rule must stay on — the UI prevents disabling the last.
- Updates live at midnight (timer).
- Default display hides Priority and Start Date; everything else (ID, status, due date, labels, project) shown and
  configurable (§5.2).
- "+ New Task" always pre-fills due = today. Adding from inside a status section creates with that status AND due today.
- Empty state: "Nothing for today" + description of the three rules.

### 4.3 All Tasks (`/my-tasks`)

Every open+closed task from every non-archived project, including No-Project, as board or list (§5.2). Full
filter/sort/search toolbar (§6). "+ New Task" creates with no project preselected.

### 4.4 Project board (`/projects/:id`)

Header: project cube icon (tinted) + name, "+ New Task" defaulting into this project. Toolbar like All Tasks but with
the Project filter/column hidden and labels scoped to this project's labels + workspace labels. Unknown id →
"Project not found".

### 4.5 Projects (`/projects`)

- Header: "Projects", pill "Active / Archived" segmented toggle (remembered), and (Active only) "+ New Project".
- Flat list under a heading ("Active Projects N" / "Archived Projects N").
- Row: [color/icon → 8-color picker] [name, double-click to rename in place] … [progress bar + %] [⋯ menu].
- Progress color: 0% empty gray track; 1–49% neutral gray fill; 50–99% accent fill; 100% green fill + green % text.
- ⋯ / right-click: Add/Remove Favorite, Rename, Archive/Unarchive, Delete Project… (native confirm: "Delete 'X'? The
  project and its N tasks will be moved to Trash/Recycle Bin." — Delete/Cancel, Cancel default).
- Clicking elsewhere on the row opens the board.
- Create: "+" inserts an inline editable row at the top (not a modal) — colored icon (random start color, clickable) + text
  field; typing shows a live preview of the task-ID prefix ("Task IDs: WEB-1"); Enter commits, Escape cancels, clicking
  away commits if non-empty/changed else cancels.
- Rename works the same in place (double-click or menu).
- New projects are never created archived ("+" hidden on Archived).

### 4.6 Views (`/views`)

- Same row pattern: header with count, inline create (colored stacked-layers icon + name), inline rename, ⋯/right-click:
  Add/Remove from Sidebar, Rename, Delete View… (confirm notes only the view+filters are removed, no tasks affected).
- Right column: filter summary "No filters" / "1 filter" / "N filters" (count of non-empty filter categories).
- Creating a view navigates into it immediately.
- If views.json can't be read: non-blocking warning banner; create/rename/delete disabled until resolved.

### 4.7 Saved view board (`/views/:id`)

Like All Tasks, except filters AND display options (order/direction/layout/visible fields) are saved to the view itself
(auto-save, no Save button), so it looks the same on any synced machine. Search is always session-only, never persisted.

"+ New Task" pre-fills unambiguous defaults from the view's filters: exactly one project → that project; exactly one
status → it; exactly one priority → it; any labels → all of them; due filter "today" or "this week" → due today.

### 4.8 Labels (`/labels`)

- Header dropdown: scope "Workspace" or each non-archived project (remembered; falls back to Workspace if the project was
  deleted/archived).
- Row: [colored dot → color] [name, click to rename in place] … [task count] [⋯ menu].
- "+" row at top to create; dot auto-picks the next unused color in a fixed rotation.
- Delete: native confirm ("Delete 'X'? It will be removed from N tasks. The tasks themselves are not deleted.") then
  strips the label id from every task.
- Workspace labels locked (dimmed, no create/edit/delete) while labels.json can't be read.

### 4.9 Reports (`/reports`) — hidden by default

A filter builder producing a copyable, AI-ready prompt with simplified task data + instructions, to paste into any LLM.
Core differentiator — reproduce exactly.

**UI**: one card of stacked rows `[label] [value chip → dropdown]`:

- **Date range** presets: This Week / Last Week / This Month / Last Month / Last 30 Days / All Time / Custom Range (two
  date pickers). Weeks respect the OS first-day-of-week. "All Time" spans year 1 → 9999 internally but is reported as the
  actual earliest-task-to-today span.
- **Projects** multi-select: All Projects (default) / No Project / each active project / (when "Include archived" is on) an
  "Archived" sub-section. Toggle "Include archived" — turning it off drops selected archived projects.
- **Labels** multi-select scoped to the Projects filter: workspace labels always; project labels only for included
  projects (All Projects → every active project's, or every project's with archived on; specific projects → theirs;
  "No Project" alone → workspace only). Grouped: "Workspace" first, then one heading per included project, alphabetical
  within groups, skip projects with zero labels. Changing Projects drops out-of-scope selected labels.
- **Status** multi-select (4). **Priority** multi-select (5).
- **Tasks** — live count ("24 tasks will be included" / "No tasks match. Try a wider date range or fewer filters.") + a Copy
  button with dropdown: Report Prompt, Summary Prompt, JSON Only.

**In range** — a task qualifies if ANY overlaps the range: it was open at some point (created on/before range end, and not
completed or completed on/after range start); OR completed within the range; OR start date in range; OR due date in range.

**Exported JSON** is simplified for an LLM that's never seen the app: no raw UUIDs; projects/labels/statuses/priorities by
human name (same-named projects disambiguated with their key in parentheses only when needed); dates as `YYYY-MM-DD`;
every empty/unset/zero/not-applicable field omitted (no null/0/[]); active filters listed once under `report.filters`,
otherwise omitted.

```json
{
  "report": { "today": "...", "period": { "from": "...", "to": "...", "name": "This Week" },
              "filters": {}, "includesArchivedProjects": false },
  "totals": {
    "tasks": 24, "completedInPeriod": 10, "createdInPeriod": 6, "dueInPeriod": 8,
    "openAtPeriodEnd": 9, "completedAfterPeriod": 2, "openNow": 11, "overdueNow": 3,
    "averageDaysToCompleteInPeriod": 4.5,
    "byStatusNow": {"Todo": 5, "In Progress": 3, "Done": 10},
    "byPriority": {"Urgent": 2, "High": 4},
    "byLabel": {"Bug": 6}
  },
  "timeline": { "months": [], "weeks": [] },
  "projects": [{
    "name": "Website Redesign", "key": "WEB", "archived": false,
    "totals": {"tasks": 12, "completedInPeriod": 5, "openAtPeriodEnd": 4, "openNow": 7, "overdueNow": 1},
    "tasks": [{
      "title": "...", "description": "...",
      "atPeriodEnd": "done | open | not created yet",
      "inPeriod": ["created", "started", "due", "completed"],
      "statusNow": "Done", "priority": "High", "labels": ["Bug"],
      "startDate": "...", "dueDate": "...", "created": "...", "completed": "...",
      "daysToComplete": 4, "overdueNowByDays": 3
    }]
  }]
}
```

`timeline.months` only when the span covers more than ~45 days; `timeline.weeks` only when the span is ~10–130 days.
Each bucket `{label, created, completed, due, openAtEnd}`, clipped to the report span. Totals are pre-computed (and the
prompt says so).

**Prompt text** (two variants, both end with the JSON in a fenced code block), in order:

1. One sentence introducing the data and period.
2. "How to read the data": report.today/report.period; the in-range rule; atPeriodEnd/inPeriod (status during the period)
   vs statusNow (today, may differ); totals are pre-computed, use as-is; (if timeline) how to read it; (if filters) that
   they're listed and unrestricted fields aren't filtered.
3. Writing rules: for someone who's never seen this data, plain language, never expose internal field names or raw
   JSON/dates like 2026-09-12 in prose (write "Sep 12"), factual, never invent numbers.
4. "Visuals first": if the AI can render charts/artifacts lead with them; else Mermaid pie/bar charts; else ASCII bars.
5. The ask:
   - **Summary Prompt**: one short visual, 1–2 sentences on overall progress, 4–7 bullets on what matters most (notable
     completions, in-flight work, overdue/at-risk, standout projects), one sentence on the trend if a timeline exists, a
     note on post-period completions if any; under 200 words, no headings/tables.
   - **Report Prompt**: full Markdown report — title, visuals, numbered sections: Overview; Key numbers table;
     (Month-by-month or Week-by-week breakdown, with a mini weekly breakdown for busy months, if timeline); Completed in
     the period (grouped by project if >1); Still open at period end; Risks & blockers (today's overdue/urgent items and
     why they matter); By project (if >1); By label (if labels used); Next steps (3–6 concrete recommendations). Empty
     sections literally say "None."
   - **JSON Only**: raw JSON, no prose.

Copying shows a toast naming what was copied and how many tasks it covers.

## 5. Board / List layout, sorting, display options

### 5.1 Kanban board

- Exactly 4 min-width, flex-fill columns: Backlog, Todo, In Progress, Done.
- Column header: status icon, label, count ("Backlog 2"), small "+" button.
- Cards follow one of 5 orders (§5.3); drag-reorder when order is Manual.
- **Manual order** uses float `sortOrder`: dropping between two cards = midpoint of neighbors; at an end = neighbor ±1000.
  Ties → `createdAt` desc.
- Dropping into a different column always changes status (any order); in Manual it also positions at the drop point; in
  non-Manual it lands at the top.
- Dropping within the same column in non-Manual order does nothing; while dragging over a non-Manual column show an
  overlay "Ordered by X" / "Sorted by most recent" instead of a drop line, and when over another column highlight it and
  say "Move to `<Status>`".
- **Done is a log**: in Manual order it shows most-recently-completed first (completedAt, fallback updatedAt, then
  updatedAt, then manual order), labeled "Recent first". If the user picks another order, it applies to Done too.
- "+" buttons: always visible when a column is empty; otherwise on hover (bottom) or always at the header. Opens New Task
  pre-filled with that status (and project, inside a project).
- Columns scroll vertically independently; the board scrolls horizontally if needed; columns are virtualized.
- **Drag physics** (feel, not exact implementation):
  - Pick-up: lift with ~1.5° tilt, ~1.03 scale, soft shadow, ~150ms strong ease-out; then follows the pointer exactly.
  - One thin accent line shows the landing spot and glides between positions.
  - Near column top/bottom (or board left/right) edges → auto-scroll, faster closer to the edge.
  - Release → ~240ms settle at the release point, un-tilt/un-scale; other cards FLIP-slide to fill gaps whenever the list
    changes.
  - Escape mid-drag cancels and flies the card back.
  - Respect OS reduce-motion: skip ghost/tilt/FLIP, apply changes instantly.
  - A plain click (no meaningful movement) opens the detail panel; clicking a chip button inside a card never starts a
    drag or opens the task.

### 5.2 List layout

- Same tasks in 4 collapsible status sections, each with a sticky header (next header slides over the previous).
- Section header: label, count, chevron (collapse state remembered per board), "+" (visible when empty, else on hover).
- Row: optional priority icon, optional status icon, optional ID, one-line title, then right-aligned optional date pill,
  labels, project (hidden if none / on single-project boards).
- Virtualized. Right-click = card context menu (§7.3). Open-in-panel highlight.

### 5.3 Display options ("sliders" toolbar button)

- **Order**: Manual / Priority / Due Date / Updated / Newest.
- **Direction**: Asc / Desc — disabled for Manual. Defaults when picked: Priority asc (urgent first), Due asc (soonest),
  Updated desc, Newest desc.
- **Sections**: "Hide Empty Sections" (board columns and list sections).
- **Properties**: Task ID, Status Icon, Priority, Start Date, Due Date, Labels, Project (Project only on cross-project
  boards).
- **Reset to Default** (disabled when already default).
- A separate "View" toggle in the toolbar switches Board ⇄ List.

**Sort rules** (board columns and list sections identically):

- Manual: `sortOrder` asc, tie `createdAt` desc.
- Priority: rank Urgent(1) < High(2) < Medium(3) < Low(4); None always sorts last regardless of direction (the direction
  applies to the ranks of prioritized tasks only). Tie `sortOrder`. *(The source spec suggested "rank None as 5, then
  apply the direction sign", which would float None to the top when descending and contradicts "always last" — the
  explicit "always last" rule wins.)*
- Due Date: `dueDate`, falling back to `startDate`; tasks with neither always sink to the bottom regardless of
  direction. Tie priority rank, then `sortOrder`.
- Updated / Newest: `updatedAt` / `createdAt` with direction applied directly; tie `sortOrder`.
- Every comparator fully deterministic (no two tasks ever compare equal).

Display options and layout persist per board: "All Tasks", each project, "Today" (own defaults — list layout, no
priority/start-date columns), and each saved View (synced via the view, §4.7). Filters persist only for the session,
per board, except saved Views (filters saved to the view; search still session-only).

## 6. Filtering & search

"Filter" button menu with submenus:

- **Status** — multi-select (4).
- **Priority** — multi-select (5), divider after "None".
- **Project** (cross-project boards only) — "All Projects" (default/reset), OR "No Project" alone, OR one or more real
  projects. Picking a real project clears "No Project" and vice versa (not independent checkboxes).
- **Label** — "No Label" (zero labels) plus every available label (project-scoped first, then workspace, visually
  separated); on cross-project boards project labels are suffixed with the project name.
- **Due Date** — Overdue (past due AND not done), Due Today, Due in Next 7 Days (today + 6, inclusive), No Due Date.
- "Clear Filters" at bottom, disabled when nothing active.

Logic: OR within a category, AND across categories; an empty category doesn't filter.

**Search**: icon toggles an inline field ("Search title, ID, description"); case-insensitive; every typed word must
appear somewhere in ID+title+description (order-independent AND). Escape or clearing collapses it. Never saved.
**Ctrl+F** (⌘F on macOS) opens/focuses the current board's search; on pages without a board, navigate to All Tasks and
open search there.

**Stale filter cleanup**: filter values referencing archived/deleted projects or labels are silently dropped.

## 7. Task detail panel, creation dialog, and context menu

### 7.1 New Task dialog (modal, distinct from editing)

- ~700px wide. Breadcrumb header: [project icon] KEY › New Task (or just "New Task" with no project).
- Borderless bold title input over a borderless multi-line description ("Task title" / "Add a description…").
- Chip row matching the card chips (status, priority, start, due, labels, project), each with an in-place picker.
- Footer: "Create more" toggle (on submit, clear title/description and keep open; restore due date and labels to the
  dialog's opening values; keep status/priority/project as last entered) + primary "Create Task" (disabled while title
  empty). Ctrl+Enter submits.
- Changing project drops labels invalid for the new project.
- Closing with typed text (Escape, ✕, click outside) → native confirm "Discard this task? / What you've typed will be
  lost." — Discard / Keep Editing (default).
- Project list: "No Project" at top, every active project, plus the archived project whose board opened the dialog.

### 7.2 Task detail panel (right-side sheet, not a dialog)

- Slides in from the right, full height minus a small margin, ~580px wide, over a dimmed backdrop.
- Header: task ID, right-aligned trash icon (immediate delete with Undo, §7.4) and close ✕.
- Top band (fixed): the chip row, editable in place.
- Middle band (scrolls): large borderless auto-growing title (Enter moves to description) + auto-growing description
  (real newlines).
- Bottom band (fixed): muted "Created [long date] · Completed [long date]" (Completed only if done).
- Autosave: title/description ~500ms after typing pauses AND immediately on blur/close; chips save instantly. An empty
  title reverts to the last saved value on leaving the field.
- If the task is deleted (here or via sync) while open, the panel closes.
- Opening another task replaces the panel's content (no stacking).
- Closing returns focus to the originating card/row.

### 7.3 Context menu (cards, list rows, Dashboard rows — identical)

1. Open
2. —
3. Status ▸ (4, checkable)
4. Priority ▸ (5, checkable, divider after None)
5. Due Date ▸ Today / Tomorrow / Next Week (always next Monday, independent of the OS first-day-of-week), each with a
   muted weekday/date hint and a checkmark if current; — ; Remove Due Date (disabled if none)
6. Labels ▸ every available label, checkable (disabled if none available)
7. Move to Project ▸ "No Project", every active project (+ the task's own project even if archived), checkable
8. —
9. Duplicate — same project/status/priority/dates/labels, not completion/history, lands at the top of its status; Undo
   toast "Duplicated as KEY-N"
10. Copy ID — copies "WEB-12", confirmation toast
11. —
12. Delete — immediate, shows its shortcut hint, red

Actions not visually obvious from the trigger point (status, priority, due, label toggle, move) show a brief Undo toast
("WEB-12 moved to Done", "WEB-12 due next week", "Added label Bug") whose Undo restores the exact prior state — undoing
a move to Done restores the previous `completedAt` if any; undoing a project move restores the original number in the
original project if still free. Only one Undo toast at a time (new replaces old).

### 7.4 Deleting tasks

No confirmation, ever: instant delete + 8-second "Deleted KEY-N — Undo" toast, from the context menu, panel trash icon,
keyboard shortcut, or menu bar Delete. (Projects, labels, and views DO confirm.)

## 8. Visual design system

Translate the Linear-inspired look into a clean platform-appropriate equivalent (no faked chrome; Mica/Acrylic only if
natural), preserving:

### 8.1 Typography & density

Body 12px; section headers/titles ~13px semibold; page titles ~13–14px semibold; meta (counts, dates, IDs) 11–12px muted.
List rows ~36–40px; generous horizontal padding (8–12px). Three text tones — primary, secondary (~60%), tertiary (~40%):
unselected sidebar = secondary, selected = primary, section headers = secondary, counts/meta = tertiary.

### 8.2 Palette

8 named colors: blue, purple, green, orange, red, yellow, magenta, neutral (neutral = plain gray, deliberate "no color",
never auto-assigned). Accent/brand = blue for selection, primary buttons, and the Done icon.

### 8.3 Status icons (14px)

Backlog: dashed outline circle, muted gray. Todo: solid outline circle, muted gray. In Progress: outline circle half
filled, yellow/orange. Done: filled circle with white checkmark cut out, accent blue.

### 8.4 Priority icons (14px, bar-chart style)

None: three short horizontal dashes, very muted. Urgent: filled rounded square with cut-out exclamation, orange.
High/Medium/Low: three ascending vertical bars with 3/2/1 filled, rest at ~25% opacity.

### 8.5 Chips

One shared shell everywhere: rounded 24px-tall pill, hairline border, small icon + small text, secondary text color,
subtle hover. Project = cube glyph tinted; view = stacked-layers glyph tinted; label = solid dot + name; multiple labels
→ up to 3 overlapping dots + "N labels".

### 8.6 Cards

Rounded rectangle, thin border, subtle elevation. Top-to-bottom: optional ID line; status icon + title (2-line clamp,
tooltip); one non-wrapping row of enabled chips (priority, a combined date pill "Oct 3 → Oct 10" / "Oct 3 →" / "Oct 10",
collapsing when start=due, labels, project last). Open-in-panel card gets a distinct subtle background. While dragging,
the origin slot shows a dashed-outline placeholder.

### 8.7 Empty states & loading

- No folder → onboarding (§10).
- Loading → after ~300ms, spinner + "Opening your workspace… Reading your projects [from the cloud, this can take a moment
  while files download]."
- Zero tasks → "No tasks yet" + "+ New Task". Tasks but none match → "No matching tasks" + "Clear Filters".
- Empty Projects/Views/Labels → explain how to create one.
- Load error → clear message + "Choose Folder…" and "Try Again".

## 9. Live-updating behavior

- Relative labels (Today/Yesterday/Tomorrow), overdue/today color cues, Today page, Dashboard greeting/date, and any
  due-date-based sort/filter re-evaluate on a ~30s timer and immediately on window focus / OS wake, so midnight flips
  everything without restart.
- Focus regain / wake re-reads the data folder — skipped while any save from this instance is in flight. Track "N saves in
  flight"; refresh is a no-op while N > 0; only the last outstanding save's result is applied.
- Watch the folder for external changes and refresh (debounced a few hundred ms), ignoring events caused by the app's own
  recent writes.

## 10. Onboarding (no folder chosen)

Centered "Welcome to Tasklet" + explanation (local files in a folder you choose; a synced folder syncs across machines).
Two buttons: primary "Choose Existing Folder…" (native folder picker) and secondary "Create New Folder…" (name and place a
new folder). No demo data, ever. Both show "Opening…"/"Creating…" busy states and disable each other while a dialog is open.

## 11. Settings window

Separate 520×440 fixed, non-resizable, tabbed window: General, Sidebar, Notifications, Data. Each tab scrolls independently.

### 11.1 General
Theme Auto/Light/Dark (Auto follows OS live). Your Name (saved on blur; feeds the greeting). "Show Release Notes"
reopens What's New in the main window (bringing it to front), even after the sidebar entry was dismissed.

### 11.2 Sidebar
§3.5.

### 11.3 Notifications (due-date reminders)
- On/off (default on). Remind Me At (default 09:00, disabled when off). Include Overdue Tasks (default on). Remind the Day
  Before (default off). "Send Test Notification" fires today's real content now; if nothing is due, shows "Reminders are
  on / Nothing's due right now. You'll get a summary at `<time>` when something is."
- If the OS blocks notifications, show an inline "Notifications Are Off…" row with a button opening the OS notification
  settings for the app.
- Rules: exactly one notification per calendar day at the configured time, across restarts (persist last sent day); if
  missed (app not running / asleep) send at the next check after that time.
- Content: one matching task → title "Due Today" / "Overdue" / "Due Tomorrow", body = task title. Several → title leads
  with the most urgent group ("N tasks due today", else "N overdue tasks", else "N tasks due tomorrow"); if other groups
  exist add one body line "Plus 2 overdue and 1 due tomorrow." (omitted when only one group).
- Click single → open that task's panel (bringing/creating the main window). Click summary → Today if it included
  due-today/overdue, else All Tasks.
- Turning on / changing the time to an already-passed time today waits until tomorrow (only Test bypasses).
- Only open tasks in non-archived projects (incl. No-Project) with a due date.

### 11.4 Data
Full data-folder path (+ "(Synced)" annotation if inside a known cloud-sync location), "Show in Folder", "Change…"
(re-pick; re-points the whole app).

## 12. Keyboard shortcuts & menu bar

Standard menu bar (File/Edit/View/Go/Window/Help) with accelerators (Ctrl on Windows, ⌘ on macOS):

| Action | Shortcut |
|---|---|
| New Task | Ctrl+N |
| New Project… | Ctrl+Shift+N |
| Find / search current board | Ctrl+F |
| Delete selected/focused/open task | Delete or Ctrl+Backspace |
| Go to Dashboard…Reports (sidebar order) | Ctrl+1 … Ctrl+7 |

- Ctrl+N while the New Task dialog is open is a no-op.
- Delete fires only when a card/row has focus or the detail panel is open — never while typing in a field or when another
  dialog/menu is open.
- Commands triggered from outside the main window (notification click, Settings' "Show Release Notes") bring the main
  window to front, creating it if needed; if freshly created, queue the command until it finishes loading.

## 13. What's New

- Dialog shown once automatically after an update introduces new notes (and via the sidebar footer while unread,
  Settings → General, or Help menu).
- Style: generous ~40px horizontal margins, large centered bold title + "Month Year Update" subtitle, one flowing list of
  feature rows (accent icon ~20px + bold short title + 1–2 lines of description, icons centered on the title baseline),
  then a final small checklist-style "Fixes and polish" entry.
- Overflow scrolls internally; a "More ↓" affordance above the primary button (space reserved) plus a bottom fade, both
  disappearing at the end; "More" smooth-scrolls ~3/4 page.
- Full-width "Continue". Any dismissal marks the release read (per machine).
- Opening/closing must not disturb the sidebar scroll position (guard focus-driven scroll on return).

## 14. Non-goals

No accounts/login/server/telemetry. No collaboration (assignees, comments, mentions). No sub-tasks, recurring tasks, or
calendar view. No in-app AI calls (Reports only generates text). No built-in network sync — sync is purely the user's
third-party folder sync.

## 15. Implementation notes (Flutter)

- Storage: native folder dialogs; `dart:io` with temp-file-then-rename; filesystem watcher with polling fallback.
- State: any mature solution — the "N saves in flight, last response wins" discipline is what matters.
- Drag & drop / animations: custom pointer handling + AnimationControllers/Transforms for lift/tilt/ghost/FLIP.
- Notifications: must fire while the main window is minimized/closed, with click routing.
- Virtualized lists for columns and list sections.
- Routes: `/`, `/today`, `/my-tasks`, `/projects`, `/projects/:id`, `/views`, `/views/:id`, `/labels`, `/reports`.
- Build order: data + storage + onboarding → shell + routing → Projects/Labels → board + list + sort/filter → task
  dialog, panel, context menu, Undo → Views → Dashboard + Today → Settings + reminders → Reports → What's New + shortcuts.
