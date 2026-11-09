#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_analyze_path.py
import json
import runpy
import sqlite3
import sys

script_path = sys.argv[1]
trace_path = sys.argv[2]
statements = []
real_connect = sqlite3.connect

class TracingConnection(sqlite3.Connection):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.set_trace_callback(statements.append)

def traced_connect(*args, **kwargs):
    kwargs["factory"] = TracingConnection
    return real_connect(*args, **kwargs)

sqlite3.connect = traced_connect
sys.argv = [script_path]
sys.path.insert(0, "/home/user")
try:
    runpy.run_path(script_path, run_name="__main__")
finally:
    with open(trace_path, "w") as f:
        json.dump(statements, f)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
from collections import defaultdict, deque

DB_PATH = "/home/user/ecommerce.db"
JSONL_PATH = "/home/user/activity.jsonl"
SCRIPT_PATH = "/home/user/analyze_path.py"
REPORT_PATH = "/home/user/report.json"
RUNNER_PATH = "/tmp/run_analyze_path.py"


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def get_shortest_path(db_path, start, end):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT user_id1, user_id2 FROM friendships")
    graph = defaultdict(list)
    for u, v in c.fetchall():
        graph[u].append(v)
    conn.close()

    queue = deque([[start]])
    visited = {start}
    while queue:
        path = queue.popleft()
        node = path[-1]
        if node == end:
            return path
        for neighbor in graph[node]:
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(path + [neighbor])
    return []


def get_expected_purchases(db_path, path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    purchases = {}
    for uid in path:
        c.execute("SELECT name FROM users WHERE id = ?", (uid,))
        row = c.fetchone()
        name = row[0] if row else f"User_{uid}"
        c.execute("SELECT SUM(amount) FROM purchases WHERE user_id = ?", (uid,))
        total_row = c.fetchone()
        total = total_row[0] if total_row and total_row[0] is not None else 0.0
        purchases[str(uid)] = {"name": name, "total_spent": total}
    conn.close()
    return purchases


def get_expected_activities(jsonl_path, path):
    path_set = set(path)
    activities = defaultdict(lambda: defaultdict(list))
    with open(jsonl_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            uid = record.get("user_id")
            if uid in path_set:
                activities[str(uid)][record["event"]].append(record["duration_ms"])

    aggregation = {}
    for uid, events in activities.items():
        aggregation[uid] = {}
        for event, durations in events.items():
            aggregation[uid][event] = sum(durations) / len(durations)
    return aggregation


def expected_state():
    path = get_shortest_path(DB_PATH, 1, 20)
    return path, get_expected_purchases(DB_PATH, path), get_expected_activities(JSONL_PATH, path)


def check_report(path, purchases, activities):
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} was not generated."
    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {REPORT_PATH} is not valid JSON: {exc}")

    assert "path" in report, "Key 'path' missing from report."
    assert "purchases" in report, "Key 'purchases' missing from report."
    assert "activity_aggregation" in report, "Key 'activity_aggregation' missing from report."
    assert report["path"] == path, f"Expected path {path}, got {report['path']}"
    assert report["purchases"] == purchases, "Purchases aggregation does not match expected output."
    assert report["activity_aggregation"] == activities, "Activity aggregation does not match expected output."


def check_sql_method(trace_path, path, purchases):
    with open(trace_path, "r") as f:
        statements = json.load(f)

    qualifying = []
    for statement in statements:
        normalized = " ".join(statement.lower().split())
        if (re.search(r"\bselect\b", normalized)
                and re.search(r"\busers\b", normalized)
                and re.search(r"\bpurchases\b", normalized)
                and re.search(r"\bjoin\b", normalized)
                and re.search(r"\b(sum|total)\s*\(", normalized)
                and re.search(r"\bgroup\s+by\b", normalized)):
            qualifying.append(statement)

    assert len(qualifying) == 1, (
        "The script must execute exactly one SQL query using users/purchases JOINs "
        "and aggregation for the path users."
    )

    # Re-execute the observed query and verify that it actually returns exactly the
    # path users' names and aggregate totals, rather than merely being a dummy query.
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.execute(qualifying[0])
        rows = cur.fetchall()
    finally:
        conn.close()
    assert len(rows) == len(path), "The purchase query did not restrict its result to the path users."

    unmatched = list(rows)
    for uid in path:
        expected = purchases[str(uid)]
        found_index = None
        for index, row in enumerate(unmatched):
            values = list(row)
            has_name = expected["name"] in values
            has_total = any(
                isinstance(value, (int, float))
                and not isinstance(value, bool)
                and math.isclose(float(value), float(expected["total_spent"]), rel_tol=1e-9, abs_tol=1e-9)
                for value in values
            )
            if has_name and has_total:
                found_index = index
                break
        assert found_index is not None, f"Purchase query did not return the correct aggregate for user {uid}."
        unmatched.pop(found_index)


def run_and_check(label):
    path, purchases, activities = expected_state()
    before_db = file_hash(DB_PATH)
    before_jsonl = file_hash(JSONL_PATH)
    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)

    trace_path = f"/tmp/analyze_trace_{label}.json"
    result = subprocess.run(
        ["python3", RUNNER_PATH, SCRIPT_PATH, trace_path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze_path.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert file_hash(DB_PATH) == before_db, "analyze_path.py must not modify ecommerce.db."
    assert file_hash(JSONL_PATH) == before_jsonl, "analyze_path.py must not modify activity.jsonl."
    check_report(path, purchases, activities)
    check_sql_method(trace_path, path, purchases)


def apply_dynamic_fixture():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM friendships WHERE (user_id1 = 14 AND user_id2 = 20) OR (user_id1 = 20 AND user_id2 = 14)")
    c.execute("INSERT INTO friendships (user_id1, user_id2) VALUES (8, 20)")
    c.execute("INSERT INTO friendships (user_id1, user_id2) VALUES (20, 8)")
    c.execute("UPDATE users SET name = 'Dynamic_User_1' WHERE id = 1")
    c.execute("UPDATE users SET name = 'Dynamic_User_8' WHERE id = 8")
    c.execute("UPDATE purchases SET amount = amount + 3.25 WHERE user_id IN (1, 7, 20)")
    c.execute("DELETE FROM purchases WHERE id = 999")
    c.execute("INSERT INTO purchases (id, user_id, amount) VALUES (999, 8, 321.75)")
    conn.commit()
    conn.close()

    with open(JSONL_PATH, "a") as f:
        f.write(json.dumps({"user_id": 1, "event": "click", "duration_ms": 347}) + "\n")
        f.write(json.dumps({"user_id": 8, "event": "view", "duration_ms": 611}) + "\n")
        f.write(json.dumps({"user_id": 8, "event": "view", "duration_ms": 913}) + "\n")


def main():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    assert os.path.getsize(SCRIPT_PATH) > 0, f"Required script {SCRIPT_PATH} is empty."
    with open(SCRIPT_PATH, "rb") as f:
        compile(f.read(), SCRIPT_PATH, "exec")

    backup_dir = tempfile.mkdtemp(prefix="analyze_path_backup_")
    db_backup = os.path.join(backup_dir, "ecommerce.db")
    jsonl_backup = os.path.join(backup_dir, "activity.jsonl")
    shutil.copy2(DB_PATH, db_backup)
    shutil.copy2(JSONL_PATH, jsonl_backup)
    try:
        run_and_check("original")
        apply_dynamic_fixture()
        run_and_check("dynamic")
    finally:
        shutil.copy2(db_backup, DB_PATH)
        shutil.copy2(jsonl_backup, JSONL_PATH)
        shutil.rmtree(backup_dir, ignore_errors=True)

    # Leave the requested report generated from the original supplied inputs.
    run_and_check("restored")


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
