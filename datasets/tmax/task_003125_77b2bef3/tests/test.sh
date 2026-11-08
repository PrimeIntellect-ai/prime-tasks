#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import pytest

def calculate_f1(pred_file, truth_file):
    try:
        with open(pred_file, 'r') as f:
            preds = set(json.load(f))
    except Exception:
        return 0.0

    with open(truth_file, 'r') as f:
        truths = set(json.load(f))

    if not preds and not truths:
        return 1.0
    if not preds or not truths:
        return 0.0

    tp = len(preds.intersection(truths))
    fp = len(preds - truths)
    fn = len(truths - preds)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0

    if precision + recall == 0:
        return 0.0

    f1 = 2 * (precision * recall) / (precision + recall)
    return f1

def test_anomalies_f1_score():
    pred_file = "/home/user/anomalies.json"
    truth_file = "/tests/ground_truth_anomalies.json"

    assert os.path.exists(pred_file), f"Output file {pred_file} does not exist."
    assert os.path.exists(truth_file), f"Ground truth file {truth_file} does not exist."

    score = calculate_f1(pred_file, truth_file)
    assert score >= 0.95, f"Metric threshold failed: F1 Score was {score:.4f}, expected >= 0.95"

def test_report_md_exists_and_format():
    report_file = "/home/user/report.md"
    assert os.path.exists(report_file), f"Output file {report_file} does not exist."

    with open(report_file, 'r') as f:
        content = f.read().strip()

    assert "# Sensor Report: Turbine Alpha" in content, "Report missing expected header."
    assert "Total Anomalies Detected:" in content, "Report missing 'Total Anomalies Detected:' line."
    assert "First Anomaly Timestamp:" in content, "Report missing 'First Anomaly Timestamp:' line."

    # Verify that the detected count and first timestamp loosely match expectations
    pred_file = "/home/user/anomalies.json"
    if os.path.exists(pred_file):
        try:
            with open(pred_file, 'r') as f:
                preds = json.load(f)

            count_match = re.search(r"Total Anomalies Detected:\s*(\d+)", content)
            if count_match:
                count = int(count_match.group(1))
                assert count == len(preds), f"Report count {count} does not match anomalies.json length {len(preds)}"

            first_match = re.search(r"First Anomaly Timestamp:\s*(\w+)", content)
            if first_match:
                first_ts = first_match.group(1)
                if len(preds) > 0:
                    expected_first = str(min(preds))
                    assert first_ts == expected_first, f"Report first timestamp {first_ts} does not match min from anomalies.json {expected_first}"
                else:
                    assert first_ts.upper() == "NONE", f"Expected 'NONE' for first timestamp, got {first_ts}"
        except Exception:
            pass

def test_ts_processor_exists():
    processor_dir = "/home/user/ts_processor"
    assert os.path.isdir(processor_dir), f"Processor directory {processor_dir} does not exist."
    cargo_toml = os.path.join(processor_dir, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml not found in {processor_dir}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
