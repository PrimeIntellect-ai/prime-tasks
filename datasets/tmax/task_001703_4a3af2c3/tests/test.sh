#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import subprocess
import pytest

def test_fast_primer_match_correctness_and_speed():
    binary_path = "/home/user/fast_primer_match"
    assert os.path.exists(binary_path), f"Student binary {binary_path} not found."
    assert os.access(binary_path, os.X_OK), f"Student binary {binary_path} is not executable."

    # Remove scores.txt if it exists to ensure we are generating a fresh one
    scores_path = "/home/user/scores.txt"
    if os.path.exists(scores_path):
        os.remove(scores_path)

    # Run the student binary and measure time
    start = time.time()
    res = subprocess.run([binary_path], capture_output=True, text=True)
    agent_time = time.time() - start

    assert res.returncode == 0, f"Student binary failed with return code {res.returncode}. stderr: {res.stderr}"

    # Check execution time
    assert agent_time < 0.2, f"Speedup not met, took {agent_time:.3f}s (required < 0.2s)"

    # Read student scores
    assert os.path.exists(scores_path), f"Scores file {scores_path} not found after execution."
    with open(scores_path, "r") as f:
        student_scores = [line.strip() for line in f if line.strip()]

    with open("/home/user/primers.txt", "r") as f:
        primers = [line.strip() for line in f if line.strip()]

    assert len(student_scores) == len(primers), f"Expected {len(primers)} scores, got {len(student_scores)}"

    with open("/home/user/reference.txt", "r") as f:
        ref = f.read().strip()

    # Verify every score against the original binary.
    for idx, primer in enumerate(primers):
        truth_res = subprocess.run(["/app/primer_match", ref, primer], capture_output=True, text=True)
        assert truth_res.returncode == 0, f"Original binary failed for primer {primer}"
        truth_score = truth_res.stdout.strip()

        student_score = student_scores[idx]
        assert student_score == truth_score, (
            f"Score mismatch at line {idx + 1} for primer {primer}: "
            f"expected {truth_score}, got {student_score}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
