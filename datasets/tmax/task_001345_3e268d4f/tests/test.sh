#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np


def levenshtein_distance(s1, s2):
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)

    if len(s2) == 0:
        return len(s1)

    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row

    return previous_row[-1]


def read_fasta(path):
    with open(path, 'r') as f:
        lines = f.readlines()
    return "".join(l.strip() for l in lines if not l.startswith('>'))


def expected_sequence():
    rng = np.random.RandomState(42)
    return "".join(rng.choice(['A', 'C', 'G', 'T'], size=200))


def test_decoded_fasta_exists():
    path = "/home/user/decoded.fasta"
    assert os.path.exists(path), f"File {path} does not exist. Did you output the reconstructed sequence?"
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_accuracy_metric():
    decoded_path = "/home/user/decoded.fasta"
    assert os.path.exists(decoded_path), f"Decoded file {decoded_path} is missing."

    truth_seq = expected_sequence()
    decoded_seq = read_fasta(decoded_path)

    dist = levenshtein_distance(truth_seq, decoded_seq)
    max_len = max(len(truth_seq), len(decoded_seq))
    accuracy = (max_len - dist) / max_len if max_len > 0 else 0

    assert accuracy >= 0.95, f"Sequence alignment accuracy is {accuracy:.4f}, which is below the 0.95 threshold."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
