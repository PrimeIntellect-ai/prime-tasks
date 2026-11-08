#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

TRUTH = [
    {
        "timestamp": "00:01:15",
        "unredacted_payload": "http://evil.com/auth",
        "used_rogue_cert": True
    },
    {
        "timestamp": "00:02:30",
        "unredacted_payload": "http://evil.com/auth",
        "used_rogue_cert": False
    },
    {
        "timestamp": "00:04:45",
        "unredacted_payload": "http://evil.com/auth",
        "used_rogue_cert": True
    }
]

def time_to_seconds(t_str):
    """Convert HH:MM:SS string to total seconds."""
    h, m, s = map(int, t_str.split(':'))
    return h * 3600 + m * 60 + s

def is_match(truth_event, pred_event):
    """Check if two events match within 1 second tolerance for timestamp."""
    if truth_event.get('unredacted_payload') != pred_event.get('unredacted_payload'):
        return False
    if truth_event.get('used_rogue_cert') != pred_event.get('used_rogue_cert'):
        return False

    try:
        t_sec = time_to_seconds(truth_event['timestamp'])
        p_sec = time_to_seconds(pred_event['timestamp'])
    except (KeyError, ValueError):
        return False

    return abs(t_sec - p_sec) <= 1

def compute_f1(truth, pred):
    """Compute F1 score using greedy matching with tolerance."""
    matched_truth = set()
    matched_pred = set()

    for i, t in enumerate(truth):
        for j, p in enumerate(pred):
            if j in matched_pred:
                continue
            if is_match(t, p):
                matched_truth.add(i)
                matched_pred.add(j)
                break

    tp = len(matched_truth)
    fp = len(pred) - tp
    fn = len(truth) - tp

    if tp == 0:
        return 0.0
    precision = tp / (tp + fp)
    recall = tp / (tp + fn)
    return 2 * (precision * recall) / (precision + recall)

def test_incident_report_f1_score():
    """Validate the incident report JSON file against the ground truth."""
    pred_file = "/home/user/incident_report.json"
    assert os.path.isfile(pred_file), f"Expected output file {pred_file} does not exist."

    with open(pred_file, 'r') as f:
        try:
            pred = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {pred_file} is not valid JSON.")

    assert isinstance(pred, list), f"Expected JSON root to be a list, got {type(pred).__name__}."

    f1 = compute_f1(TRUTH, pred)
    assert f1 >= 0.90, f"F1 score {f1:.3f} is below the threshold of 0.90."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
