#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def nw_score(seq1, seq2, match=4, mismatch=-2, gap=-3):
    n = len(seq1)
    m = len(seq2)
    dp = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        dp[i][0] = i * gap
    for j in range(m + 1):
        dp[0][j] = j * gap

    for i in range(1, n + 1):
        for j in range(1, m + 1):
            score = match if seq1[i-1] == seq2[j-1] else mismatch
            dp[i][j] = max(
                dp[i-1][j-1] + score,
                dp[i-1][j] + gap,
                dp[i][j-1] + gap
            )
    return dp[n][m]

def test_files_exist():
    assert os.path.isfile("/home/user/aligner.cpp"), "Source code /home/user/aligner.cpp is missing."
    assert os.path.isfile("/home/user/aligner"), "Executable /home/user/aligner is missing."
    assert os.access("/home/user/aligner", os.X_OK), "/home/user/aligner is not executable."
    assert os.path.isfile("/home/user/sample_scores.txt"), "Output file /home/user/sample_scores.txt is missing."

def test_aligner_accuracy():
    agent_executable = "/home/user/aligner"

    # Generate test cases
    bases = ['A', 'C', 'G', 'T']
    random.seed(42)
    test_pairs = [
        ("AATCG", "AACG"),
        ("GATTACA", "GCATGCU"),
        ("A", "T"),
        ("ACGT", "ACGG"),
        ("ACGT", "ACGT"),
        ("", ""),
        ("A", ""),
        ("", "C")
    ]

    for _ in range(20):
        len1 = random.randint(10, 50)
        len2 = random.randint(10, 50)
        seq1 = "".join(random.choices(bases, k=len1))
        seq2 = "".join(random.choices(bases, k=len2))
        test_pairs.append((seq1, seq2))

    truth_scores = [str(nw_score(s1, s2)) for s1, s2 in test_pairs]
    input_data = "\n".join(f"{s1},{s2}" for s1, s2 in test_pairs) + "\n"

    try:
        result = subprocess.run(
            [agent_executable],
            input=input_data,
            text=True,
            capture_output=True,
            timeout=5,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Aligner execution failed with return code {e.returncode}. Stderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Aligner execution timed out.")

    agent_lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]

    assert len(agent_lines) == len(truth_scores), f"Expected {len(truth_scores)} output lines, got {len(agent_lines)}."

    correct = 0
    for t, a in zip(truth_scores, agent_lines):
        if t == a:
            correct += 1

    accuracy = correct / len(truth_scores)
    assert accuracy >= 1.0, f"Accuracy metric failed: expected >= 1.0, got {accuracy}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
