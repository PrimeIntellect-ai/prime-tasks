#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def get_expected_results():
    log_path = "/home/user/app_profile.log"
    assert os.path.exists(log_path), f"Log file {log_path} is missing."

    latencies = []
    with open(log_path, "r") as f:
        for line in f:
            if "Latency:" in line:
                parts = line.split("Latency:")[1].strip()
                val = float(parts.split(" ")[0])
                latencies.append(val)

    N = len(latencies)
    assert N > 0, "No latencies found in the log file."

    overall_mean = sum(latencies) / N
    overall_lambda = round(1.0 / overall_mean, 4)

    convergence_k = None
    for k in range(50, N + 1, 50):
        all_stable = True
        for j in range(k, N + 1, 50):
            mean_j = sum(latencies[:j]) / j
            if abs(mean_j - overall_mean) > 0.01 * overall_mean:
                all_stable = False
                break
        if all_stable:
            convergence_k = k
            break

    return {
        "total_samples": N,
        "overall_lambda": overall_lambda,
        "convergence_k": convergence_k
    }

def test_profiling_results_exists():
    result_path = "/home/user/profiling_results.json"
    assert os.path.exists(result_path), f"The file {result_path} does not exist."
    assert os.path.isfile(result_path), f"The path {result_path} is not a file."

def test_profiling_results_content():
    result_path = "/home/user/profiling_results.json"
    assert os.path.exists(result_path), f"The file {result_path} does not exist."

    with open(result_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {result_path} does not contain valid JSON.")

    expected = get_expected_results()

    assert "total_samples" in results, "Key 'total_samples' is missing from the JSON file."
    assert "overall_lambda" in results, "Key 'overall_lambda' is missing from the JSON file."
    assert "convergence_k" in results, "Key 'convergence_k' is missing from the JSON file."

    assert results["total_samples"] == expected["total_samples"], \
        f"Expected total_samples to be {expected['total_samples']}, but got {results['total_samples']}."

    assert results["overall_lambda"] == expected["overall_lambda"], \
        f"Expected overall_lambda to be {expected['overall_lambda']}, but got {results['overall_lambda']}."

    assert results["convergence_k"] == expected["convergence_k"], \
        f"Expected convergence_k to be {expected['convergence_k']}, but got {results['convergence_k']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
