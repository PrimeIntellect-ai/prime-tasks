#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_malicious_ips_f1_score():
    target_path = "/home/user/malicious_ips.txt"
    assert os.path.exists(target_path), f"Output file {target_path} does not exist."

    with open(target_path, "r") as f:
        agent_ips = set(line.strip() for line in f if line.strip())

    truth_ips = {"192.168.1.105", "10.0.5.55", "172.16.8.99"}

    true_positives = len(agent_ips.intersection(truth_ips))
    false_positives = len(agent_ips - truth_ips)
    false_negatives = len(truth_ips - agent_ips)

    if true_positives == 0:
        f1 = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)
        recall = true_positives / (true_positives + false_negatives)
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.95, f"F1 score {f1:.4f} is below the threshold of 0.95. Extracted IPs: {agent_ips}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
