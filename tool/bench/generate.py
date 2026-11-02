"""Benchmark workspace generator: python -I tool/bench/generate.py <out_dir> <total_tasks>
Realistic shape: 200 projects, one holding 20% of the tasks, ~120-byte descriptions on 30% of tasks, 1% with 4 KB.
Valid keys are pre-assigned so the first read measures loading, not key repair."""
import json, os, random, sys, uuid
from datetime import datetime, timedelta, timezone

random.seed(11)
out, total = sys.argv[1], int(sys.argv[2])
os.makedirs(os.path.join(out, "projects"), exist_ok=True)
now = datetime(2026, 11, 1, 12, tzinfo=timezone.utc)
iso = lambda d: d.strftime("%Y-%m-%dT%H:%M:%S.000Z")
W = "fix add update refactor design ship review migrate test deploy audit polish write plan research cache index".split()
COLORS = ["neutral", "red", "orange", "yellow", "green", "blue", "purple", "magenta"]
STATUS = ["backlog", "todo", "in_progress", "done"]
json.dump({"app": "tasklet", "formatVersion": 1}, open(os.path.join(out, "tasklet-workspace.json"), "w"))
labels = [{"id": str(uuid.uuid4()), "name": f"label-{i}", "color": random.choice(COLORS)} for i in range(200)]
json.dump(labels, open(os.path.join(out, "labels.json"), "w"))
lids = [l["id"] for l in labels]
json.dump([], open(os.path.join(out, "views.json"), "w"))

projects = 200
sizes = [total // 5] + [(total - total // 5) // (projects - 1)] * (projects - 1)
for i, size in enumerate(sizes):
    tasks = []
    for n in range(1, size + 1):
        c = now - timedelta(days=random.randint(0, 700), minutes=random.randint(0, 1440))
        st = random.choice(STATUS)
        r = random.random()
        desc = ("x" * 4000) if r < 0.01 else (" ".join(random.choice(W) for _ in range(18)) if r < 0.31 else "")
        due = (now + timedelta(days=random.randint(-60, 90))).strftime("%Y-%m-%d") if random.random() < 0.5 else None
        tasks.append({"id": str(uuid.uuid4()), "number": n, "title": " ".join(random.choice(W) for _ in range(5)),
                      "description": desc, "status": st, "priority": random.randint(0, 4), "startDate": None,
                      "dueDate": due, "labelIds": random.sample(lids, random.randint(0, 3)),
                      "sortOrder": float(n * 1000), "createdAt": iso(c), "updatedAt": iso(c + timedelta(hours=1)),
                      "completedAt": iso(c + timedelta(hours=2)) if st == "done" else None})
    pid = str(uuid.uuid4())
    key = "P" + "".join(chr(65 + (i // 26 ** k) % 26) for k in range(3))
    json.dump({"id": pid, "name": f"Project {i}", "key": key, "color": random.choice(COLORS), "archived": False,
               "favorite": False, "sortOrder": float(i * 1000), "favoriteOrder": 0.0, "labels": [],
               "nextNumber": size + 1, "createdAt": iso(now - timedelta(days=800)), "updatedAt": iso(now),
               "tasks": tasks}, open(os.path.join(out, "projects", pid + ".json"), "w"), indent=2)
print(f"tasks={sum(sizes)}")
