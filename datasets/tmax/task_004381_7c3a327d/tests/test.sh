#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_clean_alerts_exists():
    """Check if the output file exists."""
    file_path = "/home/user/clean_alerts.csv"
    assert os.path.exists(file_path), f"The expected output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a regular file."

def test_clean_alerts_content():
    """Verify the contents of the clean_alerts.csv file."""
    file_path = "/home/user/clean_alerts.csv"

    expected_rows = [
        ["timestamp", "imputed_value", "normalized_desc", "is_anomaly"],
        ["1001", "45.0", "system start", "0"],
        ["1002", "46.2", "all good", "0"],
        ["1003", "46.2", "running smoothly", "0"],
        ["1004", "47.1", "temp normal", "0"],
        ["1005", "95.5", "warning overheat", "1"],
        ["1006", "95.5", "cooling down", "1"],
        ["1007", "48.0", "recovered", "0"],
        ["1008", "49.0", "status ok", "0"],
        ["1009", "48.5", "status ok", "0"]
    ]

    actual_rows = []
    with open(file_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            # Strip whitespace from each field for robust comparison
            actual_rows.append([col.strip() for col in row])

    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows (including header), "
        f"but got {len(actual_rows)} rows."
    )

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, (
            f"Row {i + 1} mismatch.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
