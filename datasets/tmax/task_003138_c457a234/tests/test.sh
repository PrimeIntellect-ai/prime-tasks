#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_hourly_rolling_stats_csv():
    output_file_path = "/home/user/hourly_rolling_stats.csv"

    # Check if the output file was created
    assert os.path.isfile(output_file_path), f"Output file {output_file_path} does not exist. The script may not have run or failed to save the output."

    expected_rows = [
        ["hour_bucket", "change_count", "rolling_3h_sum"],
        ["2023-11-01 08:00:00", "2", "2"],
        ["2023-11-01 09:00:00", "1", "3"],
        ["2023-11-01 10:00:00", "0", "3"],
        ["2023-11-01 11:00:00", "3", "4"],
        ["2023-11-01 12:00:00", "1", "4"],
        ["2023-11-01 13:00:00", "0", "4"],
        ["2023-11-01 14:00:00", "1", "2"]
    ]

    # Read the actual CSV content
    with open(output_file_path, "r", newline="") as f:
        reader = csv.reader(f)
        # Read all rows, ignoring any trailing empty lines
        actual_rows = [row for row in reader if row]

    # Verify the number of rows
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows in the CSV, but got {len(actual_rows)}. "
        "Check if all missing hourly buckets were filled and the correct time range was used."
    )

    # Verify each row matches exactly
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, (
            f"Row {i+1} mismatch:\n"
            f"  Expected: {expected}\n"
            f"  Actual:   {actual}\n"
            "Ensure the headers, hour buckets, change counts, and rolling 3-hour sums are calculated correctly."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
