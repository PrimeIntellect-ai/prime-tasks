#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import time
import subprocess
import sqlite3
import pytest

def get_expected_total_bytes(db_path: str) -> str:
    """Dynamically traverse the topology to find all cluster nodes and aggregate bytes."""
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    master = "srv_001"
    queue = [master]
    visited = {master}

    while queue:
        current = queue.pop(0)
        c.execute("SELECT target_id FROM Topology WHERE source_id = ?", (current,))
        for row in c.fetchall():
            target = row[0]
            if target not in visited:
                visited.add(target)
                queue.append(target)

    total_bytes = 0
    for node in visited:
        c.execute("SELECT SUM(bytes) FROM Logs WHERE server_id = ?", (node,))
        res = c.fetchone()[0]
        if res:
            total_bytes += res

    conn.close()
    return str(total_bytes)

def test_script_exists():
    script_path = '/home/user/summarize_chains.py'
    assert os.path.isfile(script_path), f"Required script not found at {script_path}"

def test_execution_time_and_accuracy():
    script_path = '/home/user/summarize_chains.py'
    db_path = '/app/backup_metadata.db'

    assert os.path.isfile(db_path), f"Database not found at {db_path}"

    # Re-derive the exact expected truth value
    expected_output = get_expected_total_bytes(db_path)

    start_time = time.time()
    try:
        res = subprocess.run(
            [sys.executable, script_path],
            capture_output=True, text=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Script execution timed out (>5 seconds). An index optimization is likely missing.")

    end_time = time.time()
    duration = end_time - start_time

    assert res.returncode == 0, f"Script failed with return code {res.returncode}. stderr: {res.stderr}"

    actual_output = res.stdout.strip()
    assert actual_output == expected_output, f"Output mismatch. Expected: {expected_output}, Got: {actual_output}"

    # Check the metric threshold
    threshold = 0.5
    assert duration <= threshold, f"Execution time threshold exceeded. Metric: {duration:.4f} seconds, Threshold: {threshold} seconds"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
