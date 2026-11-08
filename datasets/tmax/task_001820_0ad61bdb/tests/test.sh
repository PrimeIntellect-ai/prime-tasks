#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import glob
import json
import math
import pytest

def test_analysis_report_exists_and_valid():
    """Verify that the analysis report exists and is valid JSON."""
    report_path = '/home/user/analysis_report.json'
    assert os.path.exists(report_path), f"File {report_path} does not exist."

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("analysis_report.json is not a valid JSON file.")

    assert isinstance(report, dict), "The JSON root must be an object/dictionary."
    assert "posterior_means" in report, "Missing 'posterior_means' key in the report."
    assert "first_pc" in report, "Missing 'first_pc' key in the report."

def test_analysis_report_values():
    """Verify the computed posteriors and the first principal component."""
    report_path = '/home/user/analysis_report.json'
    with open(report_path, 'r') as f:
        report = json.load(f)

    # 1. Read and aggregate data
    groups = {}
    csv_files = glob.glob('/home/user/datasets/*.csv')
    assert len(csv_files) > 0, "No CSV files found in /home/user/datasets/"

    for filepath in csv_files:
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                g = row['group']
                if g not in groups:
                    groups[g] = {
                        'trials': 0, 'successes': 0,
                        'f1': 0.0, 'f2': 0.0, 'f3': 0.0,
                        'count': 0
                    }
                groups[g]['trials'] += int(row['trials'])
                groups[g]['successes'] += int(row['successes'])
                groups[g]['f1'] += float(row['f1'])
                groups[g]['f2'] += float(row['f2'])
                groups[g]['f3'] += float(row['f3'])
                groups[g]['count'] += 1

    sorted_group_names = sorted(groups.keys())
    expected_posteriors = {}
    X = []

    # 2. Compute posterior means and feature means
    for g in sorted_group_names:
        d = groups[g]
        # Beta(1,1) prior -> Posterior mean = (1 + successes) / (2 + trials)
        expected_posteriors[g] = (1 + d['successes']) / (2 + d['trials'])

        f1_mean = d['f1'] / d['count']
        f2_mean = d['f2'] / d['count']
        f3_mean = d['f3'] / d['count']
        X.append([f1_mean, f2_mean, f3_mean])

    # Check posterior means
    agent_posteriors = report['posterior_means']
    for g, exp_val in expected_posteriors.items():
        assert g in agent_posteriors, f"Missing group '{g}' in posterior_means."
        assert math.isclose(agent_posteriors[g], exp_val, abs_tol=1e-5), \
            f"Expected posterior mean for {g} to be roughly {exp_val}, got {agent_posteriors[g]}"

    # 3. Compute First Principal Component using Power Iteration on Covariance Matrix
    n_rows = len(X)
    n_cols = 3
    col_means = [sum(X[i][j] for i in range(n_rows)) / n_rows for j in range(n_cols)]

    X_centered = []
    for i in range(n_rows):
        X_centered.append([X[i][j] - col_means[j] for j in range(n_cols)])

    # Covariance matrix X^T X
    XtX = [[0.0] * n_cols for _ in range(n_cols)]
    for i in range(n_cols):
        for j in range(n_cols):
            XtX[i][j] = sum(X_centered[k][i] * X_centered[k][j] for k in range(n_rows))

    # Power Iteration to find the dominant eigenvector
    v = [1.0, 1.0, 1.0]
    for _ in range(100):
        v_new = [sum(XtX[i][j] * v[j] for j in range(n_cols)) for i in range(n_cols)]
        norm = math.sqrt(sum(x * x for x in v_new))
        v = [x / norm for x in v_new]

    # Deterministic sign constraint
    if v[0] < 0:
        v = [-x for x in v]

    # Check first PC
    agent_pc = report['first_pc']
    assert isinstance(agent_pc, list), "'first_pc' must be a list."
    assert len(agent_pc) == 3, f"'first_pc' must have exactly 3 elements, found {len(agent_pc)}."

    for i in range(3):
        assert math.isclose(agent_pc[i], v[i], abs_tol=1e-5), \
            f"Mismatch in 'first_pc' at index {i}. Expected ~{v[i]:.5f}, got {agent_pc[i]:.5f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
