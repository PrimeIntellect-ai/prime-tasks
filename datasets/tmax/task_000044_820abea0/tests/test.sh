#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_asset_report_exists():
    assert os.path.isfile('/home/user/asset_report.csv'), "The file /home/user/asset_report.csv does not exist."

def test_asset_report_content():
    report_path = '/home/user/asset_report.csv'
    assert os.path.isfile(report_path), "The file /home/user/asset_report.csv does not exist."

    with open(report_path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) >= 1, "The CSV file is empty or missing the header."

    header = rows[0]
    expected_header = ['filename', 'asset_id', 'type', 'version']
    assert header == expected_header, f"Expected header {expected_header}, but got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 2, f"Expected 2 data rows, but got {len(data_rows)}"

    expected_rows = [
        ['file_A', 'A101', 'texture', '1.2'],
        ['file_B', 'B202', 'model', '2.0']
    ]

    # Check if rows are sorted by filename
    filenames = [row[0] for row in data_rows]
    assert filenames == sorted(filenames), "The rows are not sorted alphabetically by the filename column."

    # Check exact content
    assert data_rows == expected_rows, f"Expected data rows {expected_rows}, but got {data_rows}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
