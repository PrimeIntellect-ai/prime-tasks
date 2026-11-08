#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_fatal_alerts_csv_exists():
    assert os.path.isfile('/home/user/fatal_alerts.csv'), "The file /home/user/fatal_alerts.csv does not exist."

def test_fatal_alerts_csv_content():
    expected_rows = [
        ["timestamp", "error_id"],
        ["2023-10-01T10:05:00Z", "ERR-001"],
        ["2023-10-01T10:10:00Z", "ERR-002"],
        ["2023-10-01T10:20:00Z", "ERR-003"]
    ]

    actual_rows = []
    with open('/home/user/fatal_alerts.csv', 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) > 0, "The CSV file is empty."
    assert actual_rows[0] == expected_rows[0], f"Expected header {expected_rows[0]}, but got {actual_rows[0]}."

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), but got {len(actual_rows)}."

    for i in range(1, len(expected_rows)):
        assert actual_rows[i] == expected_rows[i], f"Row {i} mismatch. Expected {expected_rows[i]}, got {actual_rows[i]}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
