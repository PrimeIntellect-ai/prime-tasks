#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_triage_result_exists_and_correct():
    result_path = "/home/user/triage_result.txt"
    assert os.path.exists(result_path), f"The file {result_path} does not exist."
    assert os.path.isfile(result_path), f"The path {result_path} is not a file."

    with open(result_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {result_path}, but found {len(lines)}."

    expected_req_id = "ReqID: req-803"
    expected_timestamp = "Timestamp: 2023-10-24T09:15:22Z"

    assert lines[0] == expected_req_id, f"First line is incorrect. Expected '{expected_req_id}', got '{lines[0]}'."
    assert lines[1] == expected_timestamp, f"Second line is incorrect. Expected '{expected_timestamp}', got '{lines[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
