#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
from datetime import datetime, timedelta
import math

def parse_time(t_str):
    return datetime.strptime(t_str, "%Y-%m-%d %H:%M:%S")

def get_minute_bin(dt):
    return dt.replace(second=0, microsecond=0)

def compute_expected_stats():
    sensor_path = '/home/user/raw_data/sensor.csv'
    state_path = '/home/user/raw_data/state.csv'

    # Read sensor data
    sensor_readings = []
    with open(sensor_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            sensor_readings.append({
                'time': parse_time(row['timestamp']),
                'temp': float(row['temperature_celsius'])
            })

    # Read state data
    state_readings = []
    with open(state_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            state_readings.append({
                'time': parse_time(row['timestamp']),
                'state': row['machine_state']
            })

    if not sensor_readings:
        return {}

    min_time = get_minute_bin(sensor_readings[0]['time'])
    max_time = get_minute_bin(sensor_readings[-1]['time'])

    # Bin sensor data
    binned_temps = {}
    current = min_time
    while current <= max_time:
        binned_temps[current] = []
        current += timedelta(minutes=1)

    for r in sensor_readings:
        bin_t = get_minute_bin(r['time'])
        if bin_t in binned_temps:
            binned_temps[bin_t].append(r['temp'])

    # Calculate means and ffill
    final_temps = {}
    last_val = None
    ffill_count = 0

    current = min_time
    while current <= max_time:
        vals = binned_temps[current]
        if vals:
            avg = sum(vals) / len(vals)
            final_temps[current] = avg
            last_val = avg
            ffill_count = 0
        else:
            if last_val is not None and ffill_count < 2:
                final_temps[current] = last_val
                ffill_count += 1
            else:
                final_temps[current] = None
                last_val = None
                ffill_count = 0
        current += timedelta(minutes=1)

    # Determine states for each bin
    state_readings.sort(key=lambda x: x['time'])
    final_states = {}

    current = min_time
    while current <= max_time:
        # Find the most recent state at or before current
        current_state = "UNKNOWN"
        for sr in state_readings:
            if sr['time'] <= current:
                current_state = sr['state']
            else:
                break
        final_states[current] = current_state
        current += timedelta(minutes=1)

    # Group by state
    summary = {}
    current = min_time
    while current <= max_time:
        st = final_states[current]
        tmp = final_temps[current]

        if st not in summary:
            summary[st] = {'temps': [], 'minutes': 0}

        summary[st]['minutes'] += 1
        if tmp is not None:
            summary[st]['temps'].append(tmp)

        current += timedelta(minutes=1)

    # Format output
    output = {"summary_by_state": {}}
    for st, data in summary.items():
        if data['minutes'] > 0:
            if data['temps']:
                mean_t = round(sum(data['temps']) / len(data['temps']), 2)
            else:
                mean_t = None

            output["summary_by_state"][st] = {
                "mean_temperature": mean_t,
                "total_minutes": data['minutes']
            }

    return output

def test_pipeline_output_exists():
    output_path = '/home/user/pipeline/stats.json'
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

def test_pipeline_output_content():
    output_path = '/home/user/pipeline/stats.json'
    with open(output_path, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} does not contain valid JSON.")

    expected_data = compute_expected_stats()

    assert "summary_by_state" in actual_data, "Missing 'summary_by_state' key in JSON output."

    actual_summary = actual_data["summary_by_state"]
    expected_summary = expected_data["summary_by_state"]

    for state, expected_stats in expected_summary.items():
        assert state in actual_summary, f"State '{state}' is missing from the output."
        actual_stats = actual_summary[state]

        assert "mean_temperature" in actual_stats, f"Missing 'mean_temperature' for state '{state}'."
        assert "total_minutes" in actual_stats, f"Missing 'total_minutes' for state '{state}'."

        assert actual_stats["total_minutes"] == expected_stats["total_minutes"], \
            f"Incorrect total_minutes for state '{state}'. Expected {expected_stats['total_minutes']}, got {actual_stats['total_minutes']}."

        if expected_stats["mean_temperature"] is not None:
            assert math.isclose(actual_stats["mean_temperature"], expected_stats["mean_temperature"], rel_tol=1e-5), \
                f"Incorrect mean_temperature for state '{state}'. Expected {expected_stats['mean_temperature']}, got {actual_stats['mean_temperature']}."
        else:
            assert actual_stats["mean_temperature"] is None, \
                f"Expected mean_temperature for state '{state}' to be null, got {actual_stats['mean_temperature']}."

    for state in actual_summary:
        assert state in expected_summary, f"Unexpected state '{state}' found in the output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
