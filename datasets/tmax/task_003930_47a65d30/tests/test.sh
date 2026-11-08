#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_output_file_exists():
    output_path = "/home/user/output/hourly_distance.csv"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

def test_output_file_contents():
    output_path = "/home/user/output/hourly_distance.csv"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    try:
        with open(output_path, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            rows = list(reader)
    except UnicodeDecodeError:
        assert False, f"Output file {output_path} is not valid UTF-8."

    assert len(rows) > 0, "Output file is empty."

    # Check header
    assert rows[0] == ["hour", "distance"], f"Header is incorrect. Expected ['hour', 'distance'], got {rows[0]}"

    # Recompute expected data based on the known input:
    # Sensor A:
    # 08:15 -> 10.0, 08:45 -> 20.0 (duplicate removed) => 08:00 Avg = 15.0
    # 09:10 -> 15.5 => 09:00 Avg = 15.5
    # 10:05 -> 100.0 => 10:00 Avg = 100.0
    # Sensor B:
    # 08:05 -> 12.0, 08:55 -> 14.0 => 08:00 Avg = 13.0
    # 09:30 -> 15.5 (duplicate removed) => 09:00 Avg = 15.5
    # 11:00 -> 50.0 => 11:00 Avg = 50.0
    # Intersections:
    # 08:00 -> |15.0 - 13.0| = 2.0
    # 09:00 -> |15.5 - 15.5| = 0.0

    expected_data = [
        ["2023-10-01T08:00:00Z", "2.0"],
        ["2023-10-01T09:00:00Z", "0.0"]
    ]

    # Strip whitespace just in case
    cleaned_rows = [[col.strip() for col in row] for row in rows[1:] if any(col.strip() for col in row)]

    assert cleaned_rows == expected_data, f"Data rows are incorrect.\nExpected: {expected_data}\nGot: {cleaned_rows}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
