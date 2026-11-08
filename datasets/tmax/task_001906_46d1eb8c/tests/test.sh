#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def calculate_iou(file_agent, file_truth):
    if not os.path.exists(file_agent):
        return 0.0
    if not os.path.exists(file_truth):
        return 0.0

    with open(file_agent, 'r') as f:
        agent_lines = set([line.strip() for line in f.readlines() if line.strip()])
    with open(file_truth, 'r') as f:
        truth_lines = set([line.strip() for line in f.readlines() if line.strip()])

    intersection = len(agent_lines.intersection(truth_lines))
    union = len(agent_lines.union(truth_lines))

    if union == 0:
        return 0.0 if len(agent_lines) > 0 or len(truth_lines) > 0 else 1.0
    return intersection / union

def test_manifest_iou_score():
    agent_manifest = "/home/user/manifest.txt"
    truth_manifest = "/tests/ground_truth_manifest.txt"

    assert os.path.exists(agent_manifest), f"Agent manifest file missing: {agent_manifest}"
    assert os.path.exists(truth_manifest), f"Ground truth manifest missing: {truth_manifest}"

    score = calculate_iou(agent_manifest, truth_manifest)
    threshold = 0.85

    assert score >= threshold, f"Manifest IoU score {score:.4f} is below the threshold of {threshold}. The generated manifest does not sufficiently match the ground truth."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
