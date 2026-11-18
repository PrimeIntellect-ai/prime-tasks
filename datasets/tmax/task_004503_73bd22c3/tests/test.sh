#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import secrets
import shutil
import sqlite3
import subprocess

PLAN_FILE = "/home/user/restore_plan.txt"
C_FILE = "/home/user/planner.c"
EXEC_FILE = "/home/user/planner"
DB_FILE = "/home/user/backups.db"
REBUILT_EXEC = "/tmp/planner_from_source"


def run_planner(executable, target):
    if os.path.exists(PLAN_FILE):
        os.unlink(PLAN_FILE)
    result = subprocess.run(
        [executable, str(target)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} failed for target {target} with exit code "
        f"{result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(PLAN_FILE), (
        f"{executable} did not create {PLAN_FILE} for target {target}"
    )
    with open(PLAN_FILE, "r") as f:
        raw = [line.strip() for line in f if line.strip()]
    try:
        return [int(value) for value in raw]
    except ValueError:
        raise AssertionError(f"Restore plan contains non-integer IDs: {raw}")


def test_c_source_exists():
    assert os.path.isfile(C_FILE), f"Source file {C_FILE} does not exist. You must write the C program."


def test_executable_exists():
    assert os.path.isfile(EXEC_FILE), f"Executable {EXEC_FILE} does not exist. Did you compile the program?"
    assert os.access(EXEC_FILE, os.X_OK), f"File {EXEC_FILE} is not executable."
    with open(EXEC_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXEC_FILE} is not a compiled native executable."


def test_restore_plan():
    assert os.path.isfile(PLAN_FILE), f"Output file {PLAN_FILE} does not exist. Did you run the program?"

    lines = [str(value) for value in run_planner(EXEC_FILE, 99)]
    expected = ['7', '8', '99']
    assert lines == expected, f"Expected restore plan {expected}, but got {lines}. Ensure you filter out FAILED backups and minimize total size."


def make_fixture():
    rng = random.Random(secrets.randbits(128))
    ids = rng.sample(range(10, 190), 14)
    f1, f2, a, b, c, d, e, t1, t2, t3, failed, progressing, isolated, failed_full = ids

    sizes = rng.sample(range(31, 931), 14)
    rows = [
        (f1, 'FULL', 'SUCCESS', sizes[0], 100),
        (f2, 'FULL', 'SUCCESS', sizes[1], 200),
        (a, 'INCR', 'SUCCESS', sizes[2], 300),
        (b, 'DIFF', 'SUCCESS', sizes[3], 400),
        (c, 'INCR', 'SUCCESS', sizes[4], 500),
        (d, 'DIFF', 'SUCCESS', sizes[5], 600),
        (e, 'INCR', 'SUCCESS', sizes[6], 700),
        (t1, 'INCR', 'SUCCESS', sizes[7], 800),
        (t2, 'DIFF', 'SUCCESS', sizes[8], 900),
        (t3, 'INCR', 'SUCCESS', sizes[9], 1000),
        (failed, 'INCR', 'FAILED', 1, 1100),
        (progressing, 'DIFF', 'IN_PROGRESS', 1, 1200),
        (isolated, 'INCR', 'SUCCESS', sizes[12], 1300),
        (failed_full, 'FULL', 'FAILED', 1, 1400),
    ]
    edges = [
        (f1, a), (a, c), (c, t1),
        (f2, b), (b, t1),
        (f1, d), (d, t1),
        (f1, failed), (failed, t1),
        (failed_full, t1),
        (c, t2), (f2, e), (e, t2), (t1, t2),
        (a, t3), (d, t3), (progressing, t3),
    ]
    rng.shuffle(rows)
    rng.shuffle(edges)
    return rows, edges, [t1, t2, t3, f1]


def install_fixture(rows, edges):
    for suffix in ("", "-wal", "-shm", "-journal"):
        path = DB_FILE + suffix
        if os.path.exists(path):
            os.unlink(path)
    conn = sqlite3.connect(DB_FILE)
    try:
        conn.execute('CREATE TABLE backups (id INTEGER PRIMARY KEY, type TEXT, status TEXT, size INTEGER, timestamp INTEGER)')
        conn.execute('CREATE TABLE dependencies (parent_id INTEGER, child_id INTEGER)')
        conn.executemany('INSERT INTO backups VALUES (?, ?, ?, ?, ?)', rows)
        conn.executemany('INSERT INTO dependencies VALUES (?, ?)', edges)
        conn.commit()
    finally:
        conn.close()


def minimum_cost(rows, edges, target):
    info = {row[0]: row for row in rows}
    graph = {}
    for parent, child in edges:
        graph.setdefault(parent, []).append(child)

    dist = {}
    queue = []
    for backup_id, backup_type, status, size, _ in rows:
        if backup_type == 'FULL' and status == 'SUCCESS':
            dist[backup_id] = size
            heapq.heappush(queue, (size, backup_id))

    while queue:
        cost, node = heapq.heappop(queue)
        if cost != dist.get(node):
            continue
        for child in graph.get(node, []):
            child_row = info.get(child)
            if child_row is None or child_row[2] != 'SUCCESS':
                continue
            new_cost = cost + child_row[3]
            if new_cost < dist.get(child, float('inf')):
                dist[child] = new_cost
                heapq.heappush(queue, (new_cost, child))
    return dist.get(target)


def validate_plan(plan, rows, edges, target):
    info = {row[0]: row for row in rows}
    edge_set = set(edges)
    assert plan, f"Empty restore plan for target {target}"
    assert plan[-1] == target, f"Plan {plan} does not end at target {target}"
    assert plan[0] in info and info[plan[0]][1] == 'FULL', f"Plan {plan} does not start with a FULL backup"
    assert len(plan) == len(set(plan)), f"Plan repeats backup IDs: {plan}"

    for backup_id in plan:
        assert backup_id in info, f"Unknown backup ID {backup_id} in plan {plan}"
        assert info[backup_id][2] == 'SUCCESS', f"Plan uses non-successful backup {backup_id}"
    for parent, child in zip(plan, plan[1:]):
        assert (parent, child) in edge_set, f"Plan follows invalid edge {parent} -> {child}"

    actual_cost = sum(info[backup_id][3] for backup_id in plan)
    expected_cost = minimum_cost(rows, edges, target)
    assert expected_cost is not None, f"Verifier fixture unexpectedly has no path to {target}"
    assert actual_cost == expected_cost, (
        f"Plan {plan} costs {actual_cost}, but the minimum successful path costs {expected_cost}"
    )


def test_program_queries_database_and_computes_paths():
    build = subprocess.run(
        ['gcc', '-o', REBUILT_EXEC, C_FILE, '-lsqlite3'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"planner.c does not compile with the required command: {build.stderr}"

    assert os.path.isfile(DB_FILE), f"Database {DB_FILE} is missing"
    with open(DB_FILE, 'rb') as f:
        original_db = f.read()

    rows, edges, targets = make_fixture()
    try:
        for executable in (EXEC_FILE, REBUILT_EXEC):
            for target in targets:
                install_fixture(rows, edges)
                plan = run_planner(executable, target)
                validate_plan(plan, rows, edges, target)
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            path = DB_FILE + suffix
            if os.path.exists(path):
                os.unlink(path)
        with open(DB_FILE, 'wb') as f:
            f.write(original_db)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
