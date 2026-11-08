#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import pytest

def get_expected_results():
    log_file = "/home/user/traffic_logs.json"
    if not os.path.isfile(log_file):
        pytest.fail(f"Required file {log_file} is missing.")

    with open(log_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {log_file} contains invalid JSON.")

    expected_ip = None
    expected_payload = None

    for entry in data:
        headers = entry.get("headers", {})
        if headers.get("X-Test-WAF") == "true":
            cookie_header = headers.get("Cookie", "")
            cookies = [c.strip() for c in cookie_header.split(";")]
            session_data = None
            for cookie in cookies:
                if cookie.startswith("session_data="):
                    session_data = cookie.split("=", 1)[1]
                    break

            if session_data:
                try:
                    decoded = base64.b64decode(session_data).decode('utf-8', errors='ignore')
                    if "<script>" in decoded:
                        expected_ip = entry.get("source_ip")
                        expected_payload = decoded
                        break
                except Exception:
                    continue

    if expected_ip is None or expected_payload is None:
        pytest.fail("Could not find the expected malicious request in the traffic logs.")

    return expected_ip, expected_payload

def test_attacker_ip_file():
    expected_ip, _ = get_expected_results()
    target_file = "/home/user/attacker_ip.txt"

    assert os.path.isfile(target_file), f"The file {target_file} does not exist."

    with open(target_file, 'r') as f:
        content = f.read().strip()

    assert content == expected_ip, f"Expected {target_file} to contain '{expected_ip}', but found '{content}'."

def test_extracted_payload_file():
    _, expected_payload = get_expected_results()
    target_file = "/home/user/extracted_payload.txt"

    assert os.path.isfile(target_file), f"The file {target_file} does not exist."

    with open(target_file, 'r') as f:
        content = f.read().strip()

    assert content == expected_payload, f"Expected {target_file} to contain '{expected_payload}', but found '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
