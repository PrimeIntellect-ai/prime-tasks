#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv

def test_clean_data_csv():
    """Test that clean_data.csv is correctly generated from raw_logs.txt."""
    raw_logs_path = "/home/user/raw_logs.txt"
    clean_data_path = "/home/user/clean_data.csv"

    assert os.path.exists(clean_data_path), f"{clean_data_path} does not exist."

    expected_rows = [["ts", "temp", "vibration", "failure"]]

    with open(raw_logs_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) != 6:
                continue
            ts, sensor_id, status, temp, vibration, failure = parts
            if status == "OK":
                expected_rows.append([ts, temp, vibration, failure])

    with open(clean_data_path, "r") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in clean_data.csv, got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i} mismatch in clean_data.csv: expected {expected}, got {actual}."

def test_metrics_json():
    """Test that metrics.json exists and has the correct structure and expected values."""
    metrics_path = "/home/user/metrics.json"
    assert os.path.exists(metrics_path), f"{metrics_path} does not exist."

    with open(metrics_path, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{metrics_path} is not valid JSON."

    assert "best_depth" in metrics, "Missing 'best_depth' in metrics.json."
    assert "best_cv_score" in metrics, "Missing 'best_cv_score' in metrics.json."

    assert isinstance(metrics["best_depth"], int), "'best_depth' must be an integer."
    assert isinstance(metrics["best_cv_score"], float), "'best_cv_score' must be a float."

    # Based on the deterministic setup, depth 2 perfectly splits the data.
    assert metrics["best_depth"] == 2, f"Expected best_depth to be 2, got {metrics['best_depth']}."
    assert metrics["best_cv_score"] == 1.0, f"Expected best_cv_score to be 1.0, got {metrics['best_cv_score']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
