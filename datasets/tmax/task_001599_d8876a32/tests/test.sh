#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_audit_trail_exists():
    """Verify that the agent generated the audit trail file."""
    assert os.path.isfile("/home/user/audit_trail.jsonl"), "The file /home/user/audit_trail.jsonl was not found."

def test_payload_recovery_accuracy():
    """Verify that the extracted payloads match the ground truth with an F1 score >= 0.95."""
    audit_file = "/home/user/audit_trail.jsonl"
    truth_file = "/tests/ground_truth_payloads.json"

    assert os.path.isfile(audit_file), f"Agent output file missing: {audit_file}"
    assert os.path.isfile(truth_file), f"Ground truth file missing: {truth_file}"

    with open(truth_file, "r") as f:
        try:
            ground_truth = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Failed to parse ground truth JSON.")

    # Assuming ground truth is a list of dicts with 'extracted_payload' or just a list of payloads
    if isinstance(ground_truth, list) and len(ground_truth) > 0 and isinstance(ground_truth[0], dict):
        truth_payloads = set(item.get("extracted_payload", "") for item in ground_truth)
    elif isinstance(ground_truth, list):
        truth_payloads = set(ground_truth)
    else:
        truth_payloads = set()

    agent_payloads = set()
    with open(audit_file, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                if "extracted_payload" in data:
                    agent_payloads.add(data["extracted_payload"])
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON on line {line_num} of {audit_file}")

    true_positives = len(agent_payloads.intersection(truth_payloads))
    false_positives = len(agent_payloads - truth_payloads)
    false_negatives = len(truth_payloads - agent_payloads)

    precision = true_positives / (true_positives + false_positives) if (true_positives + false_positives) > 0 else 0.0
    recall = true_positives / (true_positives + false_negatives) if (true_positives + false_negatives) > 0 else 0.0

    f1_score = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0

    assert f1_score >= 0.95, f"Payload Recovery Accuracy (F1 Score) is {f1_score:.4f}, which is below the 0.95 threshold."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
