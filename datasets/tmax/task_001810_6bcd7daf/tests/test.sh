#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_processed_data_exists_and_correct():
    processed_data_path = "/home/user/processed_data.csv"

    assert os.path.isfile(processed_data_path), f"Output file {processed_data_path} does not exist."

    try:
        with open(processed_data_path, "rb") as f:
            raw_content = f.read()
    except Exception as e:
        pytest.fail(f"Could not read {processed_data_path}: {e}")

    try:
        text_content = raw_content.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail(f"The file {processed_data_path} is not valid UTF-8 encoded.")

    lines = [line.strip() for line in text_content.strip().splitlines()]

    expected_lines = [
        "timestamp,comment,sensor_value,rolling_avg",
        "2023-10-01T10:00:00Z,temperature is ok!,45.5,45.5",
        "2023-10-01T10:02:00Z,cooldown,42.0,43.75",
        "2023-10-01T10:03:00Z,steady...,44.5,44.0",
        "2023-10-01T10:05:00Z,all good,46.0,44.17"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} rows (including header), but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        # Handle potential differences in floating point formatting like 45.5 vs 45.50
        # By doing a simple string comparison first
        if actual != expected:
            # If string comparison fails, let's do a more robust CSV row comparison
            actual_parts = actual.split(",")
            expected_parts = expected.split(",")

            assert len(actual_parts) == len(expected_parts), f"Row {i+1} has incorrect number of columns."

            assert actual_parts[0] == expected_parts[0], f"Row {i+1} timestamp mismatch: expected {expected_parts[0]}, got {actual_parts[0]}"
            assert actual_parts[1] == expected_parts[1], f"Row {i+1} comment mismatch: expected '{expected_parts[1]}', got '{actual_parts[1]}'"

            if i > 0: # Skip header for numeric comparison
                try:
                    actual_sensor = float(actual_parts[2])
                    expected_sensor = float(expected_parts[2])
                    assert abs(actual_sensor - expected_sensor) < 1e-5, f"Row {i+1} sensor_value mismatch"

                    actual_rolling = float(actual_parts[3])
                    expected_rolling = float(expected_parts[3])
                    assert abs(actual_rolling - expected_rolling) < 1e-5, f"Row {i+1} rolling_avg mismatch"
                except ValueError:
                    pytest.fail(f"Row {i+1} contains invalid numeric values: {actual}")
            else:
                assert actual == expected, f"Header mismatch: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
