#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import struct
import pytest

DB_PATH = '/home/user/topology.db'
OUTPUT_FILE = '/home/user/min_latency.txt'
INITIAL_CHANGE_COUNTER = 4

def get_expected_min_latency(db_path):
    """Dynamically compute the expected minimum latency for compute-only triangles."""
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    query = """
        SELECT MIN(e1.latency + e2.latency + e3.latency)
        FROM edges e1
        JOIN edges e2 ON e1.dst = e2.src
        JOIN edges e3 ON e2.dst = e3.src AND e3.dst = e1.src
        JOIN nodes n1 ON e1.src = n1.id
        JOIN nodes n2 ON e2.src = n2.id
        JOIN nodes n3 ON e3.src = n3.id
        WHERE n1.role = 'compute'
          AND n2.role = 'compute'
          AND n3.role = 'compute'
    """
    c.execute(query)
    result = c.fetchone()[0]
    conn.close()
    return result

def test_database_integrity():
    """Verify that the required index repair occurred and left a valid index."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Flush any legitimate repair performed while the database was in WAL mode.
    c.execute("PRAGMA wal_checkpoint(TRUNCATE)")

    # Keep the original index-existence assertion.
    c.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edges_src'")
    index_exists = c.fetchone()
    assert index_exists is not None, "Index 'idx_edges_src' is missing. It should have been recreated or kept intact."

    # Verify that it is actually an index on edges(src), not merely an object
    # with the expected name.
    c.execute("PRAGMA index_list('edges')")
    assert any(row[1] == 'idx_edges_src' for row in c.fetchall()), "idx_edges_src is not an index on edges."
    c.execute("PRAGMA index_info('idx_edges_src')")
    indexed_columns = [row[2] for row in c.fetchall()]
    assert indexed_columns == ['src'], f"idx_edges_src must index only edges(src), got {indexed_columns}."

    c.execute("PRAGMA integrity_check")
    assert c.fetchone()[0] == 'ok', "Database or index integrity check failed."
    conn.close()

    # The pristine database has change counter 4. DROP/CREATE or REINDEX is a
    # committed write transaction and must advance this persistent counter.
    with open(DB_PATH, 'rb') as f:
        f.seek(24)
        change_counter = struct.unpack('>I', f.read(4))[0]
    assert change_counter > INITIAL_CHANGE_COUNTER, (
        "No database repair write was detected; run REINDEX or drop and recreate idx_edges_src."
    )

def test_min_latency_output():
    """Verify that the output file contains the correct minimum latency."""
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

    with open(OUTPUT_FILE, 'r') as f:
        content = f.read().strip()

    assert content.isdigit(), f"Output file should contain only an integer, got: {content}"

    actual_val = int(content)
    expected_val = get_expected_min_latency(DB_PATH)

    assert expected_val is not None, "No compute-only triangles found in the database."
    assert actual_val == expected_val, f"Incorrect minimum latency. Expected {expected_val}, got {actual_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
