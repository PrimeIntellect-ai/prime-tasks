#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import sqlite3
import subprocess

def get_expected_output(db_path):
    """Compute the expected output directly from the SQLite database."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    query = """
    WITH mutuals AS (
        SELECT a.source_id as n1, a.dependent_id as n2
        FROM edges a
        JOIN edges b ON a.source_id = b.dependent_id AND a.dependent_id = b.source_id
        WHERE a.source_id < a.dependent_id
    ),
    indegrees AS (
        SELECT source_id as node_id, count(*) as deg
        FROM edges
        GROUP BY source_id
    )
    SELECT 
        (SELECT dataset_name FROM nodes WHERE node_id = m.n1) as name1,
        (SELECT dataset_name FROM nodes WHERE node_id = m.n2) as name2,
        COALESCE((SELECT deg FROM indegrees WHERE node_id = m.n1), 0) + 
        COALESCE((SELECT deg FROM indegrees WHERE node_id = m.n2), 0) as combined_deg
    FROM mutuals m;
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()

    expected_lines = []
    for name1, name2, deg in rows:
        # Ensure alphabetical order for the pair
        if name1 > name2:
            name1, name2 = name2, name1
        expected_lines.append(f"{name1},{name2},{deg}")

    # Sort lines alphabetically by the first dataset name
    expected_lines.sort()
    return "\n".join(expected_lines)

def test_script_exists_and_executable():
    """Verify that the script exists and is executable."""
    script_path = "/home/user/find_deadlocks.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

def test_script_output():
    """Verify that the script produces the correct output."""
    script_path = "/home/user/find_deadlocks.sh"
    db_path = "/home/user/datasets.db"

    # Ensure the DB is present for the test to compute truth
    assert os.path.isfile(db_path), f"Database {db_path} is missing."

    expected_output = get_expected_output(db_path)

    try:
        result = subprocess.run([script_path], capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        assert False, f"Script failed with return code {e.returncode}. Stderr: {e.stderr}"

    actual_output = result.stdout.strip()

    assert actual_output == expected_output, (
        f"Script output did not match expected.\n"
        f"Expected:\n{expected_output}\n\n"
        f"Actual:\n{actual_output}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
