#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_artifact_stats_json():
    raw_file_path = "/home/user/raw_experiments.txt"
    json_file_path = "/home/user/artifact_stats.json"

    assert os.path.exists(raw_file_path), f"Raw file missing: {raw_file_path}"
    assert os.path.exists(json_file_path), f"Output JSON missing: {json_file_path}"

    # Recompute ground truth from the raw file
    successes = 0
    failures = 0
    with open(raw_file_path, "r") as f:
        for line in f:
            if "dropout_0.5" in line:
                if "status: Success" in line:
                    successes += 1
                elif "status: Failure" in line:
                    failures += 1

    prior_alpha = 1
    prior_beta = 1
    expected_posterior_alpha = prior_alpha + successes
    expected_posterior_beta = prior_beta + failures
    expected_posterior_mean = expected_posterior_alpha / (expected_posterior_alpha + expected_posterior_beta)

    with open(json_file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_file_path} is not valid JSON.")

    expected_keys = {"prior_alpha", "prior_beta", "posterior_alpha", "posterior_beta", "posterior_mean"}
    assert set(data.keys()) == expected_keys, f"JSON keys do not match expected. Found: {list(data.keys())}"

    assert data["prior_alpha"] == prior_alpha, f"Expected prior_alpha {prior_alpha}, got {data['prior_alpha']}"
    assert data["prior_beta"] == prior_beta, f"Expected prior_beta {prior_beta}, got {data['prior_beta']}"
    assert data["posterior_alpha"] == expected_posterior_alpha, f"Expected posterior_alpha {expected_posterior_alpha}, got {data['posterior_alpha']}"
    assert data["posterior_beta"] == expected_posterior_beta, f"Expected posterior_beta {expected_posterior_beta}, got {data['posterior_beta']}"
    assert abs(data["posterior_mean"] - expected_posterior_mean) < 1e-6, f"Expected posterior_mean {expected_posterior_mean}, got {data['posterior_mean']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
