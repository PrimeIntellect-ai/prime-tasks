#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv

def read_col(filename, col_name):
    with open(filename, 'r') as f:
        reader = csv.DictReader(f)
        return [float(row[col_name]) for row in reader]

def mean(x):
    return sum(x) / len(x)

def std(x, ddof=0):
    m = mean(x)
    return (sum((xi - m)**2 for xi in x) / (len(x) - ddof))**0.5

def var(x, ddof=1):
    m = mean(x)
    return sum((xi - m)**2 for xi in x) / (len(x) - ddof)

def test_leakage_report_exists_and_valid():
    report_path = "/home/user/leakage_report.json"
    assert os.path.isfile(report_path), f"File not found: {report_path}"

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{report_path} is not a valid JSON file."

    required_keys = {"t_statistic", "p_value", "dot_product"}
    assert required_keys.issubset(data.keys()), f"JSON missing required keys. Found: {list(data.keys())}"

def test_leakage_report_values():
    report_path = "/home/user/leakage_report.json"
    with open(report_path, 'r') as f:
        data = json.load(f)

    # Recompute expected values
    train_f1 = read_col('/home/user/train.csv', 'feature_1')
    test_f1 = read_col('/home/user/test.csv', 'feature_1')

    train_f2 = read_col('/home/user/train.csv', 'feature_2')
    test_f2 = read_col('/home/user/test.csv', 'feature_2')

    # Incorrectly standardized feature_1
    test_f1_mean = mean(test_f1)
    test_f1_std = std(test_f1, ddof=0)
    incorrect_f1 = [(x - test_f1_mean) / test_f1_std for x in test_f1]

    # Correctly standardized feature_1
    train_f1_mean = mean(train_f1)
    train_f1_std = std(train_f1, ddof=0)
    correct_f1 = [(x - train_f1_mean) / train_f1_std for x in test_f1]

    # Correctly standardized feature_2
    train_f2_mean = mean(train_f2)
    train_f2_std = std(train_f2, ddof=0)
    correct_f2 = [(x - train_f2_mean) / train_f2_std for x in test_f2]

    # Welch's t-test statistic
    m1, m2 = mean(incorrect_f1), mean(correct_f1)
    v1, v2 = var(incorrect_f1, ddof=1), var(correct_f1, ddof=1)
    n1, n2 = len(incorrect_f1), len(correct_f1)
    expected_t_stat = (m1 - m2) / (v1/n1 + v2/n2)**0.5

    # Dot product
    expected_dot_product = sum(x * y for x, y in zip(correct_f1, correct_f2))

    # Assertions
    assert isinstance(data["t_statistic"], (int, float)), "t_statistic must be a number"
    assert isinstance(data["p_value"], (int, float)), "p_value must be a number"
    assert isinstance(data["dot_product"], (int, float)), "dot_product must be a number"

    assert abs(data["t_statistic"] - round(expected_t_stat, 4)) <= 0.0001, \
        f"Expected t_statistic ~{round(expected_t_stat, 4)}, got {data['t_statistic']}"

    assert abs(data["dot_product"] - round(expected_dot_product, 4)) <= 0.0001, \
        f"Expected dot_product ~{round(expected_dot_product, 4)}, got {data['dot_product']}"

    # Check p-value against known approximate truth since computing t-CDF in stdlib is complex
    expected_p_value = 0.0647
    assert abs(data["p_value"] - expected_p_value) <= 0.0005, \
        f"Expected p_value ~{expected_p_value}, got {data['p_value']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
