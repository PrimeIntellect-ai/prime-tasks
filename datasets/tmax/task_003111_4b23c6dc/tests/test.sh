#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import numpy as np
import pytest

def compute_truth(seq):
    mapping = {'A': 1.0, 'C': 0.5, 'G': -0.5, 'T': -1.0}
    x = np.array([mapping.get(c, 0.0) for c in seq.strip()])
    X = np.fft.fft(x)
    P = np.abs(X)**2
    return np.sum(np.abs(np.diff(P)))

def test_output_accuracy():
    seq_file = "/home/user/sequences.txt"
    out_file = "/home/user/output.txt"

    assert os.path.exists(seq_file), f"Input file {seq_file} is missing."
    assert os.path.exists(out_file), f"Output file {out_file} is missing. The task requires creating this file."

    with open(seq_file, 'r') as f:
        seqs = [line.strip() for line in f if line.strip()]

    try:
        with open(out_file, 'r') as f:
            preds = [float(line.strip()) for line in f if line.strip()]
    except ValueError:
        pytest.fail(f"Output file {out_file} must contain only floating-point numbers.")

    assert len(preds) == len(seqs), (
        f"Number of scores in {out_file} ({len(preds)}) does not match "
        f"the number of sequences in {seq_file} ({len(seqs)})."
    )

    truth = np.array([compute_truth(s) for s in seqs])
    preds = np.array(preds)

    mse = np.mean((truth - preds)**2)
    threshold = 1e-4

    assert mse < threshold, (
        f"Mean Squared Error (MSE) is too high. "
        f"Expected < {threshold}, but got {mse:.6e}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
