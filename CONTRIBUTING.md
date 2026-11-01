# Contributing to Tasklet

Thanks for helping! Tasklet aims to be a faithful implementation of [docs/SPEC.md](docs/SPEC.md) — when behavior is in
question, the spec decides. If you think the spec is wrong, open an issue proposing a change to it first. Choices made where the spec is silent
are recorded in [docs/DECISIONS.md](docs/DECISIONS.md).

## Ground rules

- **Never risk user data.** Anything touching `lib/data/` must keep the storage guarantees in SPEC §2.5 (atomic writes,
  unreadable ≠ missing, conflict copies untouched, unknown fields preserved). Add a test for every storage change.
- **`lib/core/` is pure Dart** — no `package:flutter` imports. Business rules (keys, sorting, filters, reports,
  reminders, date math) live there and are unit-tested. The mobile apps will reuse it unchanged.
- **No `DateTime.now()` in UI or core logic** — take time from the clock provider / a parameter so midnight rollover
  works and tests can inject time.
- Keep the UI calm and dense (SPEC §8). Use the shared chip, glyph, and empty-state widgets instead of one-offs.

## Workflow

```sh
flutter pub get
flutter analyze        # must be clean
flutter test           # must pass
flutter run -d windows # or -d macos
```

1. Fork, branch from `main`.
2. Keep pull requests focused; reference the SPEC section you implemented or changed.
3. Include tests for logic changes and screenshots for UI changes.
4. CI (analyze, test, Windows and macOS builds) must be green.

By contributing you agree your contributions are licensed under the [MIT License](LICENSE).
