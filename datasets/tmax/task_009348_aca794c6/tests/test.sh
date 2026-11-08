#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import hashlib
import os
import secrets
import sqlite3
import subprocess
import sys
import pytest

DB_PATH = "/home/user/errors.db"
LOG_PATH = "/home/user/raw_server_logs.txt"
SCRIPT_PATH = "/home/user/process_logs.py"


def get_expected_data():
    """
    Computes the expected database rows directly from the raw_server_logs.txt
    file, mimicking the filtering, alignment, and hashing logic.
    """
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."

    seen_hashes = set()
    expected_rows = []

    with open(LOG_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line or "ERROR:" not in line:
                continue

            # Example line: [2023-10-25 14:32:45.123] ERROR: Connection timeout - ID:usr_123
            try:
                timestamp_part, rest = line.split("] ", 1)
                timestamp_full = timestamp_part.lstrip("[")

                # Align to minute: 2023-10-25 14:32:45.123 -> 2023-10-25 14:32:00
                date_time, ms = timestamp_full.split(".")
                date, time = date_time.split(" ")
                hour, minute, sec = time.split(":")
                aligned_timestamp = f"{date} {hour}:{minute}:00"

                level_msg, user_part = rest.split(" - ID:")
                message = level_msg.replace("ERROR: ", "").strip()
                user_id = user_part.strip()

                hash_input = f"{aligned_timestamp}|{message}|{user_id}"
                hash_id = hashlib.md5(hash_input.encode('utf-8')).hexdigest()

                if hash_id not in seen_hashes:
                    seen_hashes.add(hash_id)
                    expected_rows.append((hash_id, aligned_timestamp, message, user_id))
            except Exception as e:
                pytest.fail(f"Failed to parse log line for expected truth: {line}. Error: {e}")

    # Sort to ensure consistent comparison
    expected_rows.sort(key=lambda x: (x[1], x[0]))
    return expected_rows


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The required script {SCRIPT_PATH} is missing."


def test_db_exists():
    assert os.path.isfile(DB_PATH), f"The database file {DB_PATH} was not created."


def test_db_schema():
    assert os.path.isfile(DB_PATH), f"The database file {DB_PATH} was not created."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='error_logs';")
    table = cursor.fetchone()
    assert table is not None, "Table 'error_logs' does not exist in the database."

    # Check schema
    cursor.execute("PRAGMA table_info(error_logs);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}

    expected_columns = {
        "hash_id": "TEXT",
        "timestamp": "TEXT",
        "message": "TEXT",
        "user_id": "TEXT"
    }

    for col, col_type in expected_columns.items():
        assert col in columns, f"Column '{col}' is missing from 'error_logs' table."
        # SQLite types can sometimes be flexible, but we check if TEXT is in the defined type
        assert "TEXT" in columns[col], f"Column '{col}' should be of type TEXT, but is {columns[col]}."

    conn.close()


def test_db_content():
    assert os.path.isfile(DB_PATH), f"The database file {DB_PATH} was not created."

    expected_rows = get_expected_data()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT hash_id, timestamp, message, user_id FROM error_logs ORDER BY timestamp ASC, hash_id ASC;")
    actual_rows = cursor.fetchall()
    conn.close()

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but found {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch.\nExpected: {expected}\nActual: {actual}"


def test_script_processes_unseen_log_fixture():
    token = secrets.token_hex(8)
    fixture = "\n".join([
        f"[2041-06-17 09:07:00.001] INFO: Startup {token} - ID:sys_{token}",
        f"[2041-06-17 09:07:59.987] ERROR: Timeout {token} - ID:user_{token}",
        f"[2041-06-17 09:07:01.123] ERROR: Timeout {token} - ID:user_{token}",
        f"[2041-06-17 09:07:30.456] ERROR: Disk failure {token} - ID:sys_{token}",
        f"[2041-06-17 09:08:00.000] ERROR: Timeout {token} - ID:user_{token}",
        f"[2041-06-17 09:08:44.321] ERROR: Timeout {token} - ID:other_{token}",
        ""
    ])

    with open(LOG_PATH, "rb") as f:
        original_log = f.read()
    original_db = None
    if os.path.isfile(DB_PATH):
        with open(DB_PATH, "rb") as f:
            original_db = f.read()

    try:
        with open(LOG_PATH, "w", encoding="utf-8") as f:
            f.write(fixture)
        expected_rows = get_expected_data()

        for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm"):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Running {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        # Reapply the original database existence and schema assertions to the
        # artifact produced by executing the submitted script.
        test_db_exists()
        test_db_schema()

        conn = sqlite3.connect(DB_PATH)
        try:
            rows = conn.execute(
                "SELECT hash_id, timestamp, message, user_id "
                "FROM error_logs ORDER BY timestamp ASC, hash_id ASC;"
            ).fetchall()
        finally:
            conn.close()

        assert rows == expected_rows, (
            "The submitted script did not correctly process the unseen log fixture.\n"
            f"Expected: {expected_rows}\nActual: {rows}"
        )
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
        for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm"):
            if os.path.exists(path):
                os.remove(path)
        if original_db is not None:
            with open(DB_PATH, "wb") as f:
                f.write(original_db)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
