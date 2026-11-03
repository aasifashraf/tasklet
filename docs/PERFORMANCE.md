# Performance baselines

How to measure (details and targets: [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md) sections 5 and 17):

```sh
python -I tool/bench/generate.py <scratch dir> 100000
dart tool/bench/bench.dart <scratch dir>
```

`generate.py` builds 200 projects (the largest with 20% of the tasks), short descriptions on 30% of tasks and 4 KB
on 1%, 200 labels, with a fixed seed. `bench.dart` runs the app's real store and core code and reports p50 / p95
time and the longest **UI stall** (how long the UI thread would have been frozen). Widget build and paint are not
included. Run on an idle machine; open times vary with the disk cache, so compare them within one session.

A > 2x regression on any row blocks a release.

## 100,000 tasks: Ryzen 7 7735HS, NVMe, Windows 11

| Operation | Before v1.1 (Nov 2, 2026) | Now | Target |
|---|---|---|---|
| Open (first read) | 2.2-5.2 s, stall 173-208 ms | unchanged | < 3 s |
| **Refresh, nothing changed** | **190-216 ms, stall 173-196 ms** | **58-62 ms, stall at the meter's floor (Nov 3)** | < 50 ms |
| All Tasks board: filter + group + sort | 117-150 / 135-173 ms | 171 / 213 ms, now only when filters, search, sort or day change | p95 < 50 ms |
| **All Tasks board after an edit** | **same full recompute** | **20 / 54 ms including the edit itself (patched)** | p95 < 50 ms |
| Largest project board (20k tasks) | 7-11 / 15-23 ms | unchanged | p95 < 50 ms |
| **Search, next keystroke** | **144-174 / 162-203 ms** | **63-95 / 66-104 ms; typing more of a query 30 / 36 ms** | p95 < 100 ms |
| **Dashboard aggregates** | **966-1,241 / 1,014-1,316 ms, every 30 s** | **56-59 / 74-93 ms, only when data, day or filter change** | p95 < 30 ms |
| **Reports: tasks in a period** | **1,091 / 1,166 ms** | **13 / 28 ms** | p95 < 50 ms |
| Sidebar counts | 7-9 / 16-19 ms on every sidebar rebuild | same cost, only when data, day or rules change | |
| Label usage map | 30-39 / 49-61 ms | unchanged | |
| Edit one task (in memory) | 3-4 / 14-20 ms | unchanged | |
| **Save largest project (20k tasks)** | **442-571 / 543-728 ms, stall 116-145 ms** | **377-413 / 484-499 ms, stall 42-63 ms (sliced encode, Nov 3)** | stall < 16 ms |
| Save typical project | 14 ms | unchanged | |
| Peak memory | 437-457 MB | unchanged | < 600 MB |

Saving a big project (Nov 3, 2026): the encode isolate had to receive a copy of the whole 20k-task project (40-80 ms
on the UI isolate) and the 44 MB result was UTF-8 encoded and written in one go (~80 ms). Now the project is encoded
250 tasks at a time on the UI isolate with a pause between slices (byte-identical output,
`test/data/sliced_encode_test.dart`), kept as parts and written 1 MB at a time. What is left of the stall is garbage
collection on the ~380 MB heap, not encoding work; note that the 1 ms stall meter can't resolve below the ~15.6 ms
Windows timer tick.

Phase 3 also stopped every visible card from rebuilding when a task panel opens or anything else in the workspace
changes (cards watch only their own labels and open state), and boards nobody shows are released from memory.

Phase 6: after an edit, a board takes the tasks that changed (`diffTasks`, ~5 ms) and moves just those to their
sorted places (`patchGroups`, under 1 ms) instead of filtering and sorting every task again. A project-level change
(rename, archive, labels), more than 200 changed tasks, or a new filter, search, sort or day still recomputes in full.

Search keeps each task's lowercased text on the task itself (no lookup table) and checks words against the task
ID without building the ID string. When a new query only adds to the last one (every old word is part of a new
word), the board filters its last result, which is already grouped and sorted. Matching stays exact: no
description cap and no ranking, so a search finds the same tasks as before. Search runs synchronously after the
200 ms debounce, so there are no stale results to drop; an isolate is only worth it if a query stays over 50 ms.

Earlier measurements at 10k and 500k tasks: [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md) section 3.

At 500k tasks (Nov 3, 2026, after the changes above): refresh with nothing changed 59-63 ms with no UI stall (it
was about 1 s; the cause was the sync repair pass running on every read, not garbage collection), first open 14.6 s
with a 1.1 s stall (the repair pass has to run once), saving the 100k-task project 2.2 s with a 213 ms stall
(garbage collection on a 920 MB heap), peak memory 920 MB. Those last three are past the v2 triggers (SQLite read
index, chunked project files); nothing more is planned for them in v1.
