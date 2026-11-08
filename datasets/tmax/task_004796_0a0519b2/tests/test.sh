#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

def calculate_accuracy(pred_file, truth_file):
    try:
        with open(pred_file, 'r') as f1, open(truth_file, 'r') as f2:
            preds = [json.loads(l) for l in f1 if l.strip()]
            truths = [json.loads(l) for l in f2 if l.strip()]
    except Exception:
        return 0.0

    if not truths:
        return 0.0

    matches = 0
    for p, t in zip(preds, truths):
        if p == t:
            matches += 1

    return matches / len(truths)

def test_decoder_accuracy():
    decoder_path = "/home/user/pipeline_repo/decoder.py"
    input_dat = "/app/hidden_test.dat"
    output_jsonl = "/tmp/agent_output.jsonl"
    truth_jsonl = "/tests/ground_truth.jsonl"

    assert os.path.isfile(decoder_path), f"Agent script not found at {decoder_path}"
    assert os.path.isfile(input_dat), f"Hidden test data missing: {input_dat}"
    assert os.path.isfile(truth_jsonl), f"Ground truth missing: {truth_jsonl}"

    if os.path.exists(output_jsonl):
        os.remove(output_jsonl)

    try:
        result = subprocess.run(
            ["python3", decoder_path, input_dat, output_jsonl],
            capture_output=True,
            text=True,
            timeout=30
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Agent script timed out after 30 seconds.")

    assert result.returncode == 0, f"Agent script failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.isfile(output_jsonl), "Agent script did not produce the expected output file."

    accuracy = calculate_accuracy(output_jsonl, truth_jsonl)
    assert accuracy >= 1.0, f"Accuracy metric failed. Expected >= 1.0, got {accuracy}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
