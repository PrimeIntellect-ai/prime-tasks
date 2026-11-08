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

def calculate_correlation(x, y):
    n = len(x)
    if n < 2:
        return None
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)
    if den_x == 0 or den_y == 0:
        return None
    return num / math.sqrt(den_x * den_y)

def get_expected_results():
    weights_path = "/home/user/data/model_weights.json"
    metrics_path = "/home/user/data/raw_metrics.csv"

    with open(weights_path, "r") as f:
        weights = json.load(f)

    w1 = weights["W1"]
    w2 = weights["W2"]
    w3 = weights["W3"]
    b = weights["b"]

    normal_f4 = []
    normal_f5 = []
    anomaly_f4 = []
    anomaly_f5 = []

    with open(metrics_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            f1 = float(row["f1"])
            f2 = float(row["f2"])
            f3 = float(row["f3"])
            f4 = float(row["f4"])
            f5 = float(row["f5"])

            score = (f1 * w1) + (f2 * w2) + (f3 * w3) + b
            if score > 0.5:
                anomaly_f4.append(f4)
                anomaly_f5.append(f5)
            else:
                normal_f4.append(f4)
                normal_f5.append(f5)

    corr_normal = calculate_correlation(normal_f4, normal_f5)
    corr_anomaly = calculate_correlation(anomaly_f4, anomaly_f5)

    return {
        "correlation_normal": round(corr_normal, 5) if corr_normal is not None else None,
        "correlation_anomaly": round(corr_anomaly, 5) if corr_anomaly is not None else None
    }

def test_analysis_output_exists():
    assert os.path.isfile("/home/user/output/analysis.json"), "The output file /home/user/output/analysis.json does not exist."

def test_analysis_output_content():
    output_path = "/home/user/output/analysis.json"
    assert os.path.isfile(output_path), "The output file /home/user/output/analysis.json does not exist."

    with open(output_path, "r") as f:
        try:
            student_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/output/analysis.json is not valid JSON.")

    expected_output = get_expected_results()

    assert "correlation_normal" in student_output, "Key 'correlation_normal' is missing from the output JSON."
    assert "correlation_anomaly" in student_output, "Key 'correlation_anomaly' is missing from the output JSON."

    assert student_output["correlation_normal"] == expected_output["correlation_normal"], \
        f"Expected correlation_normal to be {expected_output['correlation_normal']}, got {student_output['correlation_normal']}"

    assert student_output["correlation_anomaly"] == expected_output["correlation_anomaly"], \
        f"Expected correlation_anomaly to be {expected_output['correlation_anomaly']}, got {student_output['correlation_anomaly']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
