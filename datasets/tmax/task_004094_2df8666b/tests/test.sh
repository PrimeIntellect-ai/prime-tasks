#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import pytest

def test_stale_persons_file():
    txt_path = '/home/user/stale_persons.txt'
    assert os.path.exists(txt_path), f"File {txt_path} does not exist."

    with open(txt_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "P_Heidi",
        "P_Grace",
        "P_Frank",
        "P_Eve",
        "P_David"
    ]

    assert lines == expected, f"Content of {txt_path} is incorrect. Expected {expected}, got {lines}."

def test_database_cleaned():
    db_path = '/home/user/graph.db'
    assert os.path.exists(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check that only the valid edges remain
    cursor.execute("SELECT source, target, rel_type FROM edges ORDER BY source, target")
    edges = cursor.fetchall()

    expected_edges = [
        ('P_Alice', 'C_ValidCorp', 'WORKS_FOR'),
        ('P_Bob', 'P_Alice', 'KNOWS')
    ]

    assert edges == expected_edges, f"Edges table is not cleaned correctly. Expected exactly {expected_edges}, got {edges}."

    # Ensure nodes table was not modified
    cursor.execute("SELECT COUNT(*) FROM nodes")
    node_count = cursor.fetchone()[0]
    assert node_count == 9, f"Nodes table should not have been modified. Expected 9 nodes, got {node_count}."

    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
