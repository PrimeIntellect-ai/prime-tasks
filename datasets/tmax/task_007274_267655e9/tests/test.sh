#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

OUTPUT_FILE = "/home/user/web_hourly_metrics.csv"

EXPECTED_DATA = [
    ("2023-11-01 10:00:00", 100, 100.0),
    ("2023-11-01 11:00:00", 100, 100.0),
    ("2023-11-01 12:00:00", 500, 233.33),
    ("2023-11-01 13:00:00", 500, 366.67),
    ("2023-11-01 14:00:00", 250, 416.67),
    ("2023-11-01 15:00:00", 800, 516.67),
    ("2023-11-01 16:00:00", 800, 616.67),
    ("2023-11-01 17:00:00", 600, 733.33),
]

def test_output_file_exists():
    """Verify that the output CSV file was created."""
    assert os.path.exists(OUTPUT_FILE), f"The expected output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a regular file."

def test_output_csv_format_and_content():
    """Verify the CSV headers, row counts, and data values."""
    if not os.path.exists(OUTPUT_FILE):
        pytest.fail(f"Cannot run content checks because {OUTPUT_FILE} is missing.")

    with open(OUTPUT_FILE, "r", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"The file {OUTPUT_FILE} is empty.")

        expected_header = ["timestamp", "max_connections", "rolling_avg_3h"]
        assert header == expected_header, f"CSV header mismatch. Expected {expected_header}, got {header}."

        rows = list(reader)

    assert len(rows) == len(EXPECTED_DATA), f"Expected {len(EXPECTED_DATA)} data rows, but found {len(rows)}."

    for i, (actual_row, expected_row) in enumerate(zip(rows, EXPECTED_DATA)):
        assert len(actual_row) == 3, f"Row {i+1} does not have exactly 3 columns: {actual_row}"

        act_ts, act_max_conn, act_rolling = actual_row
        exp_ts, exp_max_conn, exp_rolling = expected_row

        # Check timestamp
        assert act_ts == exp_ts, f"Row {i+1} timestamp mismatch. Expected '{exp_ts}', got '{act_ts}'."

        # Check max_connections
        try:
            act_max_conn_int = int(act_max_conn)
        except ValueError:
            pytest.fail(f"Row {i+1} max_connections '{act_max_conn}' is not a valid integer.")
        assert act_max_conn_int == exp_max_conn, f"Row {i+1} max_connections mismatch. Expected {exp_max_conn}, got {act_max_conn_int}."

        # Check rolling_avg_3h
        try:
            act_rolling_float = float(act_rolling)
        except ValueError:
            pytest.fail(f"Row {i+1} rolling_avg_3h '{act_rolling}' is not a valid float.")

        # Check precision (allow .0 or .00 for exact integers, otherwise expect 2 decimal places)
        if exp_rolling.is_integer():
            assert act_rolling.endswith(".0") or act_rolling.endswith(".00"), \
                f"Row {i+1} rolling_avg_3h '{act_rolling}' should be formatted to 1 or 2 decimal places."
        else:
            assert len(act_rolling.split(".")[-1]) == 2, \
                f"Row {i+1} rolling_avg_3h '{act_rolling}' should be rounded to exactly 2 decimal places."

        # Check value with a small tolerance for floating point math
        assert abs(act_rolling_float - exp_rolling) < 0.015, \
            f"Row {i+1} rolling_avg_3h mismatch. Expected approx {exp_rolling}, got {act_rolling_float}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
