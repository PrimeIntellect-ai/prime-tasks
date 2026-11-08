#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import random
import pytest

CSV_PATH = "/home/user/processed_artifacts.csv"
ARTIFACTS_DIR = "/home/user/artifacts"

def compute_metrics(latencies, successes, total_trials):
    # Posterior Probability: Beta-Binomial conjugate, Prior Beta(2, 10)
    # Posterior mean = (successes + alpha) / (total_trials + alpha + beta)
    alpha = 2
    beta_prior = 10
    posterior_prob = (successes + alpha) / (total_trials + alpha + beta_prior)

    # Mean Latency
    n = len(latencies)
    mean_latency = sum(latencies) / n

    # Bootstrap CI
    random.seed(42)
    means = []
    for _ in range(10000):
        sample = random.choices(latencies, k=n)
        means.append(sum(sample) / n)

    means.sort()
    # 2.5th and 97.5th percentiles
    ci_lower = means[int(0.025 * 10000)]
    ci_upper = means[int(0.975 * 10000)]

    return posterior_prob, mean_latency, ci_lower, ci_upper

@pytest.fixture
def expected_data():
    data = {}
    for filename in os.listdir(ARTIFACTS_DIR):
        if filename.endswith(".json"):
            filepath = os.path.join(ARTIFACTS_DIR, filename)
            with open(filepath, 'r') as f:
                content = json.load(f)
                exp_id = content["experiment_id"]
                latencies = content["latencies"]
                successes = content["successes"]
                total_trials = content["total_trials"]

                post, mean_lat, ci_l, ci_u = compute_metrics(latencies, successes, total_trials)
                data[exp_id] = {
                    "posterior_prob": post,
                    "mean_latency": mean_lat,
                    "ci_lower": ci_l,
                    "ci_upper": ci_u
                }
    return data

def test_csv_exists():
    assert os.path.isfile(CSV_PATH), f"The output file {CSV_PATH} does not exist."

def test_csv_format_and_values(expected_data):
    with open(CSV_PATH, 'r') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("CSV file is empty.")

        expected_header = ['experiment_id', 'posterior_prob', 'mean_latency', 'ci_lower', 'ci_upper']
        assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}"

        rows = list(reader)

        # Check number of rows
        assert len(rows) == len(expected_data), f"Expected {len(expected_data)} rows, got {len(rows)}."

        # Check sorting
        exp_ids = [row[0] for row in rows]
        assert exp_ids == sorted(exp_ids), "CSV rows are not sorted alphabetically by experiment_id."

        for row in rows:
            exp_id = row[0]
            assert exp_id in expected_data, f"Unexpected experiment_id {exp_id} in CSV."

            try:
                post = float(row[1])
                mean_lat = float(row[2])
                ci_l = float(row[3])
                ci_u = float(row[4])
            except ValueError:
                pytest.fail(f"Non-numeric values found in row for {exp_id}.")

            expected = expected_data[exp_id]

            assert abs(post - expected["posterior_prob"]) <= 0.0005, \
                f"Posterior probability for {exp_id} is incorrect. Expected ~{expected['posterior_prob']:.4f}, got {post}"

            assert abs(mean_lat - expected["mean_latency"]) <= 0.0005, \
                f"Mean latency for {exp_id} is incorrect. Expected ~{expected['mean_latency']:.4f}, got {mean_lat}"

            # Tolerance for bootstrap CI bounds is higher due to randomness and potential difference between numpy and random
            assert abs(ci_l - expected["ci_lower"]) <= 0.15, \
                f"CI lower bound for {exp_id} is out of acceptable tolerance. Expected ~{expected['ci_lower']:.4f}, got {ci_l}"

            assert abs(ci_u - expected["ci_upper"]) <= 0.15, \
                f"CI upper bound for {exp_id} is out of acceptable tolerance. Expected ~{expected['ci_upper']:.4f}, got {ci_u}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
