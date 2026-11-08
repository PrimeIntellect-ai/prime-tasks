#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
from datetime import datetime, timedelta
from collections import defaultdict

def parse_iso(dt_str):
    # Parses ISO8601 UTC string like '2023-10-01T10:01:00Z'
    return datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%SZ")

def format_iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def get_15m_bucket(dt):
    minute = (dt.minute // 15) * 15
    return dt.replace(minute=minute, second=0, microsecond=0)

def compute_expected_data():
    input_file = '/home/user/telemetry_data.csv'
    if not os.path.exists(input_file):
        return []

    with open(input_file, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    # 1. Deduplicate (keep first occurrence)
    seen = set()
    deduped = []
    for row in rows:
        tup = tuple(row.items())
        if tup not in seen:
            seen.add(tup)
            deduped.append(row)

    # 2 & 3. Filter speed >= 0 and battery_mv not empty
    cleaned = []
    for row in deduped:
        if row['speed_kmh'] == '' or float(row['speed_kmh']) < 0:
            continue
        if row['battery_mv'] == '':
            continue
        cleaned.append(row)

    # 4. Normalization (battery_pct)
    for row in cleaned:
        bat_mv = float(row['battery_mv'])
        pct = (bat_mv - 3200) / 1000 * 100
        pct = max(0.0, min(100.0, pct))
        row['battery_pct'] = pct
        row['dt'] = parse_iso(row['timestamp'])
        row['speed_kmh'] = float(row['speed_kmh'])
        row['temp_c'] = float(row['temp_c'])

    # 5. Rolling Statistics
    # Group by device_id and sort by timestamp
    devices = defaultdict(list)
    for row in cleaned:
        devices[row['device_id']].append(row)

    for dev_id, dev_rows in devices.items():
        dev_rows.sort(key=lambda x: x['dt'])
        speeds = []
        for i, row in enumerate(dev_rows):
            speeds.append(row['speed_kmh'])
            window = speeds[-3:]
            row['rolling_speed'] = sum(window) / len(window)

    # 6. Time-based Bucketing and Aggregation
    buckets = defaultdict(list)
    for dev_id, dev_rows in devices.items():
        for row in dev_rows:
            bucket_dt = get_15m_bucket(row['dt'])
            buckets[(bucket_dt, dev_id)].append(row)

    results = []
    for (bucket_dt, dev_id), bucket_rows in buckets.items():
        max_temp = max(r['temp_c'] for r in bucket_rows)
        avg_rolling_speed = sum(r['rolling_speed'] for r in bucket_rows) / len(bucket_rows)
        max_bat = max(r['battery_pct'] for r in bucket_rows)
        min_bat = min(r['battery_pct'] for r in bucket_rows)
        battery_drop = max_bat - min_bat

        results.append({
            'interval_start': format_iso(bucket_dt),
            'device_id': dev_id,
            'max_temp': f"{max_temp:.2f}",
            'avg_rolling_speed': f"{avg_rolling_speed:.2f}",
            'battery_drop': f"{battery_drop:.2f}"
        })

    # Sort
    results.sort(key=lambda x: (x['interval_start'], x['device_id']))
    return results

def test_pipeline_log_exists_and_contains_drops():
    log_file = '/home/user/pipeline.log'
    assert os.path.exists(log_file), f"Log file {log_file} does not exist."
    with open(log_file, 'r') as f:
        content = f.read()
    assert content.strip(), "Log file is empty."
    # The prompt says it must write at least one line indicating the total number of rows dropped.
    # We just check if it's not empty, as the exact format isn't specified, but we can look for digits.
    assert any(char.isdigit() for char in content), "Log file doesn't seem to contain numerical drop counts."

def test_processed_telemetry_output():
    output_file = '/home/user/processed_telemetry.csv'
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    expected = compute_expected_data()

    with open(output_file, 'r') as f:
        reader = csv.DictReader(f)
        actual = list(reader)

    assert len(actual) == len(expected), f"Expected {len(expected)} rows, but got {len(actual)} rows."

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act['interval_start'] == exp['interval_start'], f"Row {i}: Expected interval_start {exp['interval_start']}, got {act.get('interval_start')}"
        assert act['device_id'] == exp['device_id'], f"Row {i}: Expected device_id {exp['device_id']}, got {act.get('device_id')}"

        # Compare floats up to 2 decimal places
        assert float(act['max_temp']) == float(exp['max_temp']), f"Row {i}: Expected max_temp {exp['max_temp']}, got {act.get('max_temp')}"
        assert float(act['avg_rolling_speed']) == float(exp['avg_rolling_speed']), f"Row {i}: Expected avg_rolling_speed {exp['avg_rolling_speed']}, got {act.get('avg_rolling_speed')}"
        assert float(act['battery_drop']) == float(exp['battery_drop']), f"Row {i}: Expected battery_drop {exp['battery_drop']}, got {act.get('battery_drop')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
