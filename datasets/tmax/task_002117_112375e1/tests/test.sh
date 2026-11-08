#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math

def test_cleaned_merged_exists():
    assert os.path.exists('/home/user/cleaned_merged.csv'), "The output file /home/user/cleaned_merged.csv does not exist."
    assert os.path.isfile('/home/user/cleaned_merged.csv'), "/home/user/cleaned_merged.csv is not a file."

def test_cleaned_merged_content():
    # 1. Derive expected data from inputs
    sensor_data_path = '/home/user/sensor_data.csv'
    maintenance_path = '/home/user/maintenance.csv'

    assert os.path.exists(sensor_data_path), f"Missing input file {sensor_data_path}"
    assert os.path.exists(maintenance_path), f"Missing input file {maintenance_path}"

    # Read maintenance data
    maintenance_dict = {}
    with open(maintenance_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            maintenance_dict[(row['hour'], row['sensor_id'])] = row['status']

    # Read and process sensor data
    groups = {}
    with open(sensor_data_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = row.get('timestamp', '')
            sid = row.get('sensor_id', '')
            temp_str = row.get('temperature', '')
            hum_str = row.get('humidity', '')

            if not ts or not sid or not temp_str or not hum_str:
                continue

            try:
                temp = float(temp_str)
                hum = float(hum_str)
            except ValueError:
                continue

            if math.isnan(temp) or math.isnan(hum):
                continue

            if not (-20.0 <= temp <= 50.0):
                continue
            if not (0.0 <= hum <= 100.0):
                continue

            # Bucket to hour
            # e.g. 2023-10-01T10:15:30Z -> 2023-10-01T10:00:00Z
            hour = ts[:13] + ':00:00Z'

            key = (hour, sid)
            if key not in groups:
                groups[key] = {'temp': [], 'hum': []}
            groups[key]['temp'].append(temp)
            groups[key]['hum'].append(hum)

    expected_rows = []
    for (hour, sid), vals in groups.items():
        avg_temp = sum(vals['temp']) / len(vals['temp'])
        avg_hum = sum(vals['hum']) / len(vals['hum'])

        # Round to exactly 2 decimal places
        avg_temp_str = f"{avg_temp:.2f}"
        avg_hum_str = f"{avg_hum:.2f}"

        status = maintenance_dict.get((hour, sid), "unknown")

        expected_rows.append({
            'hour': hour,
            'sensor_id': sid,
            'avg_temperature': avg_temp_str,
            'avg_humidity': avg_hum_str,
            'status': status
        })

    # Sort expected rows
    expected_rows.sort(key=lambda x: (x['hour'], x['sensor_id']))

    # 2. Read actual data
    actual_rows = []
    actual_headers = []
    with open('/home/user/cleaned_merged.csv', 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            actual_headers = next(reader)
        except StopIteration:
            assert False, "The file /home/user/cleaned_merged.csv is empty."

        for row in reader:
            if not any(row): continue
            actual_rows.append(row)

    expected_headers = ['hour', 'sensor_id', 'avg_temperature', 'avg_humidity', 'status']
    assert actual_headers == expected_headers, f"Headers mismatch. Expected {expected_headers}, got {actual_headers}"

    assert len(actual_rows) == len(expected_rows), f"Row count mismatch. Expected {len(expected_rows)} rows, got {len(actual_rows)} rows."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        # actual is a list, expected is a dict
        assert len(actual) == 5, f"Row {i+1} does not have 5 columns."

        assert actual[0] == expected['hour'], f"Row {i+1} hour mismatch: expected {expected['hour']}, got {actual[0]}"
        assert actual[1] == expected['sensor_id'], f"Row {i+1} sensor_id mismatch: expected {expected['sensor_id']}, got {actual[1]}"

        # compare floats to tolerate minor formatting differences like "23.0" vs "23.00" if the student didn't strictly format strings, 
        # but the spec says "exactly 2 decimal places" so we can enforce string match or float match.
        # Let's check float values but enforce the string representation if possible, or just float equality to be robust.
        try:
            act_temp = float(actual[2])
            exp_temp = float(expected['avg_temperature'])
            assert math.isclose(act_temp, exp_temp, rel_tol=1e-5), f"Row {i+1} avg_temperature mismatch: expected {exp_temp}, got {act_temp}"
        except ValueError:
            assert False, f"Row {i+1} avg_temperature is not a valid float: {actual[2]}"

        try:
            act_hum = float(actual[3])
            exp_hum = float(expected['avg_humidity'])
            assert math.isclose(act_hum, exp_hum, rel_tol=1e-5), f"Row {i+1} avg_humidity mismatch: expected {exp_hum}, got {act_hum}"
        except ValueError:
            assert False, f"Row {i+1} avg_humidity is not a valid float: {actual[3]}"

        assert actual[4] == expected['status'], f"Row {i+1} status mismatch: expected {expected['status']}, got {actual[4]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
