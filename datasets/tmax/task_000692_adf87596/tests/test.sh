#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import pytest

def test_jaccard_similarity():
    results_path = '/home/user/results.json'
    truth_path = '/tests/ground_truth.json'

    assert os.path.exists(results_path), f"Output file not found at {results_path}"
    assert os.path.exists(truth_path), f"Ground truth file not found at {truth_path}"

    with open(results_path, 'r') as f:
        try:
            pred = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Results file is not valid JSON.")

    with open(truth_path, 'r') as f:
        truth = json.load(f)

    pred_ips = set(pred.get('blocked_ips', []))
    truth_ips = set(truth.get('blocked_ips', []))

    pred_files = set(pred.get('non_compliant_files', []))
    truth_files = set(truth.get('non_compliant_files', []))

    intersect = len(pred_ips.intersection(truth_ips)) + len(pred_files.intersection(truth_files))
    union = len(pred_ips.union(truth_ips)) + len(pred_files.union(truth_files))

    jaccard = intersect / union if union > 0 else 0

    assert jaccard >= 0.95, (
        f"Jaccard similarity {jaccard:.4f} is below threshold 0.95.\n"
        f"Predicted IPs: {pred_ips}\n"
        f"Truth IPs: {truth_ips}\n"
        f"Predicted Files: {pred_files}\n"
        f"Truth Files: {truth_files}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
