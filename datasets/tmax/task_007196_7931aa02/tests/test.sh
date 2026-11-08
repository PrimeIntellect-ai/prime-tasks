#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/sitecustomize.py
import json
import os
import sqlite3

_original_connect = sqlite3.connect
_log_path = os.environ.get("SQLITE_AUDIT_LOG")

def _write(event):
    if _log_path:
        with open(_log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(event) + "\n")

def _connect(database, *args, **kwargs):
    try:
        db_path = os.path.realpath(os.fspath(database))
    except Exception:
        db_path = str(database)
    _write({"type": "connect", "database": db_path})
    conn = _original_connect(database, *args, **kwargs)
    conn.set_trace_callback(lambda statement: _write({"type": "sql", "statement": statement}))
    return conn

sqlite3.connect = _connect
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import sqlite3
import stat
import subprocess

DB_PATH = "/home/user/etl_locks.db"
SCRIPT_PATH = "/home/user/process_deadlock.py"
CSV_PATH = "/home/user/deadlock_report.csv"
AUDIT_PATH = "/tmp/sqlite_audit.jsonl"

ORIGINAL_ROWS = [
    ("TX-88", "TX-99", 1620000050),
    ("TX-99", "TX-105", 1620000080),
    ("TX-11", "TX-12", 1620000010),
    ("TX-42", "TX-55", 1620000100),
    ("TX-55", "TX-61", 1620000150),
    ("TX-61", "TX-42", 1620000200),
    ("TX-70", "TX-71", 1620000300),
]

def write_database(rows):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("CREATE TABLE lock_waits (waiter_tx TEXT, holder_tx TEXT, wait_start_ms INTEGER)")
        conn.executemany("INSERT INTO lock_waits VALUES (?, ?, ?)", rows)
        conn.commit()
    finally:
        conn.close()


def expected_from_graph(rows):
    outgoing = {waiter: holder for waiter, holder, _ in rows}
    waits = {waiter: value for waiter, _, value in rows}
    cycle_nodes = []
    for start in outgoing:
        current = outgoing[start]
        seen = set()
        while current in outgoing and current not in seen:
            if current == start:
                cycle_nodes.append(start)
                break
            seen.add(current)
            current = outgoing[current]
    ordered = sorted(cycle_nodes, key=lambda tx: waits[tx])
    return [[tx, str(waits[tx]), str(index)] for index, tx in enumerate(ordered, 1)]


def read_and_check_report(expected_rows):
    assert os.path.isfile(CSV_PATH), f"The file {CSV_PATH} does not exist. Did you run your script and generate the output?"
    expected_header = ["tx_id", "wait_start_ms", "cycle_rank"]
    with open(CSV_PATH, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            raise AssertionError(f"{CSV_PATH} is empty.")
        assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}."
        rows = list(reader)
        assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(rows)}."
        for i, (expected, actual) in enumerate(zip(expected_rows, rows)):
            assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def stripped_sql(sql):
    token = re.compile(r"'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"|--[^\n]*|/\*.*?\*/", re.S)
    return token.sub(" ", sql)


def check_sql_audit():
    assert os.path.isfile(AUDIT_PATH), "No SQLite activity was recorded."
    with open(AUDIT_PATH, encoding="utf-8") as f:
        events = [json.loads(line) for line in f if line.strip()]

    connections = [e for e in events if e.get("type") == "connect"]
    assert len(connections) == 1, f"Expected exactly one database connection, got {len(connections)}."
    assert connections[0]["database"] == os.path.realpath(DB_PATH), "The script did not connect to /home/user/etl_locks.db."

    statements = [e["statement"] for e in events if e.get("type") == "sql"]
    assert len(statements) == 1, f"Expected the script to execute a single SQL query, got {len(statements)} statements."
    sql = stripped_sql(statements[0])
    assert re.search(r"\bwith\s+recursive\b", sql, re.I), "The SQL query must use a recursive CTE."
    assert re.search(r"\bunion(?:\s+all)?\b", sql, re.I), "The recursive CTE must perform recursive graph traversal."
    assert re.search(r"\b(?:row_number|rank|dense_rank)\s*\(\s*\)\s*over\b", sql, re.I), "The SQL query must use a ranking window function."


def run_submission(rows, expected_rows):
    write_database(rows)
    for path in (CSV_PATH, AUDIT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp" + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["SQLITE_AUDIT_LOG"] = AUDIT_PATH
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, f"process_deadlock.py failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    read_and_check_report(expected_rows)
    check_sql_audit()


def make_case(cycle_size):
    tag = secrets.token_hex(5).upper()
    base = 1700000000000 + secrets.randbelow(10000000)
    cycle = [f"C-{tag}-{i}" for i in range(cycle_size)]
    times = [base + offset for offset in secrets.SystemRandom().sample(range(100, 5000), cycle_size)]
    rows = [(cycle[i], cycle[(i + 1) % cycle_size], times[i]) for i in range(cycle_size)]
    rows.extend([
        (f"N-{tag}-1", f"N-{tag}-2", base + 6000),
        (f"N-{tag}-2", f"N-{tag}-3", base + 6100),
        (f"N-{tag}-4", f"N-{tag}-5", base + 6200),
        (f"N-{tag}-6", cycle[0], base + 6300),
    ])
    secrets.SystemRandom().shuffle(rows)
    return rows


def test_process_deadlock_script_and_report():
    assert os.path.isfile(SCRIPT_PATH), f"The file {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."

    original_expected = [
        ["TX-42", "1620000100", "1"],
        ["TX-55", "1620000150", "2"],
        ["TX-61", "1620000200", "3"],
    ]

    try:
        run_submission(ORIGINAL_ROWS, original_expected)
        for cycle_size in (3, 5):
            rows = make_case(cycle_size)
            run_submission(rows, expected_from_graph(rows))
    finally:
        write_database(ORIGINAL_ROWS)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
