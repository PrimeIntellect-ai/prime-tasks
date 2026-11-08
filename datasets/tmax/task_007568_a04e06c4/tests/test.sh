#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

DATA_DIR = "/home/user/data"
EMBEDDINGS_FILE = os.path.join(DATA_DIR, "embeddings.csv")
BASELINE_FILE = os.path.join(DATA_DIR, "baseline.txt")
RESULTS_FILE = "/home/user/results.log"

def calc_dist(vA, vB):
    return sum((a - b) ** 2 for a, b in zip(vA, vB))

def get_expected_results():
    assert os.path.exists(EMBEDDINGS_FILE), f"Missing {EMBEDDINGS_FILE}"

    with open(EMBEDDINGS_FILE, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        data = {row[0]: [float(x) for x in row[1:]] for row in reader}

    assert 'doc_73' in data, "Target 'doc_73' missing from embeddings"
    target = data['doc_73']

    dists = []
    for k, v in data.items():
        if k == 'doc_73':
            continue
        dists.append((k, calc_dist(target, v)))

    dists.sort(key=lambda x: x[1])
    top_3 = [x[0] for x in dists[:3]]

    assert os.path.exists(BASELINE_FILE), f"Missing {BASELINE_FILE}"
    with open(BASELINE_FILE, 'r') as f:
        baseline_id = f.read().strip()

    status = "MATCH" if top_3[0] == baseline_id else "MISMATCH"

    return top_3, status

def test_results_log_exists():
    assert os.path.isfile(RESULTS_FILE), f"Results file {RESULTS_FILE} was not created."

def test_results_content():
    expected_top_3, expected_status = get_expected_results()

    with open(RESULTS_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {RESULTS_FILE}, found {len(lines)}."

    assert lines[0] == expected_top_3[0], f"Line 1 expected {expected_top_3[0]}, got {lines[0]}"
    assert lines[1] == expected_top_3[1], f"Line 2 expected {expected_top_3[1]}, got {lines[1]}"
    assert lines[2] == expected_top_3[2], f"Line 3 expected {expected_top_3[2]}, got {lines[2]}"
    assert lines[3] == expected_status, f"Line 4 expected {expected_status}, got {lines[3]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
