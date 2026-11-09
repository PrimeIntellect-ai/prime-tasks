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

METRICS_FILE = "/home/user/experiment_metrics.json"
CSV_FILE = "/home/user/inference_logs.csv"

def test_experiment_metrics_exists():
    assert os.path.isfile(METRICS_FILE), f"The file {METRICS_FILE} does not exist."

def test_experiment_metrics_content():
    assert os.path.isfile(CSV_FILE), f"The input file {CSV_FILE} is missing."

    # Recompute expected values based on the actual CSV file
    data = {"A": [], "B": []}
    with open(CSV_FILE, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            val = row.get("latency_ms", "")
            try:
                v = float(val)
                if not math.isnan(v):
                    model = row.get("model_version")
                    if model in data:
                        data[model].append(v)
            except ValueError:
                pass

    expected = {}
    for model, values in data.items():
        n = len(values)
        if n > 1:
            mean = sum(values) / n
            variance = sum((x - mean) ** 2 for x in values) / (n - 1)
            std_dev = math.sqrt(variance)
            sem = std_dev / math.sqrt(n)
            ci_lower = mean - 1.96 * sem
            ci_upper = mean + 1.96 * sem
            expected[model] = {
                "mean": f"{mean:.2f}",
                "ci_lower": f"{ci_lower:.2f}",
                "ci_upper": f"{ci_upper:.2f}"
            }

    # Read the generated JSON
    with open(METRICS_FILE, "r") as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{METRICS_FILE} does not contain valid JSON.")

    # Assert JSON structure and values
    for model in ["A", "B"]:
        assert model in actual, f"Model '{model}' is missing from the JSON output."
        for key in ["mean", "ci_lower", "ci_upper"]:
            assert key in actual[model], f"Key '{key}' is missing from model '{model}' in JSON output."
            expected_val = expected[model][key]
            actual_val = actual[model][key]
            assert actual_val == expected_val, (
                f"Incorrect value for Model {model} '{key}'. "
                f"Expected '{expected_val}', got '{actual_val}'."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
