#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import re
import pytest

def test_failed_batch_txt():
    log_file = "/home/user/logs/pipeline.log"
    assert os.path.exists(log_file), "Log file is missing."

    with open(log_file, "r") as f:
        logs = f.read()

    match = re.search(r"stalled indefinitely while processing batch_id=(\d+)", logs)
    assert match is not None, "Could not find stalled batch in logs."
    expected_batch = match.group(1)

    failed_batch_file = "/home/user/failed_batch.txt"
    assert os.path.exists(failed_batch_file), f"{failed_batch_file} does not exist."

    with open(failed_batch_file, "r") as f:
        content = f.read().strip()

    assert content == expected_batch, f"Expected '{expected_batch}' in failed_batch.txt, but got '{content}'."

def test_extracted_inputs_txt():
    failed_batch_file = "/home/user/failed_batch.txt"
    assert os.path.exists(failed_batch_file), f"{failed_batch_file} does not exist."

    with open(failed_batch_file, "r") as f:
        batch_id = f.read().strip()

    db_file = "/home/user/db/workload.db"
    assert os.path.exists(db_file), "Database file is missing."

    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    cursor.execute("SELECT input_value FROM measurements WHERE batch_id=?", (batch_id,))
    expected_inputs = [str(row[0]) for row in cursor.fetchall()]
    conn.close()

    extracted_file = "/home/user/extracted_inputs.txt"
    assert os.path.exists(extracted_file), f"{extracted_file} does not exist."

    with open(extracted_file, "r") as f:
        actual_inputs = [line.strip() for line in f if line.strip()]

    assert sorted(actual_inputs) == sorted(expected_inputs), "The contents of extracted_inputs.txt do not match the expected values from the database for the failed batch."

def test_minimal_bug_txt():
    minimal_bug_file = "/home/user/minimal_bug.txt"
    assert os.path.exists(minimal_bug_file), f"{minimal_bug_file} does not exist."

    with open(minimal_bug_file, "r") as f:
        content = f.read().strip()

    # 3074457345618258605 is the value from the DB that causes integer overflow in bash
    # when multiplied by 3 and adding 1, since it exceeds the signed 64-bit integer max.
    expected_bug_value = "3074457345618258605"
    assert content == expected_bug_value, f"Expected minimal bug value '{expected_bug_value}' in minimal_bug.txt, but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
