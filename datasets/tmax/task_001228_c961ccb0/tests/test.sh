#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
import numpy as np
import pytest

def compute_energy_canonical(sequence, seed=42):
    np.random.seed(seed)
    conformations = np.random.randn(1000, 4, 20)

    seq_map = {'A':0, 'C':1, 'G':2, 'T':3}
    seq_encoded = np.array([seq_map[c] for c in sequence])

    def eval_conf(conf):
        val = 0.0
        for i in range(20):
            val += conf[seq_encoded[i], i] * (10 ** (i % 7 - 3))
        return val

    results = [eval_conf(conformations[i]) for i in range(1000)]
    return math.fsum(results)

def get_best_mutation(sequence):
    best_energy = float('inf')
    best_seq = ""
    bases = ['A', 'C', 'G', 'T']

    for i in range(len(sequence)):
        for b in bases:
            if b == sequence[i]:
                continue
            mutated = sequence[:i] + b + sequence[i+1:]
            energy = compute_energy_canonical(mutated)
            if energy < best_energy:
                best_energy = energy
                best_seq = mutated
            elif energy == best_energy:
                if mutated < best_seq:
                    best_seq = mutated
    return best_seq, best_energy

def test_results_csv_exists_and_format():
    file_path = "/home/user/results.csv"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) == 6, f"Expected 6 rows (1 header + 5 data), but got {len(rows)}."

    expected_header = ["original_sequence", "original_energy", "best_mutated_sequence", "best_energy"]
    assert rows[0] == expected_header, f"Header row does not match expected: {expected_header}"

    raw_reads = "ACGTACGTACGTACGTACGTGCATGCATGCATGCATGCATTTAACCGGTTTTAACCGGTTGGCCAATTGGCCAATTGGCCTAGCTAGCTAGCTAGCTAGC"
    expected_sequences = [raw_reads[i:i+20] for i in range(0, 100, 20)]

    for i in range(5):
        orig_seq = expected_sequences[i]
        orig_energy = compute_energy_canonical(orig_seq)
        best_mut_seq, best_mut_energy = get_best_mutation(orig_seq)

        row = rows[i+1]
        assert row[0] == orig_seq, f"Row {i+1}: Expected original sequence {orig_seq}, got {row[0]}"
        assert f"{orig_energy:.6f}" == row[1], f"Row {i+1}: Expected original energy {orig_energy:.6f}, got {row[1]}"
        assert row[2] == best_mut_seq, f"Row {i+1}: Expected best mutated sequence {best_mut_seq}, got {row[2]}"
        assert f"{best_mut_energy:.6f}" == row[3], f"Row {i+1}: Expected best energy {best_mut_energy:.6f}, got {row[3]}"

def test_mc_energy_reproducibility():
    import sys
    sys.path.insert(0, "/home/user")
    import mc_energy

    seq = "ACGTACGTACGTACGTACGT"
    val1 = mc_energy.compute_energy(seq)
    val2 = mc_energy.compute_energy(seq)

    assert val1 == val2, "compute_energy is not reproducible. It returned different values for the same sequence."

    expected_val = compute_energy_canonical(seq)
    assert math.isclose(val1, expected_val, rel_tol=1e-9), f"compute_energy result {val1} does not match expected {expected_val}. Ensure math.fsum is used correctly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
