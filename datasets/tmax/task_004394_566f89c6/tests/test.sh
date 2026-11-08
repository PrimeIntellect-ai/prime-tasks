#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

def test_make_execution_and_output():
    makefile_path = "/home/user/Makefile"
    assert os.path.exists(makefile_path), "Makefile is missing at /home/user/Makefile"

    # Run make
    result = subprocess.run(
        ["make", "-C", "/home/user"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"make command failed with error:\n{result.stderr}"

    output_path = "/home/user/detected_anomalies.json"
    assert os.path.exists(output_path), f"Output file {output_path} was not created."

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} does not contain valid JSON.")

    assert isinstance(data, list), "The output must be a JSON array."
    assert len(data) == 1, f"Expected exactly 1 anomaly, found {len(data)}."

    anomaly = data[0]
    expected_keys = {"date", "server_id", "config_size_bytes", "rolling_mean", "rolling_std", "is_anomaly"}
    assert set(anomaly.keys()) == expected_keys, f"Anomaly object keys do not match the expected schema. Found: {list(anomaly.keys())}"

    assert anomaly["date"] == "2023-10-06", f"Expected date '2023-10-06', got {anomaly['date']}"
    assert anomaly["server_id"] == "srv-beta", f"Expected server_id 'srv-beta', got {anomaly['server_id']}"
    assert anomaly["config_size_bytes"] == 1500, f"Expected config_size_bytes 1500, got {anomaly['config_size_bytes']}"
    assert anomaly["is_anomaly"] is True, f"Expected is_anomaly to be true, got {anomaly['is_anomaly']}"

    # Gap-filled values for srv-beta through 2023-10-06 are
    # [500, 550, 550, 550, 550, 1500].
    assert abs(anomaly["rolling_mean"] - 700.0) < 0.1, f"Expected rolling_mean ~700.0, got {anomaly['rolling_mean']}"
    assert abs(anomaly["rolling_std"] - 392.4) < 0.1, f"Expected rolling_std ~392.4, got {anomaly['rolling_std']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
