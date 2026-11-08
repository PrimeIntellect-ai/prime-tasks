#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import subprocess
import pytest

ORIGINAL_CSV_PATH = "/home/user/data/query_logs.csv"
FIXED_CSV_PATH = "/home/user/data/query_logs_fixed.csv"
BAD_QUERIES_LOG_PATH = "/home/user/bad_queries.log"
SCRIPT_PATH = "/home/user/scripts/build_report.py"


def expected_original_rows():
    rows = [["QueryID", "Timestamp", "UserID", "QueryText", "ExecutionTime"]]
    for i in range(1, 101):
        query_id = f"Q{i:04d}"
        timestamp = f"2023-10-24T10:{i % 60:02d}:00"
        user = f"U{i % 10}"
        query = "SELECT * FROM users"
        execution_time = f"{i * 0.1:.2f}"
        if i == 42:
            execution_time = "NULL_VAL"
        if i == 76:
            query = "SELECT * FROM users\x00 WHERE id=1"
        rows.append([query_id, timestamp, user, query, execution_time])
    return rows


def read_csv_rows(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def test_fixed_csv_exists():
    assert os.path.isfile(FIXED_CSV_PATH), f"The fixed CSV file is missing at {FIXED_CSV_PATH}"


def test_fixed_csv_contents():
    with open(FIXED_CSV_PATH, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    assert len(lines) == 99, f"Expected 99 lines in fixed CSV, found {len(lines)}"

    content = "".join(lines)
    assert "QueryID,Timestamp,UserID,QueryText,ExecutionTime" in lines[0], "Missing or incorrect CSV header in the fixed file"
    assert "Q0042" not in content, "Row Q0042 (corrupted) should be removed from the fixed CSV"
    assert "Q0076" not in content, "Row Q0076 (corrupted) should be removed from the fixed CSV"
    assert "\x00" not in content, "Null bytes should not be present in the fixed CSV"
    assert "NULL_VAL" not in content, "NULL_VAL should not be present in the fixed CSV"


def test_fixed_csv_is_original_data_without_corrupted_rows():
    assert os.path.isfile(ORIGINAL_CSV_PATH), "The original CSV is missing"
    original_rows = read_csv_rows(ORIGINAL_CSV_PATH)
    assert original_rows == expected_original_rows(), "The original CSV was modified"

    expected_fixed_rows = [
        row for index, row in enumerate(original_rows)
        if index == 0 or row[0] not in {"Q0042", "Q0076"}
    ]
    actual_fixed_rows = read_csv_rows(FIXED_CSV_PATH)
    assert actual_fixed_rows == expected_fixed_rows, (
        "The fixed CSV must contain exactly the original uncorrupted rows, in their original order"
    )


def test_bad_queries_log_exists():
    assert os.path.isfile(BAD_QUERIES_LOG_PATH), f"The bad queries log is missing at {BAD_QUERIES_LOG_PATH}"


def test_bad_queries_log_contents():
    with open(BAD_QUERIES_LOG_PATH, 'r', encoding='utf-8') as f:
        content = f.read().strip().splitlines()

    expected = ["Q0042", "Q0076"]
    assert content == expected, f"Expected bad queries log to contain {expected}, but found {content}"


def test_build_script_succeeds_with_fixed_csv():
    assert os.path.isfile(SCRIPT_PATH), "Build script is missing"

    result = subprocess.run(
        ["python3", SCRIPT_PATH, FIXED_CSV_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    assert result.returncode == 0, f"Build script failed on fixed CSV. Stderr: {result.stderr}"
    assert "Build successful:" in result.stdout, "Build script did not output success message"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
