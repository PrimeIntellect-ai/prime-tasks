#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
from datetime import datetime, timedelta

def test_cleaned_sensor_data():
    raw_path = "/home/user/raw_sensor_data.csv"
    out_path = "/home/user/cleaned_sensor_data.csv"

    assert os.path.exists(out_path), f"Output file {out_path} is missing."

    raw_data = []
    with open(raw_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_data.append({
                'ts': datetime.strptime(row['ts'], "%Y-%m-%d %H:%M:%S"),
                'sensor': row['sensor'],
                'temp': float(row['temp']),
                'etl_run': int(row['etl_run'])
            })

    # 1. Deduplicate
    dedup = {}
    for r in raw_data:
        key = (r['ts'], r['sensor'])
        if key not in dedup or r['etl_run'] > dedup[key]['etl_run']:
            dedup[key] = r

    # Find global min and max ts
    all_ts = [r['ts'] for r in dedup.values()]
    min_ts = min(all_ts)
    max_ts = max(all_ts)

    # Generate full timeline (5-minute intervals)
    timeline = []
    curr = min_ts
    while curr <= max_ts:
        timeline.append(curr)
        curr += timedelta(minutes=5)

    sensors = sorted(list(set(r['sensor'] for r in dedup.values())))

    expected_rows = []
    for sensor in sensors:
        # Get data for sensor
        sensor_data = {k[0]: v['temp'] for k, v in dedup.items() if k[1] == sensor}

        # 2. Resampling & Gap-Filling
        temps = []
        for t in timeline:
            temps.append(sensor_data.get(t, None))

        first_idx = next((i for i, v in enumerate(temps) if v is not None), None)
        last_idx = next((i for i in range(len(temps)-1, -1, -1) if temps[i] is not None), None)

        if first_idx is None:
            continue

        interp_temps = list(temps)
        for i in range(first_idx, last_idx + 1):
            if interp_temps[i] is None:
                # Find prev and next for linear interpolation
                prev_i = i - 1
                while interp_temps[prev_i] is None:
                    prev_i -= 1
                next_i = i + 1
                while interp_temps[next_i] is None:
                    next_i += 1

                prev_val = interp_temps[prev_i]
                next_val = interp_temps[next_i]
                interp_temps[i] = prev_val + (next_val - prev_val) * (i - prev_i) / (next_i - prev_i)

        # 3. Rolling Aggregation
        rolling_temps = []
        for i in range(len(interp_temps)):
            window = interp_temps[max(0, i-5):i+1]
            valid = [v for v in window if v is not None]
            if not valid:
                rolling_temps.append(None)
            else:
                rolling_temps.append(round(sum(valid) / len(valid), 2))

        # 4. Final Formatting
        for t, r_temp in zip(timeline, rolling_temps):
            if r_temp is not None:
                expected_rows.append({
                    'ts': t.strftime("%Y-%m-%d %H:%M:%S"),
                    'sensor': sensor,
                    'rolling_temp': f"{r_temp:.2f}"
                })

    # Read and verify output
    out_rows = []
    with open(out_path, 'r') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['ts', 'sensor', 'rolling_temp'], f"Incorrect columns in output: {reader.fieldnames}"
        for row in reader:
            try:
                dt = datetime.strptime(row['ts'], "%Y-%m-%d %H:%M:%S")
                row['ts'] = dt.strftime("%Y-%m-%d %H:%M:%S")
            except ValueError:
                pass
            try:
                row['rolling_temp'] = f"{float(row['rolling_temp']):.2f}"
            except ValueError:
                pass
            out_rows.append(row)

    assert len(out_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(out_rows)} rows in the output CSV."

    for i, (out_r, exp_r) in enumerate(zip(out_rows, expected_rows)):
        assert out_r['ts'] == exp_r['ts'], f"Row {i} 'ts' mismatch: expected {exp_r['ts']}, got {out_r['ts']}"
        assert out_r['sensor'] == exp_r['sensor'], f"Row {i} 'sensor' mismatch: expected {exp_r['sensor']}, got {out_r['sensor']}"
        assert out_r['rolling_temp'] == exp_r['rolling_temp'], f"Row {i} 'rolling_temp' mismatch: expected {exp_r['rolling_temp']}, got {out_r['rolling_temp']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
