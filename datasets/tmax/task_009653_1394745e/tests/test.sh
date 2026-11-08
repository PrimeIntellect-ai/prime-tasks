#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure numerical libraries used by the verifier are constrained before Python starts.
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import re
import math
import statistics
import pytest
from scipy import stats


def test_analysis_report_exists():
    """Check if the analysis report was created."""
    assert os.path.isfile("/home/user/analysis_report.json"), "analysis_report.json is missing."


def test_analysis_report_contents():
    """Validate the contents of the analysis report."""
    assert os.environ.get("OMP_NUM_THREADS") == "1", "OMP_NUM_THREADS must be set to 1"
    assert os.environ.get("OPENBLAS_NUM_THREADS") == "1", "OPENBLAS_NUM_THREADS must be set to 1"

    report_path = "/home/user/analysis_report.json"
    assert os.path.isfile(report_path), "analysis_report.json is missing."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("analysis_report.json is not a valid JSON file.")

    expected_keys = {
        "median_latency_imputed",
        "cpu_outliers_capped",
        "vocab_size",
        "t_stat",
        "p_value",
        "ci_lower",
        "ci_upper"
    }

    missing_keys = expected_keys - set(report.keys())
    assert not missing_keys, f"Missing keys in JSON: {missing_keys}"

    # Read CSV to compute expected values.
    csv_path = "/home/user/server_logs.csv"
    assert os.path.isfile(csv_path), "server_logs.csv is missing."

    latencies = []
    cpu_usages = []
    messages = []

    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            lat_str = row["latency_ms"]
            if lat_str and lat_str.lower() != "nan":
                latencies.append(float(lat_str))
            else:
                latencies.append(None)

            cpu_usages.append(float(row["cpu_usage"]))
            messages.append(row["log_message"])

    # 1. Median Imputation
    valid_latencies = [x for x in latencies if x is not None]
    median_lat = statistics.median(valid_latencies)
    imputed_latencies = [x if x is not None else median_lat for x in latencies]

    # 2. Outliers
    mean_cpu = statistics.mean(cpu_usages)
    std_cpu = statistics.stdev(cpu_usages)
    upper = mean_cpu + 3 * std_cpu
    lower = mean_cpu - 3 * std_cpu
    cpu_outliers_capped = sum(1 for x in cpu_usages if x > upper or x < lower)

    # 3. Tokenization
    vocab = set()
    tokens_list = []
    for msg in messages:
        msg_lower = msg.lower()
        msg_clean = re.sub(r'[^a-z0-9\s]', '', msg_lower)
        tokens = msg_clean.split()
        tokens_list.append(tokens)
        vocab.update(tokens)

    vocab_size = len(vocab)

    # 4. Welch's t-test and confidence interval
    group_a = []
    group_b = []
    for tokens, lat in zip(tokens_list, imputed_latencies):
        if "timeout" in tokens:
            group_a.append(lat)
        else:
            group_b.append(lat)

    mean_a = statistics.mean(group_a)
    mean_b = statistics.mean(group_b)
    var_a = statistics.variance(group_a)
    var_b = statistics.variance(group_b)
    n_a = len(group_a)
    n_b = len(group_b)

    term_a = var_a / n_a
    term_b = var_b / n_b
    se = math.sqrt(term_a + term_b)
    t_stat = (mean_a - mean_b) / se
    welch_df = (term_a + term_b) ** 2 / (
        (term_a ** 2) / (n_a - 1) + (term_b ** 2) / (n_b - 1)
    )
    p_value = 2.0 * stats.t.sf(abs(t_stat), welch_df)
    critical = stats.t.ppf(0.975, welch_df)
    mean_difference = mean_a - mean_b
    ci_lower = mean_difference - critical * se
    ci_upper = mean_difference + critical * se

    # Preserve the original assertions.
    assert math.isclose(report["median_latency_imputed"], median_lat, abs_tol=1e-3), \
        f"Expected median_latency_imputed approx {median_lat}, got {report['median_latency_imputed']}"

    assert report["cpu_outliers_capped"] == cpu_outliers_capped, \
        f"Expected cpu_outliers_capped {cpu_outliers_capped}, got {report['cpu_outliers_capped']}"

    assert report["vocab_size"] == vocab_size, \
        f"Expected vocab_size {vocab_size}, got {report['vocab_size']}"

    assert math.isclose(report["t_stat"], t_stat, abs_tol=1e-3), \
        f"Expected t_stat approx {t_stat}, got {report['t_stat']}"

    assert isinstance(report["p_value"], (int, float)), "p_value must be a number"
    assert 0.0 <= report["p_value"] <= 1.0, "p_value must be between 0 and 1"

    assert isinstance(report["ci_lower"], (int, float)), "ci_lower must be a number"
    assert isinstance(report["ci_upper"], (int, float)), "ci_upper must be a number"
    assert report["ci_lower"] < report["ci_upper"], "ci_lower must be less than ci_upper"

    # Validate the required rounded Welch p-value and 95% confidence interval.
    expected_p = round(float(p_value), 4)
    expected_lower = round(float(ci_lower), 4)
    expected_upper = round(float(ci_upper), 4)

    assert math.isclose(report["p_value"], expected_p, rel_tol=0.0, abs_tol=5e-5), \
        f"Expected p_value {expected_p}, got {report['p_value']}"
    assert math.isclose(report["ci_lower"], expected_lower, rel_tol=0.0, abs_tol=5e-5), \
        f"Expected ci_lower {expected_lower}, got {report['ci_lower']}"
    assert math.isclose(report["ci_upper"], expected_upper, rel_tol=0.0, abs_tol=5e-5), \
        f"Expected ci_upper {expected_upper}, got {report['ci_upper']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
