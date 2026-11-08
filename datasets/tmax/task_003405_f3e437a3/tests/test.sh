#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import pytest


def test_results_file_exists():
    assert os.path.isfile('/tmp/results.json'), "Agent failed: /tmp/results.json not found. Did the pipeline script run and forward data?"


def test_results_format_and_count():
    results = []
    with open('/tmp/results.json', 'r') as f:
        for line in f:
            if line.strip():
                try:
                    data = json.loads(line)
                    results.append(data)
                except json.JSONDecodeError:
                    pytest.fail("Agent failed: /tmp/results.json contains invalid JSON lines.")

    assert len(results) >= 5, f"Agent failed: Not enough windows submitted ({len(results)} < 5). Ensure the pipeline runs for at least 60 seconds."

    for r in results:
        assert "window_start" in r, "Agent failed: 'window_start' key missing in result payload."
        assert "avg_temp" in r, "Agent failed: 'avg_temp' key missing in result payload."


def test_mse_metric():
    assert os.path.isfile('/tests/ground_truth.json'), "Verifier error: missing /tests/ground_truth.json"

    with open('/tests/ground_truth.json', 'r') as f:
        truth = {int(k): float(v) for k, v in json.load(f).items()}

    results = []
    with open('/tmp/results.json', 'r') as f:
        for line in f:
            if line.strip():
                results.append(json.loads(line))

    matched_window_starts = set()
    mse = 0.0
    matched = 0
    for r in results:
        w_start = r.get("window_start")
        a_temp = r.get("avg_temp")
        if w_start in truth:
            matched_window_starts.add(w_start)
            diff = truth[w_start] - a_temp
            mse += diff * diff
            matched += 1

    assert matched > 0, "Agent failed: No matching window_starts found between results and ground truth."
    assert len(matched_window_starts) >= 5, (
        f"Agent failed: Not enough distinct valid windows submitted "
        f"({len(matched_window_starts)} < 5)."
    )

    mse = mse / matched
    assert mse <= 0.5, f"Agent failed: MSE ({mse:.4f}) is greater than the threshold (0.5). Matched windows: {matched}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
