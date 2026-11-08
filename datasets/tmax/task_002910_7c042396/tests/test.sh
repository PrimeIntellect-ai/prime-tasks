#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import pytest
import numpy as np

def calc_corr(x, y):
    n = len(x)
    if n == 0:
        return 0.0
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    cov = sum((a - mean_x) * (b - mean_y) for a, b in zip(x, y))
    var_x = sum((a - mean_x) ** 2 for a in x)
    var_y = sum((b - mean_y) ** 2 for b in y)
    if var_x == 0 or var_y == 0:
        return 0.0
    return cov / math.sqrt(var_x * var_y)

def test_audit_report_content():
    report_path = "/home/user/audit_report.json"
    assert os.path.exists(report_path), f"Output file {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not a valid JSON file.")

    expected_keys = {
        "corrupted_runs",
        "uncorrupted_corr",
        "corrupted_corr",
        "bootstrap_ci_lower",
        "bootstrap_ci_upper"
    }
    assert set(report.keys()) == expected_keys, f"JSON keys do not match expected keys. Found: {list(report.keys())}"

    experiments_dir = "/home/user/experiments"
    corrupted_files = []
    clean_true_labels = []
    clean_pred_probs = []
    corr_true_labels = []
    corr_pred_probs = []

    for i in range(1, 11):
        filename = f"run_{i:02d}.csv"
        filepath = os.path.join(experiments_dir, filename)

        is_corrupted = False
        true_labels = []
        pred_probs = []

        with open(filepath, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                # NaNs are represented as empty strings in standard CSV serialization
                if row.get("text_token_id", "").strip() == "":
                    is_corrupted = True

                true_labels.append(float(row["true_label"]))
                pred_probs.append(float(row["predicted_prob"]))

        if is_corrupted:
            corrupted_files.append(filename)
            corr_true_labels.extend(true_labels)
            corr_pred_probs.extend(pred_probs)
        else:
            clean_true_labels.extend(true_labels)
            clean_pred_probs.extend(pred_probs)

    corrupted_files.sort()

    expected_uncorrupted_corr = round(calc_corr(clean_true_labels, clean_pred_probs), 5)
    expected_corrupted_corr = round(calc_corr(corr_true_labels, corr_pred_probs), 5)

    assert report["corrupted_runs"] == corrupted_files, \
        f"Expected corrupted_runs {corrupted_files}, got {report['corrupted_runs']}"

    assert report["uncorrupted_corr"] == expected_uncorrupted_corr, \
        f"Expected uncorrupted_corr {expected_uncorrupted_corr}, got {report['uncorrupted_corr']}"

    assert report["corrupted_corr"] == expected_corrupted_corr, \
        f"Expected corrupted_corr {expected_corrupted_corr}, got {report['corrupted_corr']}"

    assert isinstance(report["bootstrap_ci_lower"], float), "bootstrap_ci_lower must be a float"
    assert isinstance(report["bootstrap_ci_upper"], float), "bootstrap_ci_upper must be a float"
    assert report["bootstrap_ci_lower"] < report["bootstrap_ci_upper"], \
        "bootstrap_ci_lower must be strictly less than bootstrap_ci_upper"

    # Check that bootstrap CI bounds are somewhat close to the base correlation
    assert report["bootstrap_ci_lower"] < expected_uncorrupted_corr, \
        "bootstrap_ci_lower should be less than the uncorrupted_corr"
    assert report["bootstrap_ci_upper"] > expected_uncorrupted_corr, \
        "bootstrap_ci_upper should be greater than the uncorrupted_corr"

    # Reproduce the required seeded 1000-iteration bootstrap exactly.
    clean_true = np.asarray(clean_true_labels, dtype=float)
    clean_pred = np.asarray(clean_pred_probs, dtype=float)
    sample_size = len(clean_true)
    bootstrap_corrs = []
    np.random.seed(42)
    for _ in range(1000):
        indices = np.random.choice(sample_size, size=sample_size, replace=True)
        bootstrap_corrs.append(calc_corr(clean_true[indices], clean_pred[indices]))

    expected_ci_lower, expected_ci_upper = np.percentile(
        bootstrap_corrs, [2.5, 97.5]
    )
    expected_ci_lower = round(float(expected_ci_lower), 5)
    expected_ci_upper = round(float(expected_ci_upper), 5)

    assert report["bootstrap_ci_lower"] == expected_ci_lower, \
        f"Expected bootstrap_ci_lower {expected_ci_lower}, got {report['bootstrap_ci_lower']}"
    assert report["bootstrap_ci_upper"] == expected_ci_upper, \
        f"Expected bootstrap_ci_upper {expected_ci_upper}, got {report['bootstrap_ci_upper']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
