#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess

def test_scan_waf_f1_score():
    script_path = "/home/user/scan_waf.sh"
    assert os.path.isfile(script_path), f"Script not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

    # Execute the student's script end-to-end
    result = subprocess.run([script_path], capture_output=True, text=True)

    pred_file = "/home/user/crashing_hashes.txt"
    truth_file = "/tests/ground_truth_hashes.txt"

    assert os.path.isfile(pred_file), (
        f"Output file not found: {pred_file}\n"
        f"Script Exit Code: {result.returncode}\n"
        f"STDOUT: {result.stdout}\n"
        f"STDERR: {result.stderr}"
    )
    assert os.path.isfile(truth_file), f"Truth file not found: {truth_file}"

    # Compute the F1-Score
    with open(pred_file, 'r') as f:
        preds = set(line.strip() for line in f if line.strip())
    with open(truth_file, 'r') as f:
        truths = set(line.strip() for line in f if line.strip())

    true_positives = len(preds.intersection(truths))
    false_positives = len(preds - truths)
    false_negatives = len(truths - preds)

    if true_positives == 0:
        f1 = 0.0
    else:
        precision = true_positives / (true_positives + false_positives)
        recall = true_positives / (true_positives + false_negatives)
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.95, (
        f"F1-Score is {f1:.4f}, which is below the threshold of 0.95.\n"
        f"True Positives: {true_positives}, False Positives: {false_positives}, False Negatives: {false_negatives}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
