#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_anomaly_json_exists():
    assert os.path.isfile('/home/user/anomaly.json'), "/home/user/anomaly.json does not exist. Did you save the output to the correct path?"

def test_anomaly_json_content():
    file_path = '/home/user/anomaly.json'
    with open(file_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{file_path} does not contain valid JSON."

    expected_keys = ["index", "timestamp", "message_char_len", "message_byte_len"]
    for key in expected_keys:
        assert key in data, f"Missing key '{key}' in the output JSON."

    assert data["index"] == 142, f"Expected 'index' to be 142, but got {data['index']}."
    assert data["timestamp"] == "2023-10-01T12:02:22Z", f"Expected 'timestamp' to be '2023-10-01T12:02:22Z', but got '{data['timestamp']}'."
    assert data["message_char_len"] == 24, f"Expected 'message_char_len' to be 24, but got {data['message_char_len']}."
    assert data["message_byte_len"] == 68, f"Expected 'message_byte_len' to be 68, but got {data['message_byte_len']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
