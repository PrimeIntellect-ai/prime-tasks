#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_db_import_csv_exists():
    """Test that the output CSV file exists at the correct location."""
    file_path = '/home/user/db_import.csv'
    assert os.path.exists(file_path), f"The output file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_db_import_csv_contents():
    """Test that the output CSV file has the exact expected contents."""
    file_path = '/home/user/db_import.csv'

    expected_rows = [
        ['server_id', 'avg_cpu_norm', 'total_mem_mb'],
        ['srv-01', '0.38', '16384'],
        ['srv-02', '0.85', '16384'],
        ['srv-03', '0.99', '32768']
    ]

    actual_rows = []
    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) > 0, "The output CSV file is empty."
    assert actual_rows[0] == expected_rows[0], f"Expected header {expected_rows[0]}, but got {actual_rows[0]}."

    # Check if the rows match exactly
    assert actual_rows == expected_rows, f"The CSV contents do not match the expected output. Expected: {expected_rows}, Actual: {actual_rows}"

def test_db_import_csv_is_sorted():
    """Test that the output CSV file is sorted alphabetically by server_id."""
    file_path = '/home/user/db_import.csv'

    server_ids = []
    with open(file_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            server_ids.append(row['server_id'])

    assert server_ids == sorted(server_ids), "The output CSV file is not sorted alphabetically by server_id."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
