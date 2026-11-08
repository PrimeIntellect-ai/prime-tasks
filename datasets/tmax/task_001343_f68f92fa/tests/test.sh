#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def extract_latencies(filename):
    latencies = []
    with open(filename, 'r') as f:
        for line in f:
            if "Inference time:" in line:
                try:
                    val_str = line.split("Inference time:")[1].strip().split()[0]
                    val = float(val_str)
                    if not math.isnan(val):
                        latencies.append(val)
                except Exception:
                    pass
    return latencies

def mean(data):
    return sum(data) / len(data)

def variance(data, ddof=1):
    m = mean(data)
    return sum((x - m) ** 2 for x in data) / (len(data) - ddof)

def t_pdf(x, df):
    return math.gamma((df + 1) / 2) / (math.sqrt(df * math.pi) * math.gamma(df / 2)) * (1 + x**2 / df)**(-(df + 1) / 2)

def t_cdf(t, df):
    limit = t if t < 0 else -t
    a = -40.0
    b = limit
    if b < a:
        cdf_lower = 0.0
    else:
        n = 20000
        h = (b - a) / n
        s = 0.5 * t_pdf(a, df) + 0.5 * t_pdf(b, df)
        for i in range(1, n):
            s += t_pdf(a + i * h, df)
        cdf_lower = s * h
    return cdf_lower if t < 0 else 1.0 - cdf_lower

def t_ppf(q, df):
    low = -40.0
    high = 40.0
    for _ in range(100):
        mid = (low + high) / 2.0
        if t_cdf(mid, df) < q:
            low = mid
        else:
            high = mid
    return (low + high) / 2.0

@pytest.fixture
def expected_results():
    data_A = extract_latencies("/home/user/raw_logs_A.txt")
    data_B = extract_latencies("/home/user/raw_logs_B.txt")

    n_A = len(data_A)
    n_B = len(data_B)

    mean_A = mean(data_A)
    mean_B = mean(data_B)

    var_A = variance(data_A)
    var_B = variance(data_B)

    se = math.sqrt(var_A / n_A + var_B / n_B)
    t_stat = (mean_A - mean_B) / se

    df = (var_A / n_A + var_B / n_B)**2 / ((var_A / n_A)**2 / (n_A - 1) + (var_B / n_B)**2 / (n_B - 1))

    p_value = 2.0 * t_cdf(-abs(t_stat), df)

    t_crit = t_ppf(0.975, df)
    diff = mean_A - mean_B
    ci_lower = diff - t_crit * se
    ci_upper = diff + t_crit * se

    return {
        "mean_A": round(mean_A, 4),
        "mean_B": round(mean_B, 4),
        "p_value": round(p_value, 4),
        "ci_lower": round(ci_lower, 4),
        "ci_upper": round(ci_upper, 4)
    }

def test_benchmark_results_exist():
    output_path = "/home/user/benchmark_results.json"
    assert os.path.exists(output_path), f"Expected output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Path {output_path} is not a regular file."

def test_benchmark_results_content(expected_results):
    output_path = "/home/user/benchmark_results.json"

    with open(output_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} is not valid JSON.")

    expected_keys = {"mean_A", "mean_B", "p_value", "ci_lower", "ci_upper"}
    assert set(results.keys()) == expected_keys, f"JSON keys do not match. Expected {expected_keys}, got {set(results.keys())}"

    for key in expected_keys:
        assert isinstance(results[key], (int, float)), f"Value for {key} must be a number."

        expected_val = expected_results[key]
        actual_val = results[key]

        assert math.isclose(actual_val, expected_val, abs_tol=0.00015), \
            f"Value for {key} is incorrect. Expected ~{expected_val}, got {actual_val}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
