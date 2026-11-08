#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import random
import statistics
import pytest

def test_recovered_db_valid():
    db_path = "/home/user/recovered.db"
    assert os.path.exists(db_path), f"Failed: {db_path} not found"

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT count(*) FROM measurements")
        count = cursor.fetchone()[0]
        assert count > 0, "Failed: measurements table is empty in recovered.db"
    except sqlite3.Error as e:
        pytest.fail(f"Failed: recovered.db is not a valid SQLite database or missing table. Error: {e}")
    finally:
        if 'conn' in locals():
            conn.close()

def test_mre_script_exists():
    mre_path = "/home/user/mre.py"
    assert os.path.exists(mre_path), f"Failed: {mre_path} not found"
    assert os.path.isfile(mre_path), f"Failed: {mre_path} is not a file"

def test_final_variance_correct():
    # Recompute the expected variance based on the setup script's logic
    random.seed(42)
    base_val = 100000000.0
    values = [base_val + random.uniform(0, 1) for _ in range(50000)]
    more_values = [base_val + random.uniform(0, 1) for _ in range(50000)]
    all_values = values + more_values

    expected_variance = statistics.variance(all_values)
    expected_variance_str = f"{expected_variance:.4f}"

    txt_path = "/home/user/final_variance.txt"
    assert os.path.exists(txt_path), f"Failed: {txt_path} not found"

    with open(txt_path, "r") as f:
        actual_variance_str = f.read().strip()

    assert actual_variance_str == expected_variance_str, (
        f"Failed: Variance mismatch. Expected {expected_variance_str}, got {actual_variance_str}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
