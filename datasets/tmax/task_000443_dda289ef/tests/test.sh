#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import pytest

def test_decisions_accuracy():
    """Verify that the student's decisions.jsonl achieves >= 95% accuracy against the ground truth."""
    decisions_path = "/home/user/decisions.jsonl"
    truth_path = "/tests/ground_truth.jsonl"

    assert os.path.exists(decisions_path), f"Student output file missing: {decisions_path}"
    assert os.path.isfile(decisions_path), f"Student output is not a file: {decisions_path}"
    assert os.path.exists(truth_path), f"Ground truth file missing: {truth_path}"

    truth = {}
    with open(truth_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                truth[data['id']] = data['action']
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON in ground truth at line {line_num}")
            except KeyError:
                pytest.fail(f"Missing 'id' or 'action' in ground truth at line {line_num}")

    preds = {}
    with open(decisions_path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                preds[data['id']] = data['action']
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON in {decisions_path} at line {line_num}. Each line must be a valid JSON object.")
            except KeyError:
                pytest.fail(f"Missing 'id' or 'action' in {decisions_path} at line {line_num}. Schema must be {{'id': '...', 'action': '...'}}.")

    total = len(truth)
    assert total > 0, "Ground truth dataset is empty."

    correct = 0
    for req_id, expected_action in truth.items():
        if preds.get(req_id) == expected_action:
            correct += 1

    accuracy = correct / total

    assert accuracy >= 0.95, f"Accuracy is too low. Expected >= 0.95, but got {accuracy:.4f} ({correct}/{total} correct)."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
