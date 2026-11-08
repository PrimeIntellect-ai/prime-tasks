#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
from datetime import datetime, timezone

def get_expected_data():
    """
    Derive the expected output from the input files to act as the source of truth.
    """
    csv_path = "/home/user/data/run_1.csv"
    json_path = "/home/user/data/retry_1.json"

    records = []

    if os.path.exists(csv_path):
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                ts = float(row['ts'])
                dt = datetime.fromtimestamp(ts, tz=timezone.utc)
                rounded_ts = round(dt.timestamp())
                rounded_dt = datetime.fromtimestamp(rounded_ts, tz=timezone.utc)

                val_a = float(row['sensor_a']) if row['sensor_a'] else None
                val_b = float(row['sensor_b']) if row['sensor_b'] else None

                records.append({
                    'dt': rounded_dt,
                    'a': val_a,
                    'b': val_b
                })

    if os.path.exists(json_path):
        with open(json_path, 'r') as f:
            for line in f:
                if not line.strip(): 
                    continue
                data = json.loads(line)
                dt = datetime.fromisoformat(data['datetime']).astimezone(timezone.utc)
                rounded_ts = round(dt.timestamp())
                rounded_dt = datetime.fromtimestamp(rounded_ts, tz=timezone.utc)

                records.append({
                    'dt': rounded_dt,
                    'a': data.get('val_a'),
                    'b': data.get('val_b')
                })

    # Group by rounded UTC timestamp
    groups = {}
    for r in records:
        dt_str = r['dt'].strftime('%Y-%m-%dT%H:%M:%SZ')
        if dt_str not in groups:
            groups[dt_str] = {'a': [], 'b': []}
        if r['a'] is not None:
            groups[dt_str]['a'].append(r['a'])
        if r['b'] is not None:
            groups[dt_str]['b'].append(r['b'])

    # Calculate means and filter
    final_records = []
    for dt_str in sorted(groups.keys()):
        a_vals = groups[dt_str]['a']
        b_vals = groups[dt_str]['b']

        if not a_vals or not b_vals:
            continue

        mean_a = sum(a_vals) / len(a_vals)
        mean_b = sum(b_vals) / len(b_vals)

        final_records.append({
            'timestamp': dt_str,
            'sensor_a': mean_a,
            'sensor_b': mean_b
        })

    # Calculate Euclidean distance
    sq_sum = 0.0
    for r in final_records:
        sq_sum += (r['sensor_a'] - r['sensor_b']) ** 2
    distance = math.sqrt(sq_sum)

    return final_records, distance


def test_cleaned_data_csv_exists():
    assert os.path.isfile("/home/user/cleaned_data.csv"), "The output file /home/user/cleaned_data.csv does not exist."

def test_distance_txt_exists():
    assert os.path.isfile("/home/user/distance.txt"), "The output file /home/user/distance.txt does not exist."

def test_cleaned_data_content():
    expected_records, _ = get_expected_data()

    with open("/home/user/cleaned_data.csv", "r") as f:
        reader = csv.DictReader(f)
        actual_records = list(reader)

    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} rows in cleaned_data.csv, but got {len(actual_records)}."

    for i, (act, exp) in enumerate(zip(actual_records, expected_records)):
        assert act['timestamp'] == exp['timestamp'], f"Row {i+1}: Expected timestamp {exp['timestamp']}, got {act['timestamp']}."

        act_a = float(act['sensor_a'])
        act_b = float(act['sensor_b'])

        assert abs(act_a - exp['sensor_a']) < 1e-3, f"Row {i+1}: Expected sensor_a {exp['sensor_a']:.3f}, got {act_a}."
        assert abs(act_b - exp['sensor_b']) < 1e-3, f"Row {i+1}: Expected sensor_b {exp['sensor_b']:.3f}, got {act_b}."

        # Check formatting (rounded to 3 decimal places)
        assert "." in act['sensor_a'] and len(act['sensor_a'].split('.')[1]) == 3, f"Row {i+1}: sensor_a is not rounded to 3 decimal places."
        assert "." in act['sensor_b'] and len(act['sensor_b'].split('.')[1]) == 3, f"Row {i+1}: sensor_b is not rounded to 3 decimal places."

def test_distance_content():
    _, expected_dist = get_expected_data()

    with open("/home/user/distance.txt", "r") as f:
        content = f.read().strip()

    try:
        actual_dist = float(content)
    except ValueError:
        pytest.fail("The content of distance.txt is not a valid float.")

    assert abs(actual_dist - expected_dist) < 1e-2, f"Expected distance approximately {expected_dist:.2f}, got {actual_dist}."

    # Check formatting (rounded to 2 decimal places)
    assert "." in content and len(content.split('.')[1]) == 2, "The distance value in distance.txt is not rounded to 2 decimal places."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
