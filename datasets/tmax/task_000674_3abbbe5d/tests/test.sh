#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

import cv2

DB_PATH = "/home/user/recovered_backups.db"
SCRIPT_PATH = "/home/user/backup_analyzer.py"
VIDEO_PATH = "/app/backup_monitor.mp4"
START_TS = 1700000000


def recover_expected_rows():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open {VIDEO_PATH}"
    rows = []
    index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        rows.append((START_TS + index, 1 if float(gray.mean()) > 128 else 0))
        index += 1
    cap.release()
    assert rows, "No frames were decoded from the backup monitor video."
    return rows


EXPECTED_ROWS = recover_expected_rows()


def longest_failure_streak(rows, timestamp):
    longest = 0
    current = 0
    for ts, status in rows:
        if ts >= timestamp:
            break
        if status == 0:
            current += 1
            longest = max(longest, current)
        else:
            current = 0
    return longest


def run_analyzer(timestamp):
    result = subprocess.run(
        [SCRIPT_PATH, str(timestamp)], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Analyzer failed on input {timestamp}: {result.stderr}"
    )
    assert result.stderr == "", f"Analyzer wrote to stderr: {result.stderr!r}"
    output = result.stdout.strip()
    assert re.fullmatch(r"[0-9]+", output), (
        f"Analyzer must print only an integer, got {result.stdout!r}"
    )
    return int(output)


def test_recovered_db_exists_and_contents():
    assert os.path.isfile(DB_PATH), f"Recovered database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        schema = conn.execute("PRAGMA table_info(backups)").fetchall()
        assert len(schema) == 2, f"Unexpected backups schema: {schema}"
        assert schema[0][1].lower() == "timestamp"
        assert schema[0][2].upper() == "INTEGER"
        assert schema[0][5] == 1, "timestamp must be the primary key"
        assert schema[1][1].lower() == "status"
        assert schema[1][2].upper() == "INTEGER"
        rows = conn.execute(
            "SELECT timestamp, status FROM backups ORDER BY timestamp"
        ).fetchall()
    finally:
        conn.close()
    assert rows == EXPECTED_ROWS, "Recovered database does not match the video."


def test_analyzer_script_exists_executable_and_uses_window_sql():
    assert os.path.isfile(SCRIPT_PATH), f"Analyzer script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Analyzer script {SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as handle:
        source = handle.read()
    ast.parse(source, filename=SCRIPT_PATH)
    assert re.search(r"\bOVER\s*\(", source, re.IGNORECASE), (
        "Analyzer does not contain a SQL window function."
    )
    assert re.search(r"\?|:[A-Za-z_]\w*", source), (
        "Analyzer does not appear to use a parameterized SQL query."
    )


def test_fuzz_equivalence():
    random.seed(42)
    timestamps = [
        START_TS - 10,
        START_TS,
        START_TS + len(EXPECTED_ROWS),
        START_TS + len(EXPECTED_ROWS) + 10,
    ]
    timestamps.extend(
        random.randint(START_TS - 20, START_TS + len(EXPECTED_ROWS) + 20)
        for _ in range(200)
    )
    for timestamp in timestamps:
        expected = longest_failure_streak(EXPECTED_ROWS, timestamp)
        actual = run_analyzer(timestamp)
        assert actual == expected, (
            f"Output mismatch for T={timestamp}: expected {expected}, got {actual}"
        )


def test_analyzer_actually_uses_recovered_database():
    crafted = [
        (START_TS, 0),
        (START_TS + 1, 0),
        (START_TS + 2, 1),
        (START_TS + 3, 0),
        (START_TS + 4, 0),
        (START_TS + 5, 0),
        (START_TS + 6, 1),
        (START_TS + 7, 0),
    ]
    fd, saved_path = tempfile.mkstemp(prefix="recovered_backups_", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, saved_path)
    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("DELETE FROM backups")
            conn.executemany("INSERT INTO backups(timestamp, status) VALUES (?, ?)", crafted)
            conn.commit()
        finally:
            conn.close()

        for timestamp in range(START_TS, START_TS + 10):
            expected = longest_failure_streak(crafted, timestamp)
            actual = run_analyzer(timestamp)
            assert actual == expected, (
                f"Analyzer did not reflect database contents for T={timestamp}: "
                f"expected {expected}, got {actual}"
            )
    finally:
        shutil.copy2(saved_path, DB_PATH)
        os.unlink(saved_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
