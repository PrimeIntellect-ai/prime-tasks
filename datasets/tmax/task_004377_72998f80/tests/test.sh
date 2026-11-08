#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
from datetime import datetime, timedelta

def process_data(raw_path):
    with open(raw_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    # Deduplicate (keep first occurrence)
    seen = set()
    dedup_rows = []
    for row in rows:
        # Create a tuple of all values to hash
        tup = tuple(row.items())
        if tup not in seen:
            seen.add(tup)
            dedup_rows.append(row)

    # Parse timestamps and sort
    for row in dedup_rows:
        row['timestamp'] = datetime.strptime(row['timestamp'], '%Y-%m-%d %H:%M:%S')

    dedup_rows.sort(key=lambda x: x['timestamp'])

    if not dedup_rows:
        return []

    # Resample 1H and ffill
    min_time = dedup_rows[0]['timestamp']
    max_time = dedup_rows[-1]['timestamp']

    resampled_rows = []
    current_time = min_time

    # Create a mapping of time to row
    time_to_row = {r['timestamp']: r for r in dedup_rows}

    last_known = None
    while current_time <= max_time:
        if current_time in time_to_row:
            last_known = time_to_row[current_time]

        # Copy the last known row and update timestamp
        new_row = dict(last_known)
        new_row['timestamp'] = current_time
        resampled_rows.append(new_row)

        current_time += timedelta(hours=1)

    # Reshape to long format
    long_rows = []
    for row in resampled_rows:
        ts_str = row['timestamp'].strftime('%Y-%m-%d %H:%M:%S')
        for room in ['room_A', 'room_B', 'room_C']:
            val = row[room]
            long_rows.append({
                'timestamp': ts_str,
                'room': room,
                'temperature': val
            })

    # Sort primarily by timestamp, secondarily by room
    long_rows.sort(key=lambda x: (x['timestamp'], x['room']))
    return long_rows

def test_processed_sensors_exists_and_correct():
    raw_path = "/home/user/raw_sensors.csv"
    processed_path = "/home/user/processed_sensors.csv"

    assert os.path.isfile(processed_path), f"Expected output file {processed_path} is missing."

    expected_data = process_data(raw_path)

    with open(processed_path, 'r') as f:
        reader = csv.DictReader(f)
        actual_data = list(reader)

    assert reader.fieldnames == ['timestamp', 'room', 'temperature'], \
        f"Expected columns ['timestamp', 'room', 'temperature'], got {reader.fieldnames}"

    assert len(actual_data) == len(expected_data), \
        f"Expected {len(expected_data)} rows, got {len(actual_data)} rows."

    for i, (expected, actual) in enumerate(zip(expected_data, actual_data)):
        assert actual['timestamp'] == expected['timestamp'], \
            f"Row {i+1}: Expected timestamp {expected['timestamp']}, got {actual['timestamp']}"
        assert actual['room'] == expected['room'], \
            f"Row {i+1}: Expected room {expected['room']}, got {actual['room']}"

        # Compare temperatures, handling empty strings or specific formats
        # Since we are reading from CSV, we compare as floats if possible
        exp_temp = expected['temperature']
        act_temp = actual['temperature']

        if exp_temp == '' or exp_temp.lower() == 'nan':
            assert act_temp == '' or act_temp.lower() == 'nan', \
                f"Row {i+1}: Expected NaN temperature, got {act_temp}"
        else:
            try:
                exp_val = float(exp_temp)
                act_val = float(act_temp)
                assert abs(exp_val - act_val) < 1e-6, \
                    f"Row {i+1}: Expected temperature {exp_val}, got {act_val}"
            except ValueError:
                assert act_temp == exp_temp, \
                    f"Row {i+1}: Expected temperature {exp_temp}, got {act_temp}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
