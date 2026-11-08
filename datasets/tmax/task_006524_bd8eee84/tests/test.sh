#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_etl_c_exists():
    assert os.path.isfile("/home/user/etl.c"), "The source file /home/user/etl.c does not exist."

def test_etl_executable_exists():
    assert os.path.isfile("/home/user/etl"), "The executable /home/user/etl does not exist."
    assert os.access("/home/user/etl", os.X_OK), "The file /home/user/etl is not executable."

def test_processed_sensors_matches_expected():
    raw_file = "/home/user/raw_sensors.csv"
    processed_file = "/home/user/processed_sensors.csv"

    assert os.path.isfile(raw_file), f"Input file {raw_file} is missing."
    assert os.path.isfile(processed_file), f"Output file {processed_file} is missing."

    # Read and parse raw data
    data = []
    with open(raw_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            ts = int(parts[0])
            s_id = int(parts[1])
            val = float(parts[2])
            data.append((ts, s_id, val))

    # Compute expected output
    valid_data = []
    last_ts_per_sensor = {1: -1, 2: -1, 3: -1, 4: -1, 5: -1}

    for ts, s_id, val in data:
        if val < -50.0 or val > 150.0:
            continue
        if ts == last_ts_per_sensor[s_id]:
            continue
        last_ts_per_sensor[s_id] = ts
        valid_data.append((ts, s_id, val))

    if not valid_data:
        expected_lines = []
    else:
        buckets = {}
        global_min = min(r[0] for r in valid_data) // 60 * 60
        global_max = max(r[0] for r in valid_data) // 60 * 60

        for ts, s_id, val in valid_data:
            b_ts = (ts // 60) * 60
            if b_ts not in buckets:
                buckets[b_ts] = {1: [], 2: [], 3: [], 4: [], 5: []}
            buckets[b_ts][s_id].append(val)

        last_val = {1: -999.0, 2: -999.0, 3: -999.0, 4: -999.0, 5: -999.0}
        expected_lines = []

        for b_ts in range(global_min, global_max + 60, 60):
            for s_id in range(1, 6):
                if b_ts in buckets and len(buckets[b_ts][s_id]) > 0:
                    avg = sum(buckets[b_ts][s_id]) / len(buckets[b_ts][s_id])
                    last_val[s_id] = avg
                expected_lines.append(f"{b_ts},{s_id},{last_val[s_id]:.2f}")

    # Read processed data
    actual_lines = []
    with open(processed_file, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                actual_lines.append(line)

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows, but got {len(actual_lines)} rows in {processed_file}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch at row {i + 1}:\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
