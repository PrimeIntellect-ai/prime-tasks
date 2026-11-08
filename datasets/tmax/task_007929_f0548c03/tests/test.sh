#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

ARTIFACTS_DIR = "/home/user/artifacts"
OUTPUT_FILE = "/home/user/valid_experiments.txt"

def is_valid_experiment(data):
    try:
        exp_id = data.get("experiment_id")
        if not isinstance(exp_id, str):
            return False

        hyperparams = data.get("hyperparameters", {})
        learning_rate = hyperparams.get("learning_rate")
        prior_alpha = hyperparams.get("prior_alpha")
        prior_beta = hyperparams.get("prior_beta")

        metrics = data.get("metrics", {})
        cv_score = metrics.get("cv_score")

        if learning_rate is None or prior_alpha is None or prior_beta is None or cv_score is None:
            return False

        if not (0.0 < learning_rate < 1.0):
            return False

        if not (prior_alpha > 0.0 and prior_beta > 0.0):
            return False

        if cv_score == 0:
            return False

        if not (0.50 <= cv_score <= 0.99):
            return False

        return True
    except Exception:
        return False

def test_valid_experiments_output():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

    expected_valid_ids = []

    for filename in os.listdir(ARTIFACTS_DIR):
        if filename.endswith(".json"):
            filepath = os.path.join(ARTIFACTS_DIR, filename)
            with open(filepath, 'r') as f:
                try:
                    data = json.load(f)
                    if is_valid_experiment(data):
                        expected_valid_ids.append(data["experiment_id"])
                except json.JSONDecodeError:
                    pass

    expected_valid_ids.sort()

    with open(OUTPUT_FILE, 'r') as f:
        actual_lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert actual_lines == expected_valid_ids, (
        f"Expected valid experiment IDs: {expected_valid_ids}, "
        f"but got: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
