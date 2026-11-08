#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import csv
import pytest

def test_pipeline_output_matches_database_truth():
    db_path = "/home/user/graph_data.db"
    csv_path = "/home/user/pipeline_out.csv"

    assert os.path.exists(db_path), f"Database file missing at {db_path}"
    assert os.path.exists(csv_path), f"Output CSV missing at {csv_path}"

    # Compute expected results directly from the database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    query = """
        SELECT u.id, u.name, d.name, COUNT(c.user_id_2) as conn_count
        FROM users u
        JOIN departments d ON u.department_id = d.id
        LEFT JOIN connections c ON u.id = c.user_id_1
        GROUP BY u.id, u.name, d.name
        HAVING conn_count > 2
    """

    try:
        cursor.execute(query)
        expected_rows = cursor.fetchall()
    finally:
        conn.close()

    # Convert expected rows to strings to match CSV format
    expected_data = sorted([
        [str(row[0]), str(row[1]), str(row[2]), str(row[3])]
        for row in expected_rows
    ])

    # Read actual results from CSV
    actual_data = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            # Skip empty lines if any
            if not row:
                continue
            # Strip whitespace to be robust against minor formatting differences
            actual_data.append([col.strip() for col in row])

    actual_data_sorted = sorted(actual_data)

    # Verify the output matches exactly
    assert actual_data_sorted == expected_data, (
        f"CSV contents do not match expected results.\n"
        f"Expected: {expected_data}\n"
        f"Actual: {actual_data_sorted}"
    )

def test_no_headers_in_csv():
    csv_path = "/home/user/pipeline_out.csv"
    assert os.path.exists(csv_path), f"Output CSV missing at {csv_path}"

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        first_row = next(reader, None)

    if first_row:
        # If the first row contains 'user_id' or 'department_name', it's likely a header
        assert "user_id" not in first_row[0].lower(), "CSV file should not contain a header row"
        assert not first_row[3].isalpha(), "The fourth column should be a numeric connection count, but found text (possible header)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
