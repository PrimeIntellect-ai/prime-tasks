#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import csv
import math
import os
import pytest

def test_results_csv_exists_and_correct():
    results_path = '/home/user/results.csv'
    assert os.path.isfile(results_path), f"File {results_path} does not exist. Ensure you saved the output correctly."

    with open(results_path, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['id', 'prob', 'class'], f"Expected header ['id', 'prob', 'class'], got {header}"

        rows = list(reader)

    assert len(rows) == 8, f"Expected exactly 8 rows of data, got {len(rows)}"

    # Original data to recompute expectations robustly
    data = [
        {'id': 101, 'age': 25, 'income': 45000, 'score_A': 80, 'score_B': 75, 'category': 'A'},
        {'id': 102, 'age': 15, 'income': 75000, 'score_A': 90, 'score_B': 85, 'category': 'B'},
        {'id': 103, 'age': 95, 'income': None, 'score_A': 70, 'score_B': 65, 'category': 'C'},
        {'id': 104, 'age': 45, 'income': 55000, 'score_A': 85, 'score_B': 90, 'category': 'A'},
        {'id': 105, 'age': 30, 'income': 120000, 'score_A': 60, 'score_B': 55, 'category': 'A'},
        {'id': 106, 'age': -5, 'income': None, 'score_A': 95, 'score_B': 88, 'category': 'B'},
        {'id': 107, 'age': 50, 'income': 61000, 'score_A': 50, 'score_B': 60, 'category': 'C'},
        {'id': 108, 'age': 42, 'income': 58000, 'score_A': 75, 'score_B': 80, 'category': 'B'}
    ]

    # Recompute median income
    incomes = sorted([d['income'] for d in data if d['income'] is not None])
    n = len(incomes)
    if n % 2 == 0:
        median_income = (incomes[n//2 - 1] + incomes[n//2]) / 2.0
    else:
        median_income = incomes[n//2]

    expected_results = {}
    for d in data:
        # Data Cleaning
        age = max(18, min(90, d['age']))
        income = d['income'] if d['income'] is not None else median_income

        # Feature Engineering
        combined = (d['score_A'] * 0.4) + (d['score_B'] * 0.6)
        income_bracket = 1 if income > 60000 else 0
        cat_A = 1 if d['category'] == 'A' else 0
        cat_B = 1 if d['category'] == 'B' else 0
        cat_C = 1 if d['category'] == 'C' else 0

        # Model Inference
        z = -2.5 + (0.02 * age) + (0.05 * combined) + (0.8 * income_bracket) + (0.5 * cat_A) + (-0.3 * cat_B) + (0.0 * cat_C)
        prob = 1 / (1 + math.exp(-z))
        cls = 1 if prob >= 0.5 else 0

        expected_results[str(d['id'])] = (f"{prob:.4f}", str(cls))

    # Require every expected customer exactly once.
    submitted_ids = [row[0] for row in rows if len(row) > 0]
    assert len(submitted_ids) == len(set(submitted_ids)), "Each customer id must appear exactly once; duplicate ids were found."
    assert set(submitted_ids) == set(expected_results), f"Expected ids {sorted(expected_results)}, got {sorted(set(submitted_ids))}"

    # Verify the output rows against the expected results
    for row in rows:
        assert len(row) == 3, f"Row {row} does not have exactly 3 columns."
        row_id, row_prob, row_cls = row
        assert row_id in expected_results, f"Unexpected id {row_id} found in results."

        exp_prob, exp_cls = expected_results[row_id]

        assert row_prob == exp_prob, f"For id {row_id}, expected prob {exp_prob}, but got {row_prob}"
        assert row_cls == exp_cls, f"For id {row_id}, expected class {exp_cls}, but got {row_cls}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
