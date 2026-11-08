#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest
from itertools import combinations

EXPERIMENTS_DIR = "/home/user/experiments"
REPORT_DIR = "/home/user/report"
REQUIRED_KEYS = {
    "experiment_id",
    "learning_rate",
    "batch_size",
    "schema_hash",
    "model_weights_hash",
    "accuracy"
}

def get_experiments():
    experiments = {}
    if not os.path.exists(EXPERIMENTS_DIR):
        return experiments

    for filename in os.listdir(EXPERIMENTS_DIR):
        if filename.endswith(".json"):
            filepath = os.path.join(EXPERIMENTS_DIR, filename)
            try:
                with open(filepath, "r") as f:
                    data = json.load(f)
                    experiments[filename] = data
            except (json.JSONDecodeError, IOError):
                pass
    return experiments

def test_invalid_log():
    invalid_log_path = os.path.join(REPORT_DIR, "invalid.log")
    assert os.path.isfile(invalid_log_path), f"Expected file {invalid_log_path} is missing."

    experiments = get_experiments()
    expected_invalid = []

    for filename, data in experiments.items():
        if filename == "exp_ref.json":
            continue
        if not REQUIRED_KEYS.issubset(data.keys()):
            expected_invalid.append(filename)

    expected_invalid.sort()

    with open(invalid_log_path, "r") as f:
        actual_invalid = [line.strip() for line in f if line.strip()]

    assert actual_invalid == expected_invalid, (
        f"Contents of {invalid_log_path} do not match expected invalid files.\n"
        f"Expected: {expected_invalid}\nActual: {actual_invalid}"
    )

def test_closest_log():
    closest_log_path = os.path.join(REPORT_DIR, "closest.log")
    assert os.path.isfile(closest_log_path), f"Expected file {closest_log_path} is missing."

    experiments = get_experiments()
    ref_data = experiments.get("exp_ref.json")
    assert ref_data is not None, "exp_ref.json is missing from experiments directory."

    ref_lr = ref_data.get("learning_rate")
    ref_bs = ref_data.get("batch_size")

    min_dist = float('inf')
    closest_file = None

    for filename, data in experiments.items():
        if filename == "exp_ref.json":
            continue
        if REQUIRED_KEYS.issubset(data.keys()):
            lr = data.get("learning_rate")
            bs = data.get("batch_size")
            if lr is not None and bs is not None:
                dist = math.sqrt((lr - ref_lr)**2 + (bs - ref_bs)**2)
                if dist < min_dist:
                    min_dist = dist
                    closest_file = filename

    with open(closest_log_path, "r") as f:
        actual_closest = f.read().strip()

    assert actual_closest == closest_file, (
        f"Contents of {closest_log_path} do not match expected closest file.\n"
        f"Expected: '{closest_file}'\nActual: '{actual_closest}'"
    )

def test_violations_log():
    violations_log_path = os.path.join(REPORT_DIR, "violations.log")
    assert os.path.isfile(violations_log_path), f"Expected file {violations_log_path} is missing."

    experiments = get_experiments()
    valid_exps = {}

    for filename, data in experiments.items():
        if filename == "exp_ref.json":
            continue
        if REQUIRED_KEYS.issubset(data.keys()):
            valid_exps[filename] = data

    expected_violations = []
    for (f1, d1), (f2, d2) in combinations(sorted(valid_exps.items()), 2):
        if (d1.get("learning_rate") == d2.get("learning_rate") and
            d1.get("batch_size") == d2.get("batch_size") and
            d1.get("schema_hash") == d2.get("schema_hash") and
            d1.get("model_weights_hash") != d2.get("model_weights_hash")):
            pair = sorted([f1, f2])
            expected_violations.append(f"{pair[0]},{pair[1]}")

    expected_violations.sort()

    with open(violations_log_path, "r") as f:
        actual_violations = [line.strip() for line in f if line.strip()]

    assert actual_violations == expected_violations, (
        f"Contents of {violations_log_path} do not match expected violations.\n"
        f"Expected: {expected_violations}\nActual: {actual_violations}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
