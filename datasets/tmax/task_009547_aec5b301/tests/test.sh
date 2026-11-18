#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_result_json_exists_and_correct():
    result_path = "/home/user/result.json"
    assert os.path.isfile(result_path), f"The file {result_path} does not exist."

    with open(result_path, "r") as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {result_path} is not valid JSON.")

    # Compute expected values
    fasta_path = "/home/user/bio_data/sequences.fasta"
    assert os.path.isfile(fasta_path), f"The file {fasta_path} does not exist."

    seqs = []
    with open(fasta_path, "r") as f:
        for line in f:
            if not line.startswith(">"):
                seqs.append(line.strip())

    gc_averages = {}
    for n in range(10, len(seqs) + 1, 10):
        subset = seqs[:n]
        total_gc = sum(s.count('G') + s.count('C') for s in subset)
        total_len = sum(len(s) for s in subset)
        gc_averages[n] = total_gc / total_len if total_len > 0 else 0

    diffs = {}
    for n in range(20, len(seqs) + 1, 10):
        diffs[n] = abs(gc_averages[n] - gc_averages[n-10])

    converged_N = None
    for n in range(40, len(seqs) + 1, 10):
        if n-20 in diffs and n-10 in diffs and n in diffs:
            if diffs[n-20] < 0.005 and diffs[n-10] < 0.005 and diffs[n] < 0.005:
                converged_N = n
                break

    assert converged_N is not None, "Could not find convergence in the provided FASTA file."

    avg_gc = round(gc_averages[converged_N], 5)

    ref_path = "/home/user/bio_data/reference_gc.txt"
    assert os.path.isfile(ref_path), f"The file {ref_path} does not exist."
    with open(ref_path, "r") as f:
        ref_gc = float(f.read().strip())

    ref_gc_rounded = round(ref_gc, 5)
    diff = round(abs(avg_gc - ref_gc_rounded), 5)

    expected_keys = {"converged_N", "average_gc", "reference_gc", "difference"}
    assert set(result.keys()) == expected_keys, f"Result JSON must contain exactly keys: {expected_keys}"

    assert result["converged_N"] == converged_N, f"Expected converged_N to be {converged_N}, got {result['converged_N']}"
    assert result["average_gc"] == avg_gc, f"Expected average_gc to be {avg_gc}, got {result['average_gc']}"
    assert result["reference_gc"] == ref_gc_rounded, f"Expected reference_gc to be {ref_gc_rounded}, got {result['reference_gc']}"
    assert result["difference"] == diff, f"Expected difference to be {diff}, got {result['difference']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
