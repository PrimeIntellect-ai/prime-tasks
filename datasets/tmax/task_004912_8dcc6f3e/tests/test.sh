#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import zlib
import base64
import pytest

LOG_PATH = '/home/user/config_history.log'
CSV_PATH = '/home/user/connection_changes.csv'

def get_expected_changes():
    """Parse the log file to compute the expected changes."""
    expected_rows = []
    baseline_value = None

    with open(LOG_PATH, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split(' ', 1)
            if len(parts) != 2:
                continue

            ts_str, payload_b64 = parts

            try:
                compressed = base64.b64decode(payload_b64)
                json_bytes = zlib.decompress(compressed)
                data = json.loads(json_bytes.decode('utf-8'))

                max_conn = data.get('database', {}).get('max_connections')
                if max_conn is None:
                    continue

                if baseline_value is None:
                    baseline_value = max_conn
                elif max_conn != baseline_value:
                    expected_rows.append([ts_str, str(baseline_value), str(max_conn)])
                    baseline_value = max_conn
            except Exception:
                pass

    return expected_rows

def test_csv_file_exists():
    """Test that the output CSV file exists."""
    assert os.path.exists(CSV_PATH), f"The expected output file {CSV_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"The path {CSV_PATH} is not a file."

def test_csv_file_contents():
    """Test that the output CSV file contains the correct changes."""
    assert os.path.exists(CSV_PATH), f"Cannot check contents, {CSV_PATH} does not exist."

    expected_changes = get_expected_changes()
    expected_header = ['timestamp', 'old_value', 'new_value']

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"The file {CSV_PATH} is empty."

    header = rows[0]
    assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}."

    actual_changes = rows[1:]
    assert actual_changes == expected_changes, (
        f"CSV contents are incorrect.\n"
        f"Expected changes: {expected_changes}\n"
        f"Actual changes: {actual_changes}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
