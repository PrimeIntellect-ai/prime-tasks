#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def extract_set(data):
    """
    Extracts a set of JSON-serialized string representations of the items
    in the provided data to allow for set-based F1 computation.
    """
    # If the data is a dictionary, assume the paths are under some key (like 'paths' or 'results')
    if isinstance(data, dict):
        for val in data.values():
            if isinstance(val, list):
                data = val
                break

    if isinstance(data, list):
        return set(json.dumps(x, sort_keys=True) for x in data)

    return set()

def test_audit_results_f1_score():
    audit_file = "/home/user/audit_results.json"
    golden_file = "/tests/golden_results.json"

    assert os.path.isfile(audit_file), f"Output file missing: {audit_file}"
    assert os.path.isfile(golden_file), f"Golden file missing: {golden_file}"

    with open(audit_file, 'r') as f:
        try:
            audit_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Failed to parse JSON from {audit_file}")

    with open(golden_file, 'r') as f:
        golden_data = json.load(f)

    audit_set = extract_set(audit_data)
    golden_set = extract_set(golden_data)

    assert len(golden_set) > 0, "Golden dataset is empty or could not be parsed correctly."

    tp = len(audit_set.intersection(golden_set))
    fp = len(audit_set - golden_set)
    fn = len(golden_set - audit_set)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0

    if precision + recall == 0:
        f1_score = 0.0
    else:
        f1_score = 2 * (precision * recall) / (precision + recall)

    assert f1_score >= 0.95, (
        f"F1 score {f1_score:.4f} is below the threshold of 0.95. "
        f"(Precision: {precision:.4f}, Recall: {recall:.4f}, TP: {tp}, FP: {fp}, FN: {fn})"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
