#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import sqlite3
import stat
import subprocess
import time

import pytest

DB_PATH = "/home/user/backups.db"
QUERY_PATH = "/home/user/query.sql"
SOURCE_PATH = "/home/user/optimize.go"
PLAN_BEFORE_PATH = "/home/user/plan_before.txt"
PLAN_AFTER_PATH = "/home/user/plan_after.txt"
RESULTS_PATH = "/home/user/results.json"

EXPECTED_RESULTS = None
EXPECTED_PLAN_BEFORE = None
QUERY = None
RUN_STARTED_NS = None


def explain_details(conn, query):
    return [row[3] for row in conn.execute("EXPLAIN QUERY PLAN " + query).fetchall()]


def setup_module(module):
    global EXPECTED_RESULTS, EXPECTED_PLAN_BEFORE, QUERY, RUN_STARTED_NS

    assert os.path.isfile(SOURCE_PATH), f"File {SOURCE_PATH} is missing."
    source_stat = os.lstat(SOURCE_PATH)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE_PATH} must be a regular Go source file."
    assert source_stat.st_size > 0, f"{SOURCE_PATH} is empty."

    for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 900000), 12)
    roots = ids[:4]
    children = ids[4:]
    excluded_root = rng.choice(roots)

    rows = []
    totals = {}
    for i, root_id in enumerate(roots):
        first_child = children[i * 2]
        second_child = children[i * 2 + 1]
        root_bytes = rng.randrange(11000, 90000)
        first_bytes = rng.randrange(101, 5000)
        second_bytes = rng.randrange(101, 5000)
        rows.extend([
            (root_id, None, f"full_{root_id}", root_bytes, "success"),
            (first_child, root_id, f"inc_{first_child}", first_bytes, "success"),
            (second_child, first_child, f"inc_{second_child}", second_bytes, "success"),
        ])
        totals[root_id] = root_bytes + first_bytes + second_bytes
    rng.shuffle(rows)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE backup_jobs (
            id INTEGER PRIMARY KEY,
            parent_id INTEGER,
            job_name TEXT,
            bytes_transferred INTEGER,
            status TEXT
        )
    """)
    conn.executemany(
        "INSERT INTO backup_jobs (id, parent_id, job_name, bytes_transferred, status) VALUES (?, ?, ?, ?, ?)",
        rows,
    )
    conn.commit()

    QUERY = f"""WITH RECURSIVE backup_chain AS (
    SELECT id, id as root_id, bytes_transferred
    FROM backup_jobs
    WHERE parent_id IS NULL AND id != {excluded_root}

    UNION ALL

    SELECT b.id, c.root_id, b.bytes_transferred
    FROM backup_jobs b
    JOIN backup_chain c ON b.parent_id = c.id
)
SELECT root_id, SUM(bytes_transferred) as total_bytes
FROM backup_chain
GROUP BY root_id
ORDER BY root_id;
"""
    with open(QUERY_PATH, "w", encoding="utf-8") as query_file:
        query_file.write(QUERY)

    EXPECTED_RESULTS = [
        {"root_id": root_id, "total_bytes": totals[root_id]}
        for root_id in sorted(roots)
        if root_id != excluded_root
    ]
    EXPECTED_PLAN_BEFORE = explain_details(conn, QUERY)
    conn.close()

    assert any("SCAN" in detail.upper() for detail in EXPECTED_PLAN_BEFORE)
    assert any("BACKUP_JOBS" in detail.upper() for detail in EXPECTED_PLAN_BEFORE)

    for path in (PLAN_BEFORE_PATH, PLAN_AFTER_PATH, RESULTS_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    RUN_STARTED_NS = time.time_ns()
    try:
        completed = subprocess.run(
            ["go", "run", "optimize.go"],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"Executing {SOURCE_PATH} timed out: {exc}")

    assert completed.returncode == 0, (
        f"Executing {SOURCE_PATH} failed with exit code {completed.returncode}:\n"
        f"{completed.stdout}"
    )


def test_results_json():
    assert os.path.isfile(RESULTS_PATH), f"File {RESULTS_PATH} is missing."
    assert os.stat(RESULTS_PATH).st_mtime_ns >= RUN_STARTED_NS, f"{RESULTS_PATH} was not freshly generated."
    with open(RESULTS_PATH, "r", encoding="utf-8") as result_file:
        try:
            data = json.load(result_file)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON.")

    assert isinstance(data, list), f"File {RESULTS_PATH} must contain a JSON array."
    data_sorted = sorted(data, key=lambda item: item.get("root_id", 0))
    expected_sorted = sorted(EXPECTED_RESULTS, key=lambda item: item["root_id"])
    assert data_sorted == expected_sorted, f"Data in {RESULTS_PATH} does not match the query output."


def test_plan_before():
    assert os.path.isfile(PLAN_BEFORE_PATH), f"File {PLAN_BEFORE_PATH} is missing."
    assert os.stat(PLAN_BEFORE_PATH).st_mtime_ns >= RUN_STARTED_NS, f"{PLAN_BEFORE_PATH} was not freshly generated."
    with open(PLAN_BEFORE_PATH, "r", encoding="utf-8") as plan_file:
        lines = plan_file.read().splitlines()
    content = "\n".join(lines).upper()

    assert "SCAN" in content, f"Expected 'SCAN' in {PLAN_BEFORE_PATH}, indicating a full table scan before optimization."
    assert "BACKUP_JOBS" in content, f"Expected table 'backup_jobs' to be mentioned in {PLAN_BEFORE_PATH}."
    assert lines == EXPECTED_PLAN_BEFORE, f"{PLAN_BEFORE_PATH} does not contain the real pre-index explain details."


def test_plan_after():
    assert os.path.isfile(PLAN_AFTER_PATH), f"File {PLAN_AFTER_PATH} is missing."
    assert os.stat(PLAN_AFTER_PATH).st_mtime_ns >= RUN_STARTED_NS, f"{PLAN_AFTER_PATH} was not freshly generated."
    with open(PLAN_AFTER_PATH, "r", encoding="utf-8") as plan_file:
        lines = plan_file.read().splitlines()
    content = "\n".join(lines).upper()

    assert "SEARCH" in content, f"Expected 'SEARCH' in {PLAN_AFTER_PATH}, indicating an index was used after optimization."
    assert "BACKUP_JOBS" in content, f"Expected table 'backup_jobs' to be mentioned in {PLAN_AFTER_PATH}."

    conn = sqlite3.connect(DB_PATH)
    actual_plan = explain_details(conn, QUERY)
    conn.close()
    assert lines == actual_plan, f"{PLAN_AFTER_PATH} does not contain the real post-index explain details."


def test_index_created():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA index_list('backup_jobs');")
    indexes = cursor.fetchall()

    has_parent_id_index = False
    for idx in indexes:
        idx_name = idx[1]
        escaped_name = idx_name.replace("'", "''")
        cursor.execute(f"PRAGMA index_info('{escaped_name}');")
        columns = cursor.fetchall()
        if any(col[2] == "parent_id" for col in columns):
            has_parent_id_index = True
            break

    conn.close()
    assert has_parent_id_index, "No index found on the 'parent_id' column of the 'backup_jobs' table."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
