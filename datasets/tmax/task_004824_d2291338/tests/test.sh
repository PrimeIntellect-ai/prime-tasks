#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_anomaly_json_exists():
    path = "/home/user/anomaly.json"
    assert os.path.exists(path), f"File {path} does not exist. The task requires writing the anomaly result here."

def test_anomaly_json_content():
    path = "/home/user/anomaly.json"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} does not contain valid JSON."

    expected = {
        "service": "service_a",
        "timestamp": "2023-10-01T10:00:20Z",
        "req_id": "a4"
    }

    assert "service" in data, "Key 'service' missing from JSON."
    assert "timestamp" in data, "Key 'timestamp' missing from JSON."
    assert "req_id" in data, "Key 'req_id' missing from JSON."

    assert data["service"] == expected["service"], f"Expected service '{expected['service']}', got '{data['service']}'"
    assert data["timestamp"] == expected["timestamp"], f"Expected timestamp '{expected['timestamp']}', got '{data['timestamp']}'"
    assert data["req_id"] == expected["req_id"], f"Expected req_id '{expected['req_id']}', got '{data['req_id']}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
