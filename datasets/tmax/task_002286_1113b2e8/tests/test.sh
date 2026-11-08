#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import pytest

def test_failed_traces_file_exists():
    assert os.path.isfile("/home/user/failed_traces.json"), "The output file /home/user/failed_traces.json does not exist."

def test_failed_traces_content_matches_logs():
    gateway_log_path = "/home/user/logs/api_gateway.log"
    payment_log_path = "/home/user/logs/payment_backend.log"

    assert os.path.isfile(gateway_log_path), f"Missing {gateway_log_path}"
    assert os.path.isfile(payment_log_path), f"Missing {payment_log_path}"

    # Parse API Gateway logs for 503s
    gateway_503_reqs = set()
    gateway_regex = re.compile(r"\[req_id=(REQ-\d+)\] HTTP 503")
    with open(gateway_log_path, "r") as f:
        for line in f:
            match = gateway_regex.search(line)
            if match:
                gateway_503_reqs.add(match.group(1))

    # Parse Payment Backend logs for retry_count >= 3
    payment_high_retries = set()
    payment_regex = re.compile(r"trace=(REQ-\d+) \| STATE: retry_count=(\d+)")
    with open(payment_log_path, "r") as f:
        for line in f:
            match = payment_regex.search(line)
            if match:
                req_id = match.group(1)
                retry_count = int(match.group(2))
                if retry_count >= 3:
                    payment_high_retries.add(req_id)

    # Compute expected failed traces
    expected_failed_traces = sorted(list(gateway_503_reqs.intersection(payment_high_retries)))

    # Read the student's output
    output_path = "/home/user/failed_traces.json"
    with open(output_path, "r") as f:
        try:
            actual_failed_traces = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} does not contain valid JSON.")

    assert isinstance(actual_failed_traces, list), f"Expected a JSON array, got {type(actual_failed_traces).__name__}."
    assert all(isinstance(x, str) for x in actual_failed_traces), "Expected all elements in the JSON array to be strings."

    assert actual_failed_traces == expected_failed_traces, (
        f"The failed traces do not match the expected list.\n"
        f"Expected: {expected_failed_traces}\n"
        f"Actual: {actual_failed_traces}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
