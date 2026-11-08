#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os

import numpy as np


def calculate_entropy(sequence):
    spectrum = np.zeros(1000, dtype=float)
    for i, aa in enumerate(sequence):
        freq = (ord(aa) * 7) % 1000
        spectrum[freq] += (i + 1) * 0.5

    shifted = spectrum - np.max(spectrum)
    probabilities = np.exp(shifted)
    probabilities /= np.sum(probabilities)

    smoothed = np.convolve(
        probabilities, np.ones(5, dtype=float) / 5.0, mode="same"
    )
    smoothed = np.clip(smoothed, 1e-12, None)
    return -np.sum(smoothed * np.log(smoothed))


def expected_rows():
    sequences = {
        "seq1_short": "MATTG",
        "seq2_medium": "VLEIVMATTGVLEIVMATTGVLEIV",
        "seq3_long": "A" * 1024,
        "seq4_mixed": "ACDEFGHIKLMNPQRSTVWY" * 3,
    }
    return [
        [sequence_id, f"{calculate_entropy(sequences[sequence_id]):.4f}"]
        for sequence_id in sorted(sequences)
    ]


def test_features_csv_exists():
    """Test that the output CSV file exists."""
    csv_path = "/home/user/features.csv"
    assert os.path.exists(csv_path), f"Output file is missing: {csv_path}"
    assert os.path.isfile(csv_path), f"Path exists but is not a file: {csv_path}"


def test_features_csv_content():
    """Test that the output CSV file has the correct content and formatting."""
    csv_path = "/home/user/features.csv"
    expected = expected_rows()

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The CSV file is empty."

    header = rows[0]
    assert header == ["ID", "Entropy"], \
        f"Expected header ['ID', 'Entropy'], but got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == len(expected), \
        f"Expected {len(expected)} data rows, but got {len(data_rows)}."

    for i, (actual, wanted) in enumerate(zip(data_rows, expected)):
        assert actual == wanted, \
            f"Row {i + 1} mismatch. Expected {wanted}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
