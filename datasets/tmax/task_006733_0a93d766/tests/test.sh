#!/bin/bash
mkdir -p /logs/verifier

SRC=/home/user/audit_graph.c
BIN=/home/user/audit_graph
CSV=/home/user/co_access_graph.csv

# Force the submitted C source to produce both required artifacts.
rm -f "$BIN" "$CSV"
if [ ! -f "$SRC" ] || ! gcc "$SRC" -o "$BIN" -lsqlite3 || [ ! -x "$BIN" ] || ! "$BIN"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shutil
import sqlite3
import subprocess
import uuid
import pytest

DB_PATH = "/home/user/audit.db"
CSV_PATH = "/home/user/co_access_graph.csv"
C_SRC_PATH = "/home/user/audit_graph.c"
BIN_PATH = "/home/user/audit_graph"

QUERY = """
WITH aggregated_access AS (
    SELECT emp_id, resource_id, SUM(access_count) as total_access
    FROM access_logs
    GROUP BY emp_id, resource_id
)
SELECT
    m.emp_id AS Manager_ID,
    s.emp_id AS Subordinate_ID,
    a1.resource_id AS Resource_ID,
    a1.total_access AS Manager_Total_Accesses,
    a2.total_access AS Subordinate_Total_Accesses
FROM employees s
JOIN employees m ON s.manager_id = m.emp_id
JOIN aggregated_access a1 ON m.emp_id = a1.emp_id
JOIN aggregated_access a2 ON s.emp_id = a2.emp_id AND a1.resource_id = a2.resource_id
ORDER BY Manager_ID ASC, Subordinate_ID ASC, Resource_ID ASC;
"""

def expected_rows():
    conn = sqlite3.connect(DB_PATH)
    try:
        return conn.execute(QUERY).fetchall()
    finally:
        conn.close()

def actual_rows():
    rows = []
    with open(CSV_PATH, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            assert len(row) == 5, f"Expected 5 columns in CSV, got {len(row)} in row: {row}"
            try:
                rows.append((int(row[0]), int(row[1]), row[2], int(row[3]), int(row[4])))
            except ValueError as e:
                pytest.fail(f"Failed to parse CSV row as expected types (integers for IDs and counts): {row}. Error: {e}")
    return rows

def test_c_source_exists():
    """Test that the C source code file was created."""
    assert os.path.exists(C_SRC_PATH), f"C source file missing at {C_SRC_PATH}"
    assert os.path.isfile(C_SRC_PATH), f"Path {C_SRC_PATH} is not a file"

def test_compiled_program_exists():
    assert os.path.isfile(BIN_PATH), f"Compiled program missing at {BIN_PATH}"
    assert os.access(BIN_PATH, os.X_OK), f"Compiled program is not executable: {BIN_PATH}"
    with open(BIN_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "Compiled program is not an ELF executable"

def test_source_uses_sqlite3_c_api():
    source = open(C_SRC_PATH, 'r', encoding='utf-8').read()
    assert re.search(r'#\s*include\s*[<\"]sqlite3\.h[>\"]', source), "Source must include sqlite3.h"
    result = subprocess.run(['nm', '-D', BIN_PATH], text=True, capture_output=True, check=True)
    symbols = result.stdout + result.stderr
    assert re.search(r'\bsqlite3_open(?:16|_v2)?(?:@|\b)', symbols), "Program does not reference a SQLite3 open API"
    assert re.search(r'\bsqlite3_(?:exec|get_table|prepare(?:16|_v2|_v3)?)(?:@|\b)', symbols), "Program does not reference a SQLite3 query API"

def test_output_csv_exists():
    """Test that the output CSV file was generated."""
    assert os.path.exists(CSV_PATH), f"Output CSV missing at {CSV_PATH}"
    assert os.path.isfile(CSV_PATH), f"Path {CSV_PATH} is not a file"

def test_co_access_graph_contents():
    """Test that the CSV contents exactly match the expected co-access graph."""
    assert os.path.exists(DB_PATH), f"Database missing at {DB_PATH}"
    assert os.path.exists(CSV_PATH), f"Output CSV missing at {CSV_PATH}"

    expected = expected_rows()
    actual = actual_rows()

    assert len(actual) == len(expected), \
        f"Expected {len(expected)} rows in the CSV, but found {len(actual)}."
    for i, (actual_row, expected_row) in enumerate(zip(actual, expected)):
        assert actual_row == expected_row, \
            f"Row {i+1} mismatch. Expected {expected_row}, got {actual_row}. Ensure correct sorting and aggregation."

def test_program_recomputes_from_database():
    """Run the compiled submission against unpredictably modified database data."""
    backup = '/tmp/audit.db.verifier-backup'
    shutil.copy2(DB_PATH, backup)
    token = 'VERIFY_' + uuid.uuid4().hex
    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("UPDATE access_logs SET access_count = access_count + 19 WHERE emp_id = 1 AND resource_id = 'RES_A'")
            conn.executemany(
                'INSERT INTO employees(emp_id, manager_id, name) VALUES (?, ?, ?)',
                [(900001, None, 'Verifier Manager'), (900002, 900001, 'Verifier Subordinate')]
            )
            conn.executemany(
                'INSERT INTO access_logs(emp_id, resource_id, access_count) VALUES (?, ?, ?)',
                [(900001, token, 11), (900001, token, 17), (900002, token, 5), (900002, token, 23)]
            )
            conn.commit()
        finally:
            conn.close()

        expected = expected_rows()
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        result = subprocess.run([BIN_PATH], text=True, capture_output=True, timeout=15)
        assert result.returncode == 0, f"Compiled program failed: {result.stderr}"
        assert os.path.isfile(CSV_PATH), "Program did not create the CSV when executed"
        assert actual_rows() == expected, "Program did not recompute the graph from changed database contents"
    finally:
        shutil.copy2(backup, DB_PATH)
        subprocess.run([BIN_PATH], timeout=15, check=False)
        os.remove(backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
