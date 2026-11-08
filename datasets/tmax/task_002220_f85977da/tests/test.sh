#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
import pytest

RAW_DATA_PATH = "/home/user/raw_data.csv"
ENGINEERED_PATH = "/home/user/engineered.csv"
CORRELATIONS_PATH = "/home/user/correlations.txt"
SIMILAR_PATH = "/home/user/similar.txt"

def load_raw_data():
    with open(RAW_DATA_PATH, 'r') as f:
        reader = csv.DictReader(f)
        data = list(reader)
    return data

def compute_truth():
    data = load_raw_data()

    # Phase 1: compute normalized values at full available precision. Formatting
    # to four decimal places is applied only when engineered.csv is checked.
    fa = [float(row['Feature_A']) for row in data]
    fb = [float(row['Feature_B']) for row in data]
    fc = [float(row['Feature_C']) for row in data]

    min_a, max_a = min(fa), max(fa)
    min_b, max_b = min(fb), max(fb)
    min_c, max_c = min(fc), max(fc)

    engineered = []
    for row in data:
        na = (float(row['Feature_A']) - min_a) / (max_a - min_a)
        nb = (float(row['Feature_B']) - min_b) / (max_b - min_b)
        nc = (float(row['Feature_C']) - min_c) / (max_c - min_c)

        engineered.append({
            'ID': row['ID'],
            'Norm_A': na,
            'Norm_B': nb,
            'Norm_C': nc,
            'Target': int(row['Target'])
        })

    # Phase 2: Correlation, using unrounded normalized values.
    def pearson_corr(x, y):
        n = len(x)
        mean_x = sum(x) / n
        mean_y = sum(y) / n

        num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
        den_x = sum((xi - mean_x) ** 2 for xi in x)
        den_y = sum((yi - mean_y) ** 2 for yi in y)

        if den_x == 0 or den_y == 0:
            return 0.0
        return num / math.sqrt(den_x * den_y)

    norm_a = [row['Norm_A'] for row in engineered]
    norm_b = [row['Norm_B'] for row in engineered]
    norm_c = [row['Norm_C'] for row in engineered]
    targets = [row['Target'] for row in engineered]

    corr_a = pearson_corr(norm_a, targets)
    corr_b = pearson_corr(norm_b, targets)
    corr_c = pearson_corr(norm_c, targets)

    # Phase 3: Similarity, using unrounded normalized values.
    ref_row = next(row for row in engineered if row['ID'] == 'REF_001')
    distances = []

    for row in engineered:
        if row['ID'] == 'REF_001':
            continue
        dist = math.sqrt(
            (row['Norm_A'] - ref_row['Norm_A'])**2 +
            (row['Norm_B'] - ref_row['Norm_B'])**2 +
            (row['Norm_C'] - ref_row['Norm_C'])**2
        )
        distances.append((dist, row['ID']))

    distances.sort(key=lambda x: (x[0], x[1]))
    top_3 = [x[1] for x in distances[:3]]

    return engineered, (corr_a, corr_b, corr_c), top_3

def test_engineered_csv():
    assert os.path.exists(ENGINEERED_PATH), f"Missing {ENGINEERED_PATH}"

    truth_engineered, _, _ = compute_truth()

    with open(ENGINEERED_PATH, 'r') as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames
        assert headers == ['ID', 'Norm_A', 'Norm_B', 'Norm_C', 'Target'], f"Incorrect headers in {ENGINEERED_PATH}"

        rows = list(reader)
        assert len(rows) == len(truth_engineered), f"Expected {len(truth_engineered)} rows, got {len(rows)}"

        for expected, actual in zip(truth_engineered, rows):
            assert actual['ID'] == expected['ID']
            assert actual['Norm_A'] == f"{expected['Norm_A']:.4f}"
            assert actual['Norm_B'] == f"{expected['Norm_B']:.4f}"
            assert actual['Norm_C'] == f"{expected['Norm_C']:.4f}"
            assert actual['Target'] == str(expected['Target'])

def test_correlations_txt():
    assert os.path.exists(CORRELATIONS_PATH), f"Missing {CORRELATIONS_PATH}"

    _, truth_corrs, _ = compute_truth()
    expected_lines = [
        f"Norm_A: {truth_corrs[0]:.4f}",
        f"Norm_B: {truth_corrs[1]:.4f}",
        f"Norm_C: {truth_corrs[2]:.4f}",
    ]

    with open(CORRELATIONS_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Expected {expected_lines}, got {actual_lines}"

def test_similar_txt():
    assert os.path.exists(SIMILAR_PATH), f"Missing {SIMILAR_PATH}"

    _, _, truth_top_3 = compute_truth()

    with open(SIMILAR_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == truth_top_3, f"Expected {truth_top_3}, got {actual_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
