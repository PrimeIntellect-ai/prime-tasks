#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import sqlite3
import stat
import subprocess
import uuid

import pytest

DB_PATH = "/home/user/audit.db"
SCRIPT_PATH = "/home/user/audit_check.sh"
CSV_PATH = "/home/user/suspicious_overlaps.csv"


def get_expected_overlaps(db_path):
    """Derive expected suspicious overlaps directly from the database."""
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    cursor.execute("""
        SELECT user_id, ip_address, login_time, logout_time
        FROM access_logs
        ORDER BY user_id, login_time
    """)
    rows = cursor.fetchall()
    conn.close()

    overlaps = []
    prev_row = None
    for row in rows:
        if prev_row and prev_row['user_id'] == row['user_id']:
            if (row['login_time'] < prev_row['logout_time'] and
                    row['ip_address'] != prev_row['ip_address']):
                overlaps.append({
                    'user_id': str(row['user_id']),
                    'first_ip': prev_row['ip_address'],
                    'second_ip': row['ip_address'],
                    'overlap_start_time': row['login_time'],
                })
        prev_row = row
    return overlaps


@pytest.fixture(scope="session", autouse=True)
def prepare_and_execute_submission():
    """Add unseen cases, remove stale artifacts, and execute the submitted script."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("DROP INDEX IF EXISTS idx_user_login")
    cursor.execute("SELECT COALESCE(MAX(id), 0), COALESCE(MAX(user_id), 0) FROM access_logs")
    max_id, max_user = cursor.fetchone()

    token = uuid.uuid4().hex
    a, b, c, d, e, f = [f"verify-{token}-{n}" for n in range(6)]
    u1, u2, u3, u4 = [max_user + 1000 + n for n in range(4)]
    rows = [
        # A genuine different-IP overlap.
        (max_id + 1, u1, a, '2042-01-01 10:00:00', '2042-01-01 12:00:00'),
        (max_id + 2, u1, b, '2042-01-01 11:00:00', '2042-01-01 13:00:00'),
        # Equality at the boundary is not strictly before.
        (max_id + 3, u2, c, '2042-01-02 10:00:00', '2042-01-02 11:00:00'),
        (max_id + 4, u2, d, '2042-01-02 11:00:00', '2042-01-02 12:00:00'),
        # Same-IP overlap is not suspicious.
        (max_id + 5, u3, e, '2042-01-03 10:00:00', '2042-01-03 12:00:00'),
        (max_id + 6, u3, e, '2042-01-03 11:00:00', '2042-01-03 13:00:00'),
        # Only the immediately preceding session may be compared.
        (max_id + 7, u4, f, '2042-01-04 08:00:00', '2042-01-04 12:00:00'),
        (max_id + 8, u4, f, '2042-01-04 09:00:00', '2042-01-04 09:30:00'),
        (max_id + 9, u4, a, '2042-01-04 10:00:00', '2042-01-04 11:00:00'),
    ]
    cursor.executemany("INSERT INTO access_logs VALUES (?, ?, ?, ?, ?)", rows)
    conn.commit()
    cursor.execute("SELECT id, user_id, ip_address, login_time, logout_time FROM access_logs ORDER BY id")
    before_rows = cursor.fetchall()
    conn.close()

    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT id, user_id, ip_address, login_time, logout_time FROM access_logs ORDER BY id")
    after_rows = cursor.fetchall()
    conn.close()
    assert after_rows == before_rows, "The audit script must not alter access_logs data."


def test_script_exists_and_executable():
    """Check that the bash script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable by the owner."


def test_script_uses_window_function():
    """Check that the submitted analytical SQL contains a window function."""
    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.S)
    source = re.sub(r"(?m)^\s*(?:#|--).*?$", " ", source)
    window_call = re.compile(
        r"\b(?:lag|lead|row_number|rank|dense_rank|first_value|last_value|nth_value|"
        r"count|sum|min|max|avg)\s*\([^;]*?\)\s*(?:filter\s*\([^)]*\)\s*)?over\s*\(",
        re.I | re.S,
    )
    assert window_call.search(source), "The script does not contain a SQL window-function expression using OVER (...)."


def test_index_created():
    """Check that the required covering index was created on the correct columns."""
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_user_login';")
    result = cursor.fetchone()
    assert result is not None, "The index 'idx_user_login' was not created in the database."
    cursor.execute("PRAGMA index_info('idx_user_login')")
    columns = [row[2] for row in cursor.fetchall()]
    conn.close()
    assert columns == ['user_id', 'login_time'], (
        "The index 'idx_user_login' must cover exactly user_id and login_time in that order; "
        f"found {columns}."
    )


def test_csv_output_matches_expected():
    """Check that the executed script generated the correct CSV."""
    assert os.path.exists(CSV_PATH), f"Output CSV {CSV_PATH} does not exist. Did the script run successfully?"

    expected_overlaps = get_expected_overlaps(DB_PATH)
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        actual_overlaps = list(reader)
        expected_headers = ["user_id", "first_ip", "second_ip", "overlap_start_time"]
        assert reader.fieldnames == expected_headers, (
            f"CSV headers are incorrect. Expected {expected_headers}, got {reader.fieldnames}."
        )

    assert len(actual_overlaps) == len(expected_overlaps), (
        f"Expected {len(expected_overlaps)} rows in CSV, but found {len(actual_overlaps)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_overlaps, expected_overlaps)):
        assert actual['user_id'] == expected['user_id'], f"Row {i+1}: user_id mismatch."
        assert actual['first_ip'] == expected['first_ip'], f"Row {i+1}: first_ip mismatch."
        assert actual['second_ip'] == expected['second_ip'], f"Row {i+1}: second_ip mismatch."
        assert actual['overlap_start_time'] == expected['overlap_start_time'], f"Row {i+1}: overlap_start_time mismatch."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
