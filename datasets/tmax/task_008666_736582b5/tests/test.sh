#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import pytest

def test_process_script_exists():
    """Check if the processing script was created."""
    script_path = "/home/user/process_data.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."

def test_output_file_exists():
    """Check if the processed measurements CSV was generated."""
    output_file = "/home/user/data/processed_measurements.csv"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"Path {output_file} is not a file."

def test_output_file_contents():
    """Validate the contents of the processed measurements CSV against the reference logic."""
    input_file = "/home/user/data/sensor_logs.csv"
    output_file = "/home/user/data/processed_measurements.csv"

    assert os.path.exists(input_file), f"Input file {input_file} is missing."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    expected_rows = []
    with open(input_file, 'r', newline='') as infile:
        reader = csv.reader(infile)
        headers = next(reader)

        expected_rows.append(['timestamp', 'sensor_id', 'true_value'])

        for row in reader:
            timestamp, sensor_id, metadata_json, raw_value = row

            # 1. Typo correction
            sensor_id = sensor_id.replace('sensro_', 'sensor_')

            # 2 & 3. Data extraction, calculation, and filtering
            metadata = json.loads(metadata_json)
            if metadata.get('status') != 'active':
                continue

            offset = metadata['calibration']['offset']
            multiplier = metadata['calibration']['multiplier']
            raw_val = float(raw_value)

            true_value = (raw_val + offset) * multiplier
            true_value_rounded = f"{true_value:.2f}"

            expected_rows.append([timestamp, sensor_id, true_value_rounded])

    with open(output_file, 'r', newline='') as outfile:
        reader = csv.reader(outfile)
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), (
        f"Row count mismatch. Expected {len(expected_rows)} rows, but got {len(actual_rows)} rows."
    )

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, (
            f"Row {i + 1} mismatch.\nExpected: {expected}\nActual: {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
