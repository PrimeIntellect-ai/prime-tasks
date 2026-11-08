#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import stat
import subprocess

REPORT_PATH = "/home/user/deadlock_report.txt"
DB_PATH = "/home/user/audit.db"
SOURCE_PATH = "/home/user/detect_deadlocks.cpp"
BINARY_PATH = "/home/user/detect_deadlocks"


def test_complete_deadlock_tool():
    # Preserve the original report assertion.
    assert os.path.isfile(REPORT_PATH), f"Report file missing at {REPORT_PATH}"
    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()
    assert content == "1001,1002,1003", (
        f"Expected '1001,1002,1003' in {REPORT_PATH}, got '{content}'"
    )

    # Preserve the original index existence assertions.
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_locks';"
    )
    result = cursor.fetchone()
    assert result is not None, "Index 'idx_locks' was not found in the database."
    assert result[0] == "idx_locks", "Index 'idx_locks' was not found in the database."

    # The named index must actually cover and support the holder lookup.
    cursor.execute("PRAGMA index_info('idx_locks')")
    index_columns = [row[2].lower() for row in cursor.fetchall()]
    assert {"resource", "status", "tx_id"}.issubset(index_columns), (
        "idx_locks must cover resource, status, and tx_id"
    )
    assert index_columns and index_columns[0] in {"resource", "status"}, (
        "idx_locks must lead with resource or status so holder lookups can use it"
    )
    conn.close()

    # Verify that the requested source and previously compiled executable exist.
    assert os.path.isfile(SOURCE_PATH), f"C++ source missing at {SOURCE_PATH}"
    assert stat.S_ISREG(os.stat(SOURCE_PATH).st_mode), "C++ source is not a regular file"
    assert os.path.isfile(BINARY_PATH), f"Executable missing at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable"

    # Compile the submitted source exactly as required, replacing any unrelated binary.
    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-lsqlite3", "-o", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"

    # Confirm that the compiled artifact directly uses the SQLite API.
    symbols = subprocess.run(
        ["nm", "-D", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=True,
    ).stdout
    assert re.search(r"\bsqlite3_open(?:_v2|16)?\b", symbols), (
        "Compiled program does not use a sqlite3_open API"
    )
    assert re.search(r"\bsqlite3_(?:prepare_v[23]|exec|get_table)\b", symbols), (
        "Compiled program does not use a SQLite query API"
    )

    # Replace the fixture rows with unpredictable IDs and both cyclic and acyclic work.
    base = secrets.randbelow(1_000_000_000) + 10_000
    cycle = [base + 11, base + 29, base + 47]
    holder = base + 101
    waiter = base + 102
    orphan = base + 103

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("DELETE FROM locks")
    cursor.executemany(
        "INSERT INTO locks(tx_id, resource, mode, status) VALUES (?, ?, ?, ?)",
        [
            (cycle[1], "dynamic_R2", "X", "GRANTED"),
            (cycle[0], "dynamic_R1", "X", "GRANTED"),
            (cycle[2], "dynamic_R3", "X", "GRANTED"),
            (cycle[0], "dynamic_R2", "X", "WAITING"),
            (cycle[1], "dynamic_R3", "X", "WAITING"),
            (cycle[2], "dynamic_R1", "X", "WAITING"),
            (holder, "dynamic_R4", "X", "GRANTED"),
            (waiter, "dynamic_R4", "X", "WAITING"),
            (orphan, "dynamic_R5", "X", "WAITING"),
        ],
    )
    conn.commit()
    conn.close()

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    run_result = subprocess.run(
        [BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert run_result.returncode == 0, f"Program failed:\n{run_result.stderr}"
    assert os.path.isfile(REPORT_PATH), "Program did not create deadlock_report.txt"

    with open(REPORT_PATH, "r") as f:
        dynamic_content = f.read().strip()
    expected = ",".join(str(tx) for tx in sorted(cycle))
    assert dynamic_content == expected, (
        f"Expected dynamically derived cycle '{expected}', got '{dynamic_content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
