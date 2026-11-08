#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_path_result_exists_and_correct():
    file_path = "/home/user/path_result.json"

    assert os.path.isfile(file_path), f"Output file missing: {file_path}"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {file_path}")

    assert "path" in data, "Key 'path' is missing from the JSON output."
    assert "total_latency_ms" in data, "Key 'total_latency_ms' is missing from the JSON output."

    expected_path = ["alpha", "beta", "delta", "omega"]
    expected_latency = 45

    assert data["path"] == expected_path, f"Expected path {expected_path}, but got {data['path']}"
    assert data["total_latency_ms"] == expected_latency, f"Expected total_latency_ms to be {expected_latency}, but got {data['total_latency_ms']}"

    assert len(data.keys()) == 2, f"Expected exactly 2 keys in JSON output, but found {len(data.keys())} keys: {list(data.keys())}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
