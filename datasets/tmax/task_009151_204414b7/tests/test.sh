#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import pytest

def test_processed_data_exists():
    assert os.path.exists("/home/user/processed_data.json"), "Output file /home/user/processed_data.json does not exist."
    assert os.path.isfile("/home/user/processed_data.json"), "/home/user/processed_data.json is not a file."

def test_processed_data_content():
    input_file = "/home/user/sensor_data.csv"
    assert os.path.exists(input_file), f"Input file {input_file} is missing."

    # 1. Deduplication
    seen_hashes = set()
    deduped_lines = []
    with open(input_file, "r") as f:
        for line in f:
            raw_line = line.rstrip('\n')
            if not raw_line:
                continue
            line_hash = hashlib.sha256(raw_line.encode('utf-8')).hexdigest()
            if line_hash not in seen_hashes:
                seen_hashes.add(line_hash)
                deduped_lines.append(raw_line)

    # 2. Parse and Global Min-Max
    header = deduped_lines[0].split(',')
    assert header == ['timestamp', 'vibration', 'temperature'], "Unexpected CSV header."

    data = []
    vibrations = []
    for line in deduped_lines[1:]:
        parts = line.split(',')
        ts = parts[0]
        vib = float(parts[1])
        data.append({"timestamp": ts, "vibration": vib})
        vibrations.append(vib)

    min_vib = min(vibrations)
    max_vib = max(vibrations)
    vib_range = max_vib - min_vib

    # 3. Normalization and 4. Windowed Aggregation & Anomaly Detection
    normalized = []
    for d in data:
        norm = (d["vibration"] - min_vib) / vib_range if vib_range > 0 else 0.0
        normalized.append(norm)

    expected_results = []
    for i in range(len(normalized)):
        window = normalized[max(0, i-2):i+1]
        sma = sum(window) / len(window)
        is_anomaly = abs(normalized[i] - sma) > 0.3
        expected_results.append({
            "timestamp": data[i]["timestamp"],
            "is_anomaly": is_anomaly
        })

    # Read the actual output
    output_file = "/home/user/processed_data.json"
    actual_results = []
    with open(output_file, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                actual_results.append(obj)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {output_file} is not valid JSON.")

    # Compare
    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} JSON lines, but got {len(actual_results)}."

    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert "timestamp" in actual, f"Line {i+1} missing 'timestamp' key."
        assert "is_anomaly" in actual, f"Line {i+1} missing 'is_anomaly' key."
        assert actual["timestamp"] == expected["timestamp"], f"Line {i+1}: expected timestamp {expected['timestamp']}, got {actual['timestamp']}."
        assert actual["is_anomaly"] == expected["is_anomaly"], f"Line {i+1} (timestamp {expected['timestamp']}): expected is_anomaly={expected['is_anomaly']}, got {actual['is_anomaly']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
