# Roadmap

Each milestone is done when `flutter analyze` is clean, `flutter test` passes, and the app launches on Windows with the
milestone's behavior working. Section numbers refer to [SPEC.md](SPEC.md).

## v1, Windows + macOS

- [x] **0. Repo & tooling**: scaffold, MIT license, docs, lint config, CI, project skills
- [x] **1. Core + storage**: models with unknown-field round-trip, project keys (§2.4), dates, sorting (§5.3),
      filters (§6), ordering (§5.1); workspace store with atomic writes, unreadable/conflict/missing-folder rules (§2.5),
      lazy No-Project (§2.3); save queue; folder watcher; device prefs
- [x] **2. Shell**: onboarding (§10), loading/error states (§8.7), sidebar (§3), routing, theme (§8)
- [x] **3. Projects / Labels / Views pages** (§4.5, §4.6, §4.8)
- [x] **4. Board + List + sort/filter/search** (§5, §6) incl. drag physics and virtualization
- [x] **5. Task dialog, detail panel, context menu, Undo** (§7)
- [x] **6. Saved views** (§4.7)
- [x] **7. Dashboard + Today** (§4.1, §4.2, §9)
- [x] **8. Settings window + reminders + tray/lifecycle** (§11, §12)
- [x] **9. Reports** (§4.9)
- [x] **10. What's New + menu bar + shortcuts + accessibility pass** (§12, §13)
- [ ] **11. macOS hardening**: PlatformMenuBar, notification permission, dock reopen, signing/notarization

## v1.1, released November 2026

- [x] **Workspaces**: one data folder each, switcher, Workspace menu, Ctrl+Alt+1 … 9, Settings tab, move a
      project between workspaces, export and import (DECISIONS D15)
- [x] **Icons and 16 colors** for projects, labels and quick filters (D14)
- [x] **Starter content** in new workspaces: labels, quick filters, and a sample project in the first (D16)
- [x] **Merging edits from two computers**, local backups and Restore Previous Version (D12, D13)
- [x] **Performance**: incremental reads, patched boards, faster search, dashboard and reports at 100k tasks
      ([PERFORMANCE.md](PERFORMANCE.md))

## Next

- [ ] Smoother dragging, searchable pickers and a frame-time test
- [ ] Stress runs at 100,000 and 500,000 tasks; Help → Export Diagnostics
- [ ] Code-signed Windows installer; macOS release (milestone 11)

## Phase 2, iOS + Android

Reuse `lib/core/` and `lib/state/` unchanged. Adaptive shell (drawer sidebar, full-screen detail, Settings as a page,
long-press menus). Storage: iOS iCloud container / Files picker with security-scoped bookmarks; Android Storage Access
Framework, only `lib/data/` changes.
