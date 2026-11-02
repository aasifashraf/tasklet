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

| Operation | Before v1.1 (Nov 2, 2026) | After phase 3 | Target |
|---|---|---|---|
| Open (first read) | 2.2-5.2 s, stall 173-208 ms | unchanged | < 3 s |
| Refresh, nothing changed | 190-216 ms, stall 173-196 ms | unchanged (phase 2 profiling) | < 50 ms |
| All Tasks board: filter + group + sort | 117-150 / 135-173 ms | unchanged (phase 6) | p95 < 50 ms |
| Largest project board (20k tasks) | 7-11 / 15-23 ms | unchanged | p95 < 50 ms |
| Search, next keystroke | 144-174 / 162-203 ms | unchanged (phase 6) | p95 < 100 ms |
| **Dashboard aggregates** | **966-1,241 / 1,014-1,316 ms, every 30 s** | **56-59 / 74-93 ms, only when data, day or filter change** | p95 < 30 ms |
| **Reports: tasks in a period** | **1,091 / 1,166 ms** | **13 / 28 ms** | p95 < 50 ms |
| Sidebar counts | 7-9 / 16-19 ms on every sidebar rebuild | same cost, only when data, day or rules change | |
| Label usage map | 30-39 / 49-61 ms | unchanged | |
| Edit one task (in memory) | 3-4 / 14-20 ms | unchanged | |
| Save largest project (20k tasks) | 442-571 / 543-728 ms, stall 116-145 ms | unchanged (phase 5/7) | stall < 16 ms |
| Save typical project | 14 ms | unchanged | |
| Peak memory | 437-457 MB | unchanged | < 600 MB |

Phase 3 also stopped every visible card from rebuilding when a task panel opens or anything else in the workspace
changes (cards watch only their own labels and open state), and boards nobody shows are released from memory.

Earlier measurements at 10k and 500k tasks: [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md) section 3.
