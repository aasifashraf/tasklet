# Tasklet design system

Calm, dense, keyboard-first desktop UI in the spirit of Linear: neutral surfaces, hairline borders, one accent, color
only where it carries meaning. The product rules are in [SPEC.md §8](SPEC.md); this page is the working reference
for contributors. Tokens live in [`lib/ui/theme.dart`](../lib/ui/theme.dart); shared widgets in
[`lib/ui/widgets.dart`](../lib/ui/widgets.dart).

## Color

Read with `Tokens.of(context)`. Never write `Color(0x…)` outside `theme.dart` (a test enforces this).

| Token | Use |
|---|---|
| `background`, `sidebar`, `surface`, `raised` | page, sidebar, panels/columns, cards and popovers |
| `border` | every 1px hairline |
| `hover`, `selected`, `openHighlight` | interaction states (translucent, so they work on any surface) |
| `primary` | titles and body text |
| `secondary` | supporting text, sidebar labels, chip text |
| `tertiary` | meta text, placeholders, idle icons, disabled items |
| `accent`, `onAccent` | the one action color (#3570EA): primary buttons, focus, Done; `onAccent` is the text on it (white, 4.5:1) |
| `danger`, `warning`, `success` | destructive actions, warnings, confirmations |
| `named(TaskletColor)` | the 16 user colors for projects, labels, quick filters and workspaces: glyphs, dots and fills, never body text; each reaches 3:1 on every surface (darker shades in the light theme where needed) |

**Contrast floors** (checked by `test/ui/design_system_test.dart` on every surface, both themes): primary ≥ 7:1,
secondary ≥ 4.5:1, tertiary ≥ 3:1. Use tertiary only for text that is not needed to understand the screen.

## Type

`TextStyles` only; no raw `fontSize`. 12 px body is the default everywhere.

| Style | Size / weight | Use |
|---|---|---|
| `meta` | 11 / regular, tertiary | counts, dates, IDs, hints |
| `body`, `bodySecondary` | 12 / regular | almost everything |
| `sectionLabel` | 12 / 500, secondary | sidebar and list section headers |
| `section` | 13 / 600 | column headers, dialog section titles |
| `pageTitle` | 14 / 600 | page and dialog titles |

## Shape and size

These are the values in use; new code picks from them (a token group is planned, see TODO).

- **Radius:** 6 for buttons and controls, 8 for cards, rows and panels, 12 for the chip/pill shell.
- **Heights:** chip 24, compact control 26, sidebar row 30, button 30, list row 38.
- **Icons:** 12 (inline meta), 14 (default), 16 (emphasis), painted glyphs in `glyphs.dart` for status/priority.
  Projects, labels, quick filters and workspaces show a user-picked Lucide icon (catalog in `lib/ui/icons/`,
  generated from `tool/icons/catalog.txt`) or their default glyph (cube, dot, funnel). Always draw them with
  `ProjectGlyph`, `LabelGlyph`, `ViewGlyph` or `WorkspaceGlyph`, never a raw icon.
- **Spacing:** multiples of 4 (4, 8, 12, 16, 24); 6 is allowed for tight icon-to-label gaps.
- **Borders:** always 1px `border`; no shadows on resting elements in dark mode.
- **Motion:** 120 ms for hover/fades, 200 ms for panels and drops, `Curves.easeOutCubic`. Respect
  `MediaQuery.disableAnimations`.

## Components

Reuse before building: `PropChip` (the single 24 px chip shell for every property), `IconBtn` (icon-only button,
always with a tooltip), `PillToggle`, `menuItem`, `IconPickerButton` / `iconMenuItem` / `showIconPicker` (icon and
color), `ListRowShell`, `PageScaffold`, `EmptyState`, `NoticeBanner`, `confirmDestructive`. A second implementation of
any of these is a bug.

States every interactive element needs: hover, selected (if applicable), disabled (tertiary text, no hover),
**keyboard focus**, and a tooltip or label for screen readers. `Pressable` (widgets.dart) gives all of them at once:
Tab focus with a 2 px accent ring (keyboard only, following the shape's radius), Enter/Space, the click cursor, button
semantics with enabled/selected, and a `hovered` flag that is also true while keyboard focus is on or inside it, so
hover-only affordances (a row's ⋯) appear for keyboard users. Build every clickable shell on it; `Hoverable` is only
for hover effects on things that aren't buttons. A shell with no action (a read-only chip, a row being renamed) is
not wrapped, so it isn't announced as a button.

## Writing

- Title Case for buttons, menu items and page titles ("New Quick Filter", "Copy to Clipboard"); sentence case for
  descriptions, hints and messages.
- An item that opens a dialog ends with the ellipsis character ("Delete Project…"), never three dots.
- No em dashes anywhere in the app or docs; use a colon, comma or "to".
- Say what happened and what to do: "Couldn't save your change: the folder is offline."

## Layout robustness

- Every text that shows user data (names, titles) has `maxLines` and `TextOverflow.ellipsis`.
- Lists of user data are lazy (`ListView.builder` / slivers).
- Must work at the 900×600 minimum window, in the fixed 520×440 Settings window, and at 125% OS text scaling.
