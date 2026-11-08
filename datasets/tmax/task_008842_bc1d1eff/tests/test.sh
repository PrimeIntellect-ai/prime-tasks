#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib
from collections import defaultdict

def test_pipeline_log_exists_and_content():
    log_path = "/home/user/pipeline.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."
    assert os.path.isfile(log_path), f"{log_path} is not a file."

    with open(log_path, 'r') as f:
        content = f.read()

    expected_sensors = ["S1", "S2", "S3", "S4"]
    for sensor in expected_sensors:
        expected_line = f"Processed sensor: {sensor}"
        assert expected_line in content, f"Expected '{expected_line}' to be in {log_path}."

def test_report_md_exists_and_content():
    data_path = "/home/user/sensor_data.txt"
    assert os.path.exists(data_path), f"Data file {data_path} missing."

    # Recompute expected values
    sensors = defaultdict(list)
    with open(data_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 3:
                sensors[parts[0]].append((int(parts[1]), int(parts[2])))

    hashes = {}
    for sensor, readings in sensors.items():
        readings.sort(key=lambda x: x[0])
        deltas = []
        for i in range(1, len(readings)):
            deltas.append(str(readings[i][1] - readings[i-1][1]))
        if len(deltas) >= 2:
            delta_str = ",".join(deltas)
            md5_hash = hashlib.md5(delta_str.encode('utf-8')).hexdigest()
            if md5_hash not in hashes:
                hashes[md5_hash] = []
            hashes[md5_hash].append(sensor)

    matching_sensors = []
    matching_hash = ""
    for h, s_list in hashes.items():
        if len(s_list) == 2:
            matching_sensors = sorted(s_list)
            matching_hash = h
            break

    assert len(matching_sensors) == 2, "Could not find exactly one pair of matching sensors in the data."

    report_path = "/home/user/report.md"
    assert os.path.exists(report_path), f"Report file {report_path} does not exist."
    assert os.path.isfile(report_path), f"{report_path} is not a file."

    with open(report_path, 'r') as f:
        content = f.read().strip()

    expected_report = f"""# Anomaly Report

The following sensors share an identical behavior pattern:
- {matching_sensors[0]}
- {matching_sensors[1]}

Pattern Hash: {matching_hash}"""

    assert content == expected_report, f"Report content does not match expected format or values. Expected:\n{expected_report}\n\nGot:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
