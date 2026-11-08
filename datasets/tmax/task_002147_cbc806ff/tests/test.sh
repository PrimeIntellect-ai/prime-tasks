#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
from scipy.stats import ttest_ind

def pearson_corr(x, y):
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    cov = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    var_x = sum((xi - mean_x) ** 2 for xi in x)
    var_y = sum((yi - mean_y) ** 2 for yi in y)
    if var_x == 0 or var_y == 0:
        return 0.0
    return cov / (var_x * var_y) ** 0.5

def test_selected_features_json_exists_and_correct():
    json_path = '/home/user/selected_features.json'
    csv_path = '/home/user/server_metrics.csv'

    assert os.path.exists(json_path), f"The file {json_path} is missing."
    assert os.path.exists(csv_path), f"The file {csv_path} is missing."

    # Read the dataset and compute the expected correlations
    data = []
    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Drop rows with any empty values
            if any(v.strip() == '' for v in row.values()):
                continue

            try:
                cpu = float(row['cpu_usage'])
                mem = float(row['mem_usage'])
                disk = float(row['disk_io'])
                net_rx = float(row['net_rx'])
                net_tx = float(row['net_tx'])
                status = float(row['status'])

                cpu_mem_ratio = cpu / mem
                total_net = net_rx + net_tx

                data.append({
                    'cpu_usage': cpu,
                    'mem_usage': mem,
                    'disk_io': disk,
                    'net_rx': net_rx,
                    'net_tx': net_tx,
                    'cpu_mem_ratio': cpu_mem_ratio,
                    'total_net': total_net,
                    'status': status
                })
            except ValueError:
                continue

    assert len(data) > 0, "No valid data found after dropping NaNs."

    features = ['cpu_usage', 'mem_usage', 'disk_io', 'net_rx', 'net_tx', 'cpu_mem_ratio', 'total_net']
    status_vals = [d['status'] for d in data]

    correlations = {}
    for f in features:
        f_vals = [d[f] for d in data]
        correlations[f] = pearson_corr(f_vals, status_vals)

    top_3 = sorted(features, key=lambda x: abs(correlations[x]), reverse=True)[:3]

    # Recompute the expected Welch t-test p-values from the source data.
    p_values = {}
    for f in top_3:
        normal = [d[f] for d in data if d['status'] == 0]
        failure = [d[f] for d in data if d['status'] == 1]
        _, p_value = ttest_ind(normal, failure, equal_var=False)
        p_values[f] = float(p_value)

    # Load the student's JSON
    with open(json_path, 'r') as f:
        try:
            student_output = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {json_path} is not valid JSON."

    assert isinstance(student_output, dict), "The JSON root must be a dictionary."

    student_keys = set(student_output.keys())
    expected_keys = set(top_3)

    assert student_keys == expected_keys, f"Expected top 3 features {expected_keys}, but got {student_keys}."

    for f in top_3:
        expected_corr = round(correlations[f], 4)
        expected_p = round(p_values[f], 4)
        student_feature_data = student_output[f]

        assert "correlation" in student_feature_data, f"Missing 'correlation' key for feature {f}."
        assert "p_value" in student_feature_data, f"Missing 'p_value' key for feature {f}."

        student_corr = student_feature_data["correlation"]
        assert isinstance(student_corr, (int, float)), f"Correlation for {f} must be a number."
        assert abs(student_corr - expected_corr) <= 0.0001, (
            f"Expected correlation for {f} to be {expected_corr}, got {student_corr}"
        )

        student_p = student_feature_data["p_value"]
        assert isinstance(student_p, (int, float)), f"p_value for {f} must be a number."
        assert 0.0 <= student_p <= 1.0, f"p_value for {f} must be between 0 and 1."
        assert abs(student_p - expected_p) <= 0.0001, (
            f"Expected Welch t-test p_value for {f} to be {expected_p}, got {student_p}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
