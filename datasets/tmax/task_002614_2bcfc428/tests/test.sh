#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import sqlite3
import stat
import subprocess
import uuid

import pytest

CSV_PATH = "/home/user/deadlocks.csv"
DB_PATH = "/home/user/etl_locks.db"
SCRIPT_PATH = "/home/user/deadlock_detector.py"


def create_database(transactions, locks):
    if os.path.lexists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute('''
        CREATE TABLE transactions (
            tx_id TEXT PRIMARY KEY,
            start_time DATETIME,
            query TEXT
        )
    ''')
    cur.execute('''
        CREATE TABLE locks (
            tx_id TEXT,
            resource_id TEXT,
            status TEXT
        )
    ''')
    cur.executemany("INSERT INTO transactions VALUES (?, ?, ?)", transactions)
    cur.executemany("INSERT INTO locks VALUES (?, ?, ?)", locks)
    conn.commit()
    conn.close()


def read_csv():
    assert os.path.exists(CSV_PATH), f"Expected output file {CSV_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a valid file."
    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def run_detector(expected_rows):
    if os.path.lexists(CSV_PATH):
        os.remove(CSV_PATH)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"deadlock_detector.py exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    rows = read_csv()
    assert rows, "CSV file is empty."
    assert rows[0] == ["tx_id", "rank", "query"], (
        f"CSV header is incorrect. Got {rows[0]}"
    )
    assert rows[1:] == expected_rows

    # The supplied snapshot is an input and must still be available for validation.
    assert os.path.isfile(DB_PATH), "The detector removed the input database."
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("SELECT tx_id, start_time, query FROM transactions").fetchall()
        conn.execute("SELECT tx_id, resource_id, status FROM locks").fetchall()
    finally:
        conn.close()


def create_canonical_database():
    tx_data = [
        ("T1", "2023-10-01 10:01:00", "UPDATE users SET active=1"),
        ("T2", "2023-10-01 10:02:00", "DELETE FROM sessions WHERE idle>10"),
        ("T3", "2023-10-01 10:03:00", "INSERT INTO logs VALUES (...)"),
        ("T4", "2023-10-01 10:04:00", "UPDATE config SET val=2"),
        ("T5", "2023-10-01 10:05:00", "SELECT * FROM orders"),
        ("T6", "2023-10-01 10:06:00", "UPDATE orders SET status='shipped'"),
        ("T7", "2023-10-01 10:07:00", "SELECT * FROM users"),
        ("T8", "2023-10-01 10:08:00", "DELETE FROM temp_data"),
        ("T9", "2023-10-01 10:09:00", "INSERT INTO metrics VALUES (...)"),
        ("T10", "2023-10-01 10:10:00", "UPDATE stats SET count=count+1"),
        ("T11", "2023-10-01 10:11:00", "UPDATE stats_agg SET total=total+1"),
    ]
    locks_data = [
        ("T1", "R1", "GRANTED"),
        ("T1", "R4", "WAITING"),
        ("T2", "R2", "GRANTED"),
        ("T2", "R1", "WAITING"),
        ("T3", "R3", "GRANTED"),
        ("T3", "R2", "WAITING"),
        ("T4", "R4", "GRANTED"),
        ("T4", "R3", "WAITING"),
        ("T5", "R5", "GRANTED"),
        ("T6", "R5", "WAITING"),
        ("T7", "R6", "GRANTED"),
        ("T8", "R7", "GRANTED"),
        ("T8", "R6", "WAITING"),
        ("T9", "R7", "WAITING"),
        ("T10", "R8", "GRANTED"),
        ("T10", "R9", "WAITING"),
        ("T11", "R9", "GRANTED"),
        ("T11", "R8", "WAITING"),
    ]
    create_database(tx_data, locks_data)


def test_00_script_exists_and_executes_on_controlled_inputs():
    assert os.path.lexists(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} must be a regular Python file."

    token = uuid.uuid4().hex
    a, b, c, d, e, tail, g, h = [f"{token}_{name}" for name in "abcdefgh"]
    ra, rb, rc, rd, re, rg, rh = [f"{token}_R{name}" for name in "ABCDEFG"]

    transactions = [
        (a, "2041-06-01 10:13:00", f"UPDATE alpha SET note='a,{token}'"),
        (b, "2041-06-01 10:10:00", f"DELETE FROM beta WHERE tag='{token}'"),
        (c, "2041-06-01 10:12:00", f"INSERT INTO gamma VALUES ('{token}')"),
        (d, "2041-06-01 10:11:00", f"UPDATE delta SET v=\"{token}\""),
        (e, "2041-06-01 10:09:00", f"SELECT 'e,{token}'"),
        (tail, "2041-06-01 10:01:00", f"SELECT 'tail-{token}'"),
        (g, "2041-06-01 10:02:00", f"SELECT 'g-{token}'"),
        (h, "2041-06-01 10:03:00", f"SELECT 'h-{token}'"),
    ]
    locks = [
        (a, ra, "GRANTED"), (a, rb, "WAITING"),
        (b, rb, "GRANTED"), (b, rc, "WAITING"),
        (c, rc, "GRANTED"), (c, ra, "WAITING"),
        (d, rd, "GRANTED"), (d, re, "WAITING"),
        (e, re, "GRANTED"), (e, rd, "WAITING"),
        (tail, ra, "WAITING"),
        (g, rg, "GRANTED"), (g, rh, "WAITING"),
        (h, rh, "GRANTED"),
    ]
    query_by_tx = {tx_id: query for tx_id, _, query in transactions}
    expected_order = [e, b, d, c, a]
    expected = [
        [tx_id, str(rank), query_by_tx[tx_id]]
        for rank, tx_id in enumerate(expected_order, start=1)
    ]
    create_database(transactions, locks)
    run_detector(expected)

    # A second snapshot ensures acyclic waits are not reported as deadlocks.
    token2 = uuid.uuid4().hex
    x, y, z = [f"{token2}_{name}" for name in "xyz"]
    create_database(
        [
            (x, "2042-01-01 01:00:00", f"SELECT '{token2},x'"),
            (y, "2042-01-01 02:00:00", f"SELECT '{token2},y'"),
            (z, "2042-01-01 03:00:00", f"SELECT '{token2},z'"),
        ],
        [
            (x, f"{token2}_RX", "GRANTED"),
            (y, f"{token2}_RY", "GRANTED"),
            (y, f"{token2}_RX", "WAITING"),
            (z, f"{token2}_RY", "WAITING"),
        ],
    )
    run_detector([])

    # Leave the original supplied snapshot in place and verify that running the
    # submitted artifact produces its requested final output.
    create_canonical_database()
    canonical_expected = [
        ["T1", "1", "UPDATE users SET active=1"],
        ["T2", "2", "DELETE FROM sessions WHERE idle>10"],
        ["T3", "3", "INSERT INTO logs VALUES (...)"],
        ["T4", "4", "UPDATE config SET val=2"],
        ["T10", "5", "UPDATE stats SET count=count+1"],
        ["T11", "6", "UPDATE stats_agg SET total=total+1"],
    ]
    run_detector(canonical_expected)


def get_expected_deadlocks():
    assert os.path.exists(DB_PATH), f"Required input database {DB_PATH} is missing."
    assert os.path.isfile(DB_PATH), f"{DB_PATH} is not a valid file."

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute("SELECT tx_id, resource_id FROM locks WHERE status='WAITING'")
    waiting = cur.fetchall()

    cur.execute("SELECT tx_id, resource_id FROM locks WHERE status='GRANTED'")
    granted = cur.fetchall()

    resource_holders = {res: tx for tx, res in granted}

    graph = {}
    for tx_wait, res in waiting:
        if res in resource_holders:
            tx_hold = resource_holders[res]
            graph.setdefault(tx_wait, []).append(tx_hold)

    visited = set()
    rec_stack = set()
    deadlocked_txs = set()

    def dfs(node, path):
        visited.add(node)
        rec_stack.add(node)
        path.append(node)

        for neighbor in graph.get(node, []):
            if neighbor not in visited:
                dfs(neighbor, path)
            elif neighbor in rec_stack:
                idx = path.index(neighbor)
                for n in path[idx:]:
                    deadlocked_txs.add(n)

        rec_stack.remove(node)
        path.pop()

    for node in list(graph.keys()):
        if node not in visited:
            dfs(node, [])

    if not deadlocked_txs:
        conn.close()
        return []

    placeholders = ",".join("?" for _ in deadlocked_txs)
    cur.execute(
        f"SELECT tx_id, start_time, query FROM transactions WHERE tx_id IN ({placeholders}) ORDER BY start_time ASC",
        list(deadlocked_txs),
    )

    results = []
    for rank, (tx_id, start_time, query) in enumerate(cur.fetchall(), start=1):
        results.append({"tx_id": tx_id, "rank": str(rank), "query": query})

    conn.close()
    return results


def test_csv_exists():
    assert os.path.exists(CSV_PATH), f"Expected output file {CSV_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a valid file."


def test_csv_content():
    expected_data = get_expected_deadlocks()

    assert os.path.exists(CSV_PATH), "Cannot test content because CSV is missing."

    with open(CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty.")

        assert header == ["tx_id", "rank", "query"], f"CSV header is incorrect. Expected ['tx_id', 'rank', 'query'], got {header}"
        rows = list(reader)

    assert len(rows) == len(expected_data), f"Expected {len(expected_data)} rows in CSV, but found {len(rows)}."

    for i, expected_row in enumerate(expected_data):
        actual_row = rows[i]
        assert len(actual_row) == 3, f"Row {i+1} does not have exactly 3 columns: {actual_row}"
        assert actual_row[0] == expected_row["tx_id"], f"Row {i+1} tx_id mismatch. Expected {expected_row['tx_id']}, got {actual_row[0]}"
        assert actual_row[1] == expected_row["rank"], f"Row {i+1} rank mismatch. Expected {expected_row['rank']}, got {actual_row[1]}"
        assert actual_row[2] == expected_row["query"], f"Row {i+1} query mismatch. Expected '{expected_row['query']}', got '{actual_row[2]}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
