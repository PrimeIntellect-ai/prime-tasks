#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def parse_logs(file_path):
    tps_list = []
    with open(file_path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            # Example line:
            # [2023-10-24 10:00:00] INFO: Inference complete. Model: A, Input ID: 0, Latency: 123.45ms, Output: word word word
            latency_part = line.split("Latency: ")[1].split("ms")[0]
            output_part = line.split("Output: ")[1].strip()

            latency = float(latency_part)
            tokens = len(output_part.split())
            tps = tokens / (latency / 1000.0)
            tps_list.append(tps)
    return tps_list

def test_benchmark_results():
    results_path = '/home/user/benchmark_results.json'
    assert os.path.exists(results_path), f"File {results_path} does not exist."

    with open(results_path, 'r') as f:
        try:
            res = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    expected_keys = {
        "model_A_mean_tps",
        "model_B_mean_tps",
        "t_statistic",
        "p_value",
        "mean_diff_ci_lower",
        "mean_diff_ci_upper"
    }
    assert set(res.keys()) == expected_keys, f"JSON keys do not match expected keys. Got: {list(res.keys())}"

    a_tps = parse_logs('/home/user/experiment_logs/model_A.log')
    b_tps = parse_logs('/home/user/experiment_logs/model_B.log')

    n_a = len(a_tps)
    n_b = len(b_tps)

    mean_a = sum(a_tps) / n_a
    mean_b = sum(b_tps) / n_b

    var_a = sum((x - mean_a) ** 2 for x in a_tps) / (n_a - 1)
    var_b = sum((x - mean_b) ** 2 for x in b_tps) / (n_b - 1)

    df = n_a + n_b - 2
    pooled_var = ((n_a - 1) * var_a + (n_b - 1) * var_b) / df
    se = math.sqrt(pooled_var * (1 / n_a + 1 / n_b))

    t_stat = (mean_b - mean_a) / se

    # For df=198, the 97.5th percentile of the t-distribution is approx 1.972017
    t_crit = 1.9720174778338955
    margin = t_crit * se
    diff = mean_b - mean_a
    ci_lower = diff - margin
    ci_upper = diff + margin

    # The true difference is large (~5 TPS) relative to SE, so p-value is practically 0
    # We will accept anything close to 0
    expected_p_value = 0.0

    assert abs(res["model_A_mean_tps"] - round(mean_a, 4)) <= 0.0002, "model_A_mean_tps is incorrect."
    assert abs(res["model_B_mean_tps"] - round(mean_b, 4)) <= 0.0002, "model_B_mean_tps is incorrect."
    assert abs(res["t_statistic"] - round(t_stat, 4)) <= 0.0002, "t_statistic is incorrect."
    assert abs(res["p_value"] - round(expected_p_value, 4)) <= 0.0002, "p_value is incorrect."
    assert abs(res["mean_diff_ci_lower"] - round(ci_lower, 4)) <= 0.0002, "mean_diff_ci_lower is incorrect."
    assert abs(res["mean_diff_ci_upper"] - round(ci_upper, 4)) <= 0.0002, "mean_diff_ci_upper is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
