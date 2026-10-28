# Tasklet

A calm, keyboard-first, local-first task tracker for one person.

Tasklet keeps your tasks, projects, labels, and saved views as plain JSON files in a folder you choose. Put that folder
in OneDrive, Dropbox, Google Drive, iCloud Drive, or Syncthing and your tasks follow you between machines — no account,
no server, no telemetry.

> **Status:** early development. v1 targets **Windows and macOS**; iOS and Android come next.

## Features (v1 scope)

- Kanban board or list, with manual drag ordering, sorting, filters, and search
- Today page, Dashboard, projects, labels, saved views, favorites, archive
- Linear-style task IDs (`WEB-12`) that stay stable forever
- Keyboard shortcuts, full right-click menu, quick due dates, Undo for every task action
- Optional daily due-date reminder
- Reports: filter tasks by period/project/status and copy an AI-ready prompt or JSON for any LLM (Tasklet never calls an
  AI service itself)

The full behavior spec lives in [docs/SPEC.md](docs/SPEC.md).

## Your data

```text
<your folder>/
  tasklet-workspace.json
  labels.json
  views.json
  projects/<project-id>.json
```

Files are written atomically (temp file + rename), unreadable or mid-sync files are never overwritten, sync-conflict
copies are left untouched, and fields written by newer versions are preserved.

## Building

Requires Flutter (stable, 3.47+).

```sh
flutter pub get
flutter run -d windows   # or: -d macos
flutter test
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
