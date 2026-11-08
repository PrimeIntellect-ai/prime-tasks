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

def get_csv_data(filepath):
    data = {}
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data[int(row['id'])] = row
    return data

def calculate_expected_results():
    priors_path = "/home/user/data/priors.csv"
    likelihoods_path = "/home/user/data/likelihoods.csv"
    preds_path = "/home/user/data/model_preds.csv"

    priors = get_csv_data(priors_path)
    likelihoods = get_csv_data(likelihoods_path)
    preds = get_csv_data(preds_path)

    common_ids = set(priors.keys()) & set(likelihoods.keys()) & set(preds.keys())

    unnormalized = {}
    for cid in common_ids:
        prior = float(priors[cid]['prior'])
        likelihood = float(likelihoods[cid]['likelihood'])
        unnormalized[cid] = prior * likelihood

    total_unnormalized = sum(unnormalized.values())

    flagged_ids = []
    valid_ids = []

    for cid in sorted(common_ids):
        norm_post = unnormalized[cid] / total_unnormalized
        pred_post = float(preds[cid]['predicted_posterior'])

        if abs(norm_post - pred_post) > 0.01:
            flagged_ids.append(cid)
        else:
            valid_ids.append(cid)

    valid_x = [float(priors[cid]['x']) for cid in valid_ids]
    valid_y = [float(likelihoods[cid]['y']) for cid in valid_ids]

    n = len(valid_x)
    sum_x = sum(valid_x)
    sum_y = sum(valid_y)
    sum_x_sq = sum(xi * xi for xi in valid_x)
    sum_y_sq = sum(yi * yi for yi in valid_y)
    p_sum = sum(xi * yi for xi, yi in zip(valid_x, valid_y))

    num = p_sum - (sum_x * sum_y / n)
    den = math.sqrt((sum_x_sq - sum_x**2 / n) * (sum_y_sq - sum_y**2 / n))
    corr = num / den if den != 0 else 0.0

    return sorted(flagged_ids), round(corr, 4)

def test_report_exists_and_valid():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"Expected report file {report_path} is missing."

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} does not contain valid JSON.")

    assert "flagged_ids" in report_data, "Key 'flagged_ids' missing from report."
    assert "correlation" in report_data, "Key 'correlation' missing from report."

def test_report_values():
    report_path = "/home/user/report.json"
    if not os.path.isfile(report_path):
        pytest.skip("Report file missing, skipping value test.")

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("Report file is not valid JSON, skipping value test.")

    expected_flagged, expected_corr = calculate_expected_results()

    actual_flagged = report_data.get("flagged_ids", [])
    assert isinstance(actual_flagged, list), "'flagged_ids' must be a list."
    assert sorted(actual_flagged) == expected_flagged, f"Expected flagged_ids {expected_flagged}, but got {actual_flagged}."

    actual_corr = report_data.get("correlation", None)
    assert actual_corr is not None, "Correlation value is null."
    assert isinstance(actual_corr, (int, float)), "'correlation' must be a number."
    assert round(actual_corr, 4) == expected_corr, f"Expected correlation {expected_corr}, but got {actual_corr}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
