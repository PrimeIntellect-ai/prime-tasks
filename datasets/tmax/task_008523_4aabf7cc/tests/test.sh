#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import math
from datetime import datetime
import pytest

EXPECTED_LOG = '''[2023-10-01T10:00:00Z] INFO [module_a] sensor_id: SN-1001 | some noise | payload: {"x": 0.0, "y": 0.0}
[2023-10-01T10:05:00Z] DEBUG noise sensor_id: TEST-9999 payload: {"x": 100, "y": 100}
[2023-10-01T10:10:00Z] WARN sensor_id: SN-1001 - payload: {"x": 3.0, "y": null}
[2023-10-01T10:20:00Z] INFO sensor_id: SN-1001 payload: {"x": 6.0, "y": 8.0}
[2023-10-01T10:00:00Z] INFO sensor_id: SN-2002 | payload: {"x": 10.0, "y": 10.0}
[2023-10-01T10:30:00Z] ERROR sensor_id: SN-2002 payload: {"y": 10.0}
[2023-10-01T11:00:00Z] INFO sensor_id: SN-2002 | payload: {"x": 10.0, "y": 10.0}
[2023-10-01T10:00:00Z] INFO sensor_id: SN-3003 payload: {"x": 0.0, "y": 0.0}
[2023-10-01T10:05:00Z] INFO sensor_id: SN-3003 payload: {"x": 5.0}
[2023-10-01T10:10:00Z] INFO sensor_id: SN-3003 payload: {"x": 10.0, "y": 10.0}
[2023-10-01T10:15:00Z] INFO sensor_id: SN-500 | payload: {"x": 0, "y": 0}
'''

def compute_expected_distances(log_path):
    with open(log_path, 'r') as f:
        lines = f.readlines()

    line_pattern = re.compile(
        r'^\[(.*?)\].*?sensor_id:\s*(SN-\d{4})\b.*?payload:\s*(\{.*\})'
    )

    sensor_data = {}

    for line in lines:
        match = re.search(r'^\[(.*?)\]', line)
        if not match:
            continue
        timestamp_str = match.group(1)

        sensor_match = re.search(r'sensor_id:\s*([A-Za-z0-9\-]+)', line)
        if not sensor_match:
            continue
        sensor_id = sensor_match.group(1)

        if not re.match(r'^SN-\d{4}$', sensor_id):
            continue

        payload_match = re.search(r'payload:\s*(\{.*?\})', line)
        if not payload_match:
            continue
        payload_str = payload_match.group(1)

        try:
            payload = json.loads(payload_str)
        except json.JSONDecodeError:
            continue

        dt = datetime.strptime(timestamp_str, "%Y-%m-%dT%H:%M:%SZ")
        ts = dt.timestamp()

        x = payload.get('x')
        y = payload.get('y')

        if sensor_id not in sensor_data:
            sensor_data[sensor_id] = []

        sensor_data[sensor_id].append({'ts': ts, 'x': x, 'y': y})

    distances = {}
    for sensor_id, records in sensor_data.items():
        records.sort(key=lambda r: r['ts'])

        for axis in ['x', 'y']:
            for i, rec in enumerate(records):
                if rec[axis] is None:
                    prev_valid = None
                    for j in range(i - 1, -1, -1):
                        if records[j][axis] is not None:
                            prev_valid = records[j]
                            break

                    next_valid = None
                    for j in range(i + 1, len(records)):
                        if records[j][axis] is not None:
                            next_valid = records[j]
                            break

                    if prev_valid and next_valid:
                        t0, v0 = prev_valid['ts'], prev_valid[axis]
                        t1, v1 = next_valid['ts'], next_valid[axis]
                        t = rec['ts']
                        if t1 != t0:
                            rec[axis] = v0 + (v1 - v0) * (t - t0) / (t1 - t0)
                        else:
                            rec[axis] = v0

        total_dist = 0.0
        for i in range(1, len(records)):
            dx = records[i]['x'] - records[i - 1]['x']
            dy = records[i]['y'] - records[i - 1]['y']
            total_dist += math.hypot(dx, dy)

        distances[sensor_id] = round(total_dist, 2)

    return distances


def test_distances_json_exists():
    assert os.path.exists("/home/user/distances.json"), "The file /home/user/distances.json does not exist."
    assert os.path.isfile("/home/user/distances.json"), "/home/user/distances.json is not a file."


def test_source_log_unchanged():
    log_path = "/home/user/sensor_stream.log"
    assert os.path.exists(log_path), f"Log file {log_path} is missing, cannot compute expected results."
    assert os.path.isfile(log_path), f"Log path {log_path} is not a regular file."
    with open(log_path, "r") as f:
        actual_log = f.read()
    assert actual_log == EXPECTED_LOG, "The source telemetry log was modified."


def test_distances_json_content():
    log_path = "/home/user/sensor_stream.log"
    assert os.path.exists(log_path), f"Log file {log_path} is missing, cannot compute expected results."

    expected_distances = compute_expected_distances(log_path)

    with open("/home/user/distances.json", "r") as f:
        try:
            student_distances = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/distances.json is not valid JSON.")

    assert isinstance(student_distances, dict), "The top-level JSON structure should be an object (dictionary)."

    for sensor_id, expected_dist in expected_distances.items():
        assert sensor_id in student_distances, f"Missing sensor_id '{sensor_id}' in output JSON."
        student_dist = student_distances[sensor_id]
        assert isinstance(student_dist, (int, float)), f"Distance for '{sensor_id}' must be a number."
        assert math.isclose(student_dist, expected_dist, abs_tol=0.01), \
            f"Expected distance for '{sensor_id}' to be {expected_dist}, but got {student_dist}."

    for sensor_id in student_distances:
        assert sensor_id in expected_distances, f"Unexpected sensor_id '{sensor_id}' found in output JSON."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
