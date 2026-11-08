#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import json
import pytest

DB_PATH = "/home/user/hierarchy.db"
OUTPUT_PATH = "/home/user/output.json"

def test_index_created():
    """Verify that the index idx_parent_id was created correctly."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check if the index exists
    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name='idx_parent_id';")
    result = cursor.fetchone()
    assert result is not None, "Index 'idx_parent_id' was not found in the database."
    assert result[1] == 'nodes', f"Index 'idx_parent_id' is on table '{result[1]}' instead of 'nodes'."

    # Check if the index is on the parent_id column
    cursor.execute("PRAGMA index_info('idx_parent_id');")
    columns = cursor.fetchall()
    assert len(columns) == 1, "Index 'idx_parent_id' should be on exactly one column."
    assert columns[0][2] == 'parent_id', f"Index 'idx_parent_id' is on column '{columns[0][2]}' instead of 'parent_id'."

    conn.close()

def test_json_output():
    """Verify that the JSON output matches the expected schema and data."""
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} does not contain valid JSON.")

    assert "target_node" in data, "JSON is missing the 'target_node' key."
    assert data["target_node"] == 7, f"Expected 'target_node' to be 7, got {data['target_node']}."

    assert "descendants" in data, "JSON is missing the 'descendants' key."
    assert isinstance(data["descendants"], list), "'descendants' must be an array."

    expected_descendants = [12, 14, 19, 25, 30]
    assert data["descendants"] == expected_descendants, (
        f"Expected descendants {expected_descendants}, but got {data['descendants']}. "
        "Ensure descendants are sorted in ascending order."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
