#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np
import pytest


def derive_ground_truth():
    # Replay the deterministic signal-generation RNG sequence. Injection starts
    # are aligned to the required 10-sample window step.
    np.random.seed(42)
    signal_len = 10000
    np.random.normal(50, 10, signal_len)

    indices = []
    for _ in range(50):
        idx = np.random.randint(0, signal_len - 100)
        idx = (idx // 10) * 10
        indices.append(int(idx))

        for _ in range(100):
            if np.random.rand() < 0.5:
                np.random.normal(45.5, 5.0)
            else:
                np.random.normal(60.2, 4.2)

    return set(indices)


def test_f1_score_motif_matches():
    pred_path = '/home/user/motif_matches.csv'
    assert os.path.exists(pred_path), f"Output file {pred_path} does not exist."

    try:
        with open(pred_path, 'r') as f:
            preds = set(int(x.strip()) for x in f if x.strip())
    except ValueError:
        pytest.fail(f"File {pred_path} contains non-integer values.")

    truths = derive_ground_truth()

    if not preds:
        pytest.fail("Predicted indices file is empty or contains no valid indices. F1 Score: 0.0")

    tp = len(preds & truths)
    fp = len(preds - truths)
    fn = len(truths - preds)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0

    if precision + recall == 0:
        f1 = 0.0
    else:
        f1 = 2 * (precision * recall) / (precision + recall)

    assert f1 >= 0.85, f"F1 Score {f1:.4f} is below the threshold of 0.85. TP: {tp}, FP: {fp}, FN: {fn}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
