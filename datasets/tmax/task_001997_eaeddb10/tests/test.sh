#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_deadlock_report_exists():
    path = "/home/user/deadlock_report.json"
    assert os.path.exists(path), f"Missing file: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"

def test_deadlock_report_content():
    path = "/home/user/deadlock_report.json"
    assert os.path.exists(path), f"Missing file: {path}"

    with open(path, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON")

    assert "deadlocks" in actual, "Missing 'deadlocks' key in JSON report"
    assert "bottleneck_tx" in actual, "Missing 'bottleneck_tx' key in JSON report"
    assert "bottleneck_centrality" in actual, "Missing 'bottleneck_centrality' key in JSON report"

    expected_deadlocks = [["T1", "T2", "T3"]]
    assert actual["deadlocks"] == expected_deadlocks, f"Expected deadlocks {expected_deadlocks}, got {actual['deadlocks']}"

    expected_bottleneck_tx = "T2"
    assert actual["bottleneck_tx"] == expected_bottleneck_tx, f"Expected bottleneck_tx '{expected_bottleneck_tx}', got '{actual['bottleneck_tx']}'"

    expected_centrality = 0.2381
    assert abs(actual["bottleneck_centrality"] - expected_centrality) < 0.001, f"Expected bottleneck_centrality close to {expected_centrality}, got {actual['bottleneck_centrality']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
