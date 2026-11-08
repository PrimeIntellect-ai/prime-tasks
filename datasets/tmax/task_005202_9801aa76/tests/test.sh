#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
from datetime import datetime, timedelta

def test_cleaned_file_exists():
    output_path = '/home/user/cleaned_dev_42.csv'
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Output path {output_path} is not a file."

def test_cleaned_file_content():
    input_path = '/home/user/sensor_data.csv'
    output_path = '/home/user/cleaned_dev_42.csv'

    assert os.path.exists(input_path), f"Input file {input_path} is missing."

    # Read and process input to compute the expected output
    raw_data = []
    with open(input_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['device_id'] == 'dev_42':
                # Parse timestamp and truncate to minute
                dt = datetime.strptime(row['timestamp'], "%Y-%m-%dT%H:%M:%SZ")
                dt_min = dt.replace(second=0, microsecond=0)
                raw_data.append((dt_min, float(row['temperature'])))

    # Aggregate by minute
    agg_data = {}
    for dt, temp in raw_data:
        if dt not in agg_data:
            agg_data[dt] = []
        agg_data[dt].append(temp)

    for dt in agg_data:
        agg_data[dt] = sum(agg_data[dt]) / len(agg_data[dt])

    sorted_dts = sorted(agg_data.keys())

    expected_rows = []
    if sorted_dts:
        expected_rows.append((sorted_dts[0], agg_data[sorted_dts[0]]))
        for i in range(1, len(sorted_dts)):
            prev_dt = sorted_dts[i-1]
            curr_dt = sorted_dts[i]
            diff_minutes = int((curr_dt - prev_dt).total_seconds() // 60)

            # If there are 1 to 5 missing minutes, the difference in minutes is between 2 and 6
            if 1 < diff_minutes <= 6:
                for m in range(1, diff_minutes):
                    fill_dt = prev_dt + timedelta(minutes=m)
                    expected_rows.append((fill_dt, agg_data[prev_dt]))

            expected_rows.append((curr_dt, agg_data[curr_dt]))

    expected_csv = [["timestamp", "device_id", "avg_temperature"]]
    for dt, temp in expected_rows:
        expected_csv.append([
            dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "dev_42",
            f"{temp:.2f}"
        ])

    # Read actual output
    with open(output_path, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_csv = list(reader)

    assert len(actual_csv) == len(expected_csv), f"Expected {len(expected_csv)} rows in {output_path}, got {len(actual_csv)}."

    for i, (actual, expected) in enumerate(zip(actual_csv, expected_csv)):
        assert actual == expected, f"Row {i} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
