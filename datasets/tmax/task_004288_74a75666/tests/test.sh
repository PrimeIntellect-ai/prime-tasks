#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def get_expected_output():
    exp_dir = "/home/user/experiments"
    best_run_id = None
    max_mean_cv = -float('inf')
    best_l2_norm = 0.0

    if not os.path.isdir(exp_dir):
        return None

    for fname in sorted(os.listdir(exp_dir)):
        if not fname.endswith('.csv'):
            continue
        filepath = os.path.join(exp_dir, fname)

        try:
            with open(filepath, 'r') as f:
                reader = list(csv.DictReader(f))
        except Exception:
            continue

        # 1. Schema Enforcement: exclude files with invalid run_id
        valid_file = True
        for row in reader:
            run_id = row.get('run_id', '')
            # Strict integer check
            if not (run_id.isdigit() or (run_id.startswith('-') and run_id[1:].isdigit())):
                valid_file = False
                break

        if not valid_file:
            continue

        # 2-4. Cross-Validation Evaluation, Hyperparameter Selection, Linear Algebra
        for row in reader:
            try:
                cv1 = float(row['cv_fold_1'])
                cv2 = float(row['cv_fold_2'])
                cv3 = float(row['cv_fold_3'])
                mean_cv = (cv1 + cv2 + cv3) / 3.0

                if mean_cv > max_mean_cv:
                    max_mean_cv = mean_cv
                    best_run_id = row['run_id']
                    w1 = float(row['w_1'])
                    w2 = float(row['w_2'])
                    w3 = float(row['w_3'])
                    best_l2_norm = math.sqrt(w1**2 + w2**2 + w3**2)
            except (ValueError, KeyError):
                continue

    if best_run_id is None:
        return None

    # 5. Reporting format
    return f"{best_run_id},{max_mean_cv:.4f},{best_l2_norm:.4f}"

def test_best_model_stats_exists():
    output_file = "/home/user/best_model_stats.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"Path {output_file} exists but is not a regular file."

def test_best_model_stats_content():
    output_file = "/home/user/best_model_stats.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    expected_content = get_expected_output()
    assert expected_content is not None, "Could not compute expected output from /home/user/experiments/. Ensure the directory and valid CSV files exist."

    with open(output_file, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of {output_file} is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Actual:   '{actual_content}'\n"
        f"Please check if you correctly excluded invalid files, computed the mean CV score, and formatted to 4 decimal places."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
