#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import pytest
from collections import defaultdict

def test_output_json_exists():
    """Check that the output file was created."""
    output_path = "/home/user/output.json"
    assert os.path.exists(output_path), f"Expected output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Expected {output_path} to be a file."

def test_output_json_content():
    """Verify the logic and content of output.json by recomputing the expected result from the logs."""
    server_log_path = "/home/user/logs/server.log"
    app_log_path = "/home/user/logs/app.log"
    output_path = "/home/user/output.json"

    assert os.path.exists(server_log_path), "server.log is missing."
    assert os.path.exists(app_log_path), "app.log is missing."

    # Parse server logs
    server_data = {}
    with open(server_log_path, 'r') as f:
        for line in f:
            match = re.match(r'\[(.*?)\] IP: (.*?) STATUS: (.*)', line.strip())
            if match:
                ts, ip, status = match.groups()
                server_data[(ts, ip)] = status

    # Parse app logs
    app_data = {}
    with open(app_log_path, 'r') as f:
        for line in f:
            match = re.match(r'\[(.*?)\] USER: (.*?) IP: (.*?) ACTION: (.*)', line.strip())
            if match:
                ts, user, ip, action = match.groups()
                app_data[(ts, ip)] = {"user": user, "action": action}

    # Join datasets
    joined = []
    for key, status in server_data.items():
        if key in app_data:
            ts, ip = key
            joined.append({
                "timestamp": ts,
                "ip": ip,
                "status": status,
                "user": app_data[key]["user"],
                "action": app_data[key]["action"]
            })

    # Stratified sample: max 2 per status, earliest timestamps
    by_status = defaultdict(list)
    for record in joined:
        by_status[record["status"]].append(record)

    sampled = []
    for status, records in by_status.items():
        records.sort(key=lambda x: x["timestamp"])
        sampled.extend(records[:2])

    # Sort final output chronologically
    expected_output = sorted(sampled, key=lambda x: x["timestamp"])

    # Read actual output
    with open(output_path, 'r') as f:
        try:
            actual_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{output_path} does not contain valid JSON.")

    # Validate structure and content
    assert isinstance(actual_output, list), "Output JSON should be a list of objects."

    # Check keys for all objects
    expected_keys = {"timestamp", "ip", "status", "user", "action"}
    for idx, obj in enumerate(actual_output):
        assert isinstance(obj, dict), f"Item at index {idx} in JSON is not an object."
        assert set(obj.keys()) == expected_keys, f"Item at index {idx} has incorrect keys. Expected {expected_keys}, got {set(obj.keys())}."

    # Assert exact match of the recomputed output
    assert actual_output == expected_output, "The output JSON does not match the expected stratified sample and sorted data."

def test_script_exists():
    """Check that the script file was created."""
    script_path = "/home/user/analyze.py"
    assert os.path.exists(script_path), f"Expected script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Expected {script_path} to be a file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
