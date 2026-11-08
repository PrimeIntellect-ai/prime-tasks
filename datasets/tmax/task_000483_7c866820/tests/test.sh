#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest
from datetime import datetime, timedelta

DIRTY_CSV = "/home/user/dirty_telemetry.csv"
CLEAN_CSV = "/home/user/clean_telemetry.csv"
ANOMALIES_CSV = "/home/user/anomalies.csv"

def parse_iso_time(ts_str):
    if ts_str.endswith('Z'):
        ts_str = ts_str[:-1] + '+00:00'
    return datetime.fromisoformat(ts_str)

def decode_device(hex_str):
    b = bytes.fromhex(hex_str)
    try:
        return b.decode('utf-8')
    except UnicodeDecodeError:
        return b.decode('latin-1')

def compute_expected_data():
    if not os.path.exists(DIRTY_CSV):
        pytest.fail(f"Missing input file: {DIRTY_CSV}")

    records = []
    with open(DIRTY_CSV, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            dt = parse_iso_time(row['timestamp'])
            device = decode_device(row['device_hex'])
            val = float(row['value'])
            records.append((dt, device, val))

    # Deduplicate (keep first occurrence)
    seen = set()
    deduped = []
    for r in records:
        key = (r[0], r[1])
        if key not in seen:
            seen.add(key)
            deduped.append(r)

    # Group by device
    by_device = {}
    for dt, dev, val in deduped:
        by_device.setdefault(dev, []).append((dt, val))

    clean_records = []
    for dev, items in by_device.items():
        items.sort(key=lambda x: x[0])
        if not items:
            continue

        current_dt = items[0][0]
        end_dt = items[-1][0]

        # Resample 1H and ffill
        idx = 0
        last_val = items[0][1]
        while current_dt <= end_dt:
            # Advance idx to the last item <= current_dt
            while idx < len(items) and items[idx][0] <= current_dt:
                last_val = items[idx][1]
                idx += 1

            clean_records.append((current_dt, dev, last_val))
            current_dt += timedelta(hours=1)

    # Sort by device, then timestamp
    clean_records.sort(key=lambda x: (x[1], x[0]))

    anomalies = [r for r in clean_records if r[2] > 100.0]

    return clean_records, anomalies

def read_output_csv(filepath):
    if not os.path.exists(filepath):
        pytest.fail(f"Missing output file: {filepath}")

    records = []
    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames or set(reader.fieldnames) != {'timestamp', 'device', 'value'}:
            pytest.fail(f"File {filepath} has incorrect headers: {reader.fieldnames}")

        for row in reader:
            dt = parse_iso_time(row['timestamp'])
            dev = row['device']
            val = float(row['value'])
            records.append((dt, dev, val))

    return records

def test_clean_telemetry():
    expected_clean, _ = compute_expected_data()
    actual_clean = read_output_csv(CLEAN_CSV)

    assert len(actual_clean) == len(expected_clean), \
        f"Expected {len(expected_clean)} rows in {CLEAN_CSV}, got {len(actual_clean)}"

    for i, (act, exp) in enumerate(zip(actual_clean, expected_clean)):
        assert act[0] == exp[0], f"Row {i+1} timestamp mismatch: expected {exp[0]}, got {act[0]}"
        assert act[1] == exp[1], f"Row {i+1} device mismatch: expected {exp[1]}, got {act[1]}"
        assert abs(act[2] - exp[2]) < 1e-6, f"Row {i+1} value mismatch: expected {exp[2]}, got {act[2]}"

def test_anomalies():
    _, expected_anomalies = compute_expected_data()
    actual_anomalies = read_output_csv(ANOMALIES_CSV)

    assert len(actual_anomalies) == len(expected_anomalies), \
        f"Expected {len(expected_anomalies)} rows in {ANOMALIES_CSV}, got {len(actual_anomalies)}"

    for i, (act, exp) in enumerate(zip(actual_anomalies, expected_anomalies)):
        assert act[0] == exp[0], f"Row {i+1} timestamp mismatch: expected {exp[0]}, got {act[0]}"
        assert act[1] == exp[1], f"Row {i+1} device mismatch: expected {exp[1]}, got {act[1]}"
        assert abs(act[2] - exp[2]) < 1e-6, f"Row {i+1} value mismatch: expected {exp[2]}, got {act[2]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
