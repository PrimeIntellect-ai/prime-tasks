#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy import stats

ANALYZE = "/home/user/analyze.py"
METRICS = "/home/user/metrics.json"
CSV_A = "/home/user/engine_a.csv"
CSV_B = "/home/user/engine_b.csv"


def run_analysis():
    result = subprocess.run(
        ["python3", ANALYZE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"analyze.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(METRICS), "analyze.py did not create /home/user/metrics.json"


def load_metrics():
    with open(METRICS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/metrics.json is not a valid JSON file.")


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_script():
    assert os.path.isfile(ANALYZE), "The file /home/user/analyze.py does not exist."
    run_analysis()


def get_columns(filename, col1, col2):
    """Reads two columns from a CSV file and returns them as lists of floats."""
    x, y = [], []
    with open(filename, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            x.append(float(row[col1]))
            y.append(float(row[col2]))
    return x, y


def pearson_correlation(x, y):
    """Computes the Pearson correlation coefficient."""
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    cov = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    var_x = sum((xi - mean_x) ** 2 for xi in x)
    var_y = sum((yi - mean_y) ** 2 for yi in y)
    if var_x == 0 or var_y == 0:
        return 0.0
    return cov / math.sqrt(var_x * var_y)


def test_analyze_py_exists():
    assert os.path.isfile(ANALYZE), "The file /home/user/analyze.py does not exist."


def test_metrics_json_exists():
    """Test that the metrics.json file was created."""
    assert os.path.isfile(METRICS), "The file /home/user/metrics.json does not exist."


def test_metrics_json_content():
    """Retain the original checks for the supplied datasets."""
    metrics = load_metrics()
    expected_keys = {"correlation_A", "correlation_B", "t_statistic", "p_value"}
    assert set(metrics.keys()) == expected_keys, f"metrics.json keys do not match expected. Found: {list(metrics.keys())}"

    input_a, latency_a = get_columns(CSV_A, "input_size", "latency_ms")
    expected_corr_a = pearson_correlation(input_a, latency_a)
    input_b, latency_b = get_columns(CSV_B, "input_size", "latency_ms")
    expected_corr_b = pearson_correlation(input_b, latency_b)

    assert math.isclose(metrics["correlation_A"], expected_corr_a, abs_tol=1e-4), \
        f"correlation_A is incorrect. Expected ~{expected_corr_a}, got {metrics['correlation_A']}"
    assert math.isclose(metrics["correlation_B"], expected_corr_b, abs_tol=1e-4), \
        f"correlation_B is incorrect. Expected ~{expected_corr_b}, got {metrics['correlation_B']}"

    expected_t_stat = 4.8817
    expected_p_value = 2.155e-06
    assert math.isclose(metrics["t_statistic"], expected_t_stat, abs_tol=1e-3), \
        f"t_statistic is incorrect. Expected ~{expected_t_stat}, got {metrics['t_statistic']}"
    assert math.isclose(metrics["p_value"], expected_p_value, abs_tol=1e-7), \
        f"p_value is incorrect. Expected ~{expected_p_value}, got {metrics['p_value']}"


def expected_for(a, b):
    corr_a = a["input_size"].corr(a["latency_ms"])
    corr_b = b["input_size"].corr(b["latency_ms"])
    sampled_a, sampled_b = a, b
    if len(sampled_a) > len(sampled_b):
        sampled_a = sampled_a.sample(n=len(sampled_b), random_state=42)
    elif len(sampled_b) > len(sampled_a):
        sampled_b = sampled_b.sample(n=len(sampled_a), random_state=42)
    t_stat, p_value = stats.ttest_ind(
        sampled_a["latency_ms"], sampled_b["latency_ms"], equal_var=False
    )
    return {
        "correlation_A": float(corr_a),
        "correlation_B": float(corr_b),
        "t_statistic": float(t_stat),
        "p_value": float(p_value),
    }


def assert_generated_metrics(expected):
    actual = load_metrics()
    assert set(actual) == set(expected)
    for key, wanted in expected.items():
        assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool), \
            f"{key} must be a JSON number"
        assert math.isfinite(actual[key]), f"{key} must be finite"
        assert math.isclose(actual[key], wanted, rel_tol=1e-10, abs_tol=1e-10), \
            f"{key} is incorrect: expected {wanted}, got {actual[key]}"


def test_script_on_derived_inputs_and_reproducibility():
    with open(CSV_A, "rb") as f:
        original_a = f.read()
    with open(CSV_B, "rb") as f:
        original_b = f.read()

    rng = np.random.default_rng(7319)
    cases = []

    input_a = np.arange(30, 30 + 17 * 13, 13)
    input_b = np.arange(15, 15 + 29 * 9, 9)
    cases.append((
        pd.DataFrame({"input_size": input_a, "latency_ms": 8.0 + 0.031 * input_a + rng.normal(0, 1.7, len(input_a))}),
        pd.DataFrame({"input_size": input_b, "latency_ms": 3.0 + 0.011 * input_b + rng.normal(0, 3.8, len(input_b))}),
    ))

    input_a = np.arange(20, 20 + 31 * 7, 7)
    input_b = np.arange(40, 40 + 14 * 15, 15)
    cases.append((
        pd.DataFrame({"input_size": input_a, "latency_ms": 2.0 + 0.052 * input_a + rng.normal(0, 4.2, len(input_a))}),
        pd.DataFrame({"input_size": input_b, "latency_ms": 10.0 + 0.018 * input_b + rng.normal(0, 1.1, len(input_b))}),
    ))

    try:
        for a, b in cases:
            a.to_csv(CSV_A, index=False)
            b.to_csv(CSV_B, index=False)
            expected = expected_for(a, b)

            run_analysis()
            assert_generated_metrics(expected)
            first = load_metrics()

            run_analysis()
            assert_generated_metrics(expected)
            assert load_metrics() == first, "Repeated runs on identical inputs must be reproducible"
    finally:
        with open(CSV_A, "wb") as f:
            f.write(original_a)
        with open(CSV_B, "wb") as f:
            f.write(original_b)
        subprocess.run(["python3", ANALYZE], cwd="/home/user", timeout=20)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
