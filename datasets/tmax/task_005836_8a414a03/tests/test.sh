#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def test_report_exists_and_format():
    report_path = '/home/user/report.json'
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("report.json is not a valid JSON file.")

    assert "alpha_accuracy_correlation" in report, "Missing 'alpha_accuracy_correlation' in report.json"
    assert "best_hyperparameters" in report, "Missing 'best_hyperparameters' in report.json"
    assert "alpha" in report["best_hyperparameters"], "Missing 'alpha' in best_hyperparameters"
    assert "l1_ratio" in report["best_hyperparameters"], "Missing 'l1_ratio' in best_hyperparameters"
    assert "best_cv_score" in report, "Missing 'best_cv_score' in report.json"
    assert "top_3_similar_experiments" in report, "Missing 'top_3_similar_experiments' in report.json"
    assert isinstance(report["top_3_similar_experiments"], list), "'top_3_similar_experiments' must be a list"

def test_alpha_accuracy_correlation():
    report_path = '/home/user/report.json'
    with open(report_path, 'r') as f:
        report = json.load(f)

    experiments_dir = '/home/user/experiments'
    alphas = []
    accuracies = []
    for i in range(1, 51):
        filepath = os.path.join(experiments_dir, f'exp_{i:02d}.json')
        if not os.path.exists(filepath):
            continue
        with open(filepath, 'r') as f:
            data = json.load(f)
            alphas.append(data['hyperparameters']['alpha'])
            accuracies.append(data['metrics']['accuracy'])

    n = len(alphas)
    if n == 0:
        pytest.fail("No experiment files found to calculate expected correlation.")

    mean_a = sum(alphas) / n
    mean_acc = sum(accuracies) / n
    num = sum((a - mean_a) * (acc - mean_acc) for a, acc in zip(alphas, accuracies))
    den = math.sqrt(sum((a - mean_a)**2 for a in alphas) * sum((acc - mean_acc)**2 for acc in accuracies))
    expected_corr = num / den if den != 0 else 0.0

    actual_corr = report['alpha_accuracy_correlation']
    assert math.isclose(actual_corr, expected_corr, rel_tol=1e-2), \
        f"Expected correlation ~{expected_corr:.4f}, but got {actual_corr}"

def test_best_hyperparameters_and_score():
    report_path = '/home/user/report.json'
    with open(report_path, 'r') as f:
        report = json.load(f)

    best_hp = report['best_hyperparameters']
    assert math.isclose(best_hp['alpha'], 0.01, rel_tol=1e-4), \
        f"Expected best alpha to be 0.01, got {best_hp['alpha']}"
    assert math.isclose(best_hp['l1_ratio'], 0.0, abs_tol=1e-4), \
        f"Expected best l1_ratio to be 0.0, got {best_hp['l1_ratio']}"

    actual_score = report['best_cv_score']
    assert math.isclose(actual_score, 0.852, rel_tol=1e-2), \
        f"Expected best_cv_score ~0.852, but got {actual_score}"

def test_top_3_similar_experiments():
    report_path = '/home/user/report.json'
    with open(report_path, 'r') as f:
        report = json.load(f)

    best_alpha = report['best_hyperparameters']['alpha']
    best_l1 = report['best_hyperparameters']['l1_ratio']

    experiments_dir = '/home/user/experiments'
    similarities = []
    for i in range(1, 51):
        exp_id = f'exp_{i:02d}'
        filepath = os.path.join(experiments_dir, f'{exp_id}.json')
        if not os.path.exists(filepath):
            continue
        with open(filepath, 'r') as f:
            data = json.load(f)
            a = data['hyperparameters']['alpha']
            l = data['hyperparameters']['l1_ratio']

            dot = best_alpha * a + best_l1 * l
            norm1 = math.sqrt(best_alpha**2 + best_l1**2)
            norm2 = math.sqrt(a**2 + l**2)
            sim = dot / (norm1 * norm2) if norm1 * norm2 > 0 else 0.0
            similarities.append((sim, exp_id))

    # Sort by similarity descending, then by experiment_id ascending
    similarities.sort(key=lambda x: (-x[0], x[1]))
    expected_top_3 = [x[1] for x in similarities[:3]]

    actual_top_3 = report['top_3_similar_experiments']
    assert actual_top_3 == expected_top_3, \
        f"Expected top 3 similar experiments to be {expected_top_3}, but got {actual_top_3}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
