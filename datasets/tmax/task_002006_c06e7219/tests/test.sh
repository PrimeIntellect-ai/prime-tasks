#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import pytest


def test_aligned_sensors_file_exists():
    path = "/home/user/aligned_sensors.csv"
    assert os.path.isfile(path), f"Output file {path} was not created."


def test_aligned_sensors_content():
    path = "/home/user/aligned_sensors.csv"

    expected_data = {
        "2023-10-01T10:00:00Z": (21.0, 1010.0),
        "2023-10-01T10:01:00Z": (22.0, 1010.0),
        "2023-10-01T10:02:00Z": (23.0, 1010.0),
        "2023-10-01T10:03:00Z": (24.0, 1010.0),
        "2023-10-01T10:04:00Z": (25.0, 1010.0),
        "2023-10-01T10:05:00Z": (26.0, 1015.0),
        "2023-10-01T10:06:00Z": (25.0, 1015.0),
        "2023-10-01T10:07:00Z": (24.0, 1015.0),
        "2023-10-01T10:08:00Z": (23.0, 1015.0),
        "2023-10-01T10:09:00Z": (22.0, 1015.0),
        "2023-10-01T10:10:00Z": (21.0, 1015.0),
    }
    expected_timestamps = list(expected_data)

    with open(path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "The CSV file is empty."
        assert header == ["timestamp", "temp", "pressure"], \
            f"CSV header is incorrect. Expected ['timestamp', 'temp', 'pressure'], got {header}."

        rows = list(reader)
        assert len(rows) == 11, f"Expected exactly 11 data rows, got {len(rows)}."

        actual_timestamps = [row[0] for row in rows if len(row) >= 1]
        assert actual_timestamps == expected_timestamps, \
            f"Timestamps must be the complete ordered 1-minute grid. Expected {expected_timestamps}, got {actual_timestamps}."
        assert len(set(actual_timestamps)) == 11, "Each grid timestamp must appear exactly once."

        for row in rows:
            assert len(row) == 3, f"Expected 3 columns per row, got {len(row)} in row: {row}"
            ts, temp_str, press_str = row

            assert ts in expected_data, f"Unexpected or missing timestamp: {ts}"

            e_temp, e_press = expected_data[ts]

            try:
                temp = float(temp_str)
            except ValueError:
                pytest.fail(f"Could not parse temp value as float: {temp_str} at {ts}")

            try:
                press = float(press_str)
            except ValueError:
                pytest.fail(f"Could not parse pressure value as float: {press_str} at {ts}")

            assert math.isfinite(temp), f"Temperature is missing or non-finite at {ts}"
            assert math.isfinite(press), f"Pressure is missing or non-finite at {ts}"

            assert math.isclose(temp, e_temp, rel_tol=1e-5), \
                f"Mismatch in temp at {ts}. Expected {e_temp}, got {temp}"
            assert math.isclose(press, e_press, rel_tol=1e-5), \
                f"Mismatch in pressure at {ts}. Expected {e_press}, got {press}"

            assert 10.0 <= temp <= 50.0, f"Temperature {temp} out of bounds [10.0, 50.0] at {ts}"
            assert 1000.0 <= press <= 1100.0, f"Pressure {press} out of bounds [1000.0, 1100.0] at {ts}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
