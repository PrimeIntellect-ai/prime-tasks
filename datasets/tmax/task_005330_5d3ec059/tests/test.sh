#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import base64
import pytest

def test_flagged_requests():
    log_file_path = "/home/user/upload_logs.json"
    flagged_requests_path = "/home/user/flagged_requests.txt"

    assert os.path.exists(log_file_path), f"Missing required file: {log_file_path}"
    assert os.path.exists(flagged_requests_path), f"Missing output file: {flagged_requests_path}"

    with open(log_file_path, "r") as f:
        logs = json.load(f)

    expected_ids = []
    for entry in logs:
        req_id = entry.get("request_id")
        encoded_filename = entry.get("encoded_filename", "")
        try:
            decoded = base64.b64decode(encoded_filename).decode('utf-8')
            if "../" in decoded or "..\\" in decoded:
                expected_ids.append(req_id)
        except Exception:
            pass

    expected_ids.sort()

    with open(flagged_requests_path, "r") as f:
        content = f.read().strip()

    actual_ids = []
    if content:
        for line in content.splitlines():
            line = line.strip()
            if line:
                try:
                    actual_ids.append(int(line))
                except ValueError:
                    pytest.fail(f"Invalid integer found in {flagged_requests_path}: {line}")

    assert actual_ids == expected_ids, f"Expected flagged IDs {expected_ids}, but got {actual_ids}"

def test_exploit_payload():
    exploit_payload_path = "/home/user/exploit_payload.json"
    assert os.path.exists(exploit_payload_path), f"Missing output file: {exploit_payload_path}"

    with open(exploit_payload_path, "r") as f:
        try:
            payload = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {exploit_payload_path} does not contain valid JSON.")

    assert isinstance(payload, dict), f"JSON root in {exploit_payload_path} should be a dictionary."
    assert len(payload) == 2, f"Expected exactly 2 keys in {exploit_payload_path}, found {len(payload)}."

    assert "request_id" in payload, f"Missing 'request_id' in {exploit_payload_path}."
    assert payload["request_id"] == 9999, f"Expected 'request_id' to be 9999, got {payload['request_id']}."

    assert "encoded_filename" in payload, f"Missing 'encoded_filename' in {exploit_payload_path}."
    expected_encoded = base64.b64encode(b"../../../etc/passwd").decode('utf-8')
    assert payload["encoded_filename"] == expected_encoded, f"Expected 'encoded_filename' to be {expected_encoded}, got {payload['encoded_filename']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
