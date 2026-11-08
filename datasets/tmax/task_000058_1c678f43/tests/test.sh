#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_anomaly_report_exists_and_correct():
    """Verify that the anomaly_report.json file exists and contains the correct data."""
    file_path = "/home/user/anomaly_report.json"
    assert os.path.isfile(file_path), f"File not found: {file_path}"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"File {file_path} is not valid JSON. Error: {e}")

    assert "timestamp" in data, f"Missing 'timestamp' key in {file_path}"
    assert data["timestamp"] == "2023-10-25T10:07", f"Incorrect timestamp: expected '2023-10-25T10:07', got '{data['timestamp']}'"

    assert "cpu_load" in data, f"Missing 'cpu_load' key in {file_path}"
    assert float(data["cpu_load"]) == 85.5, f"Incorrect cpu_load: expected 85.5, got {data['cpu_load']}"

    assert "error_count" in data, f"Missing 'error_count' key in {file_path}"
    assert int(data["error_count"]) == 6, f"Incorrect error_count: expected 6, got {data['error_count']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
