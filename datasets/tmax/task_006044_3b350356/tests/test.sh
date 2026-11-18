#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_correlations_json_exists_and_correct():
    file_path = "/home/user/correlations.json"
    assert os.path.isfile(file_path), f"File missing: {file_path}"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON")

    assert isinstance(data, dict), "correlations.json must contain a single dictionary"

    expected_data = {
        "elevation__type_encoded": 0.8252,
        "elevation__mean_temp": -0.9922,
        "elevation__mean_humidity": 0.9996,
        "elevation__mean_pm25": -0.9634,
        "mean_temp__type_encoded": -0.8860,
        "mean_humidity__type_encoded": 0.8144,
        "mean_pm25__type_encoded": -0.9254,
        "mean_humidity__mean_temp": -0.9904,
        "mean_pm25__mean_temp": 0.9880,
        "mean_humidity__mean_pm25": -0.9659
    }

    assert len(data) == 10, f"Expected exactly 10 key-value pairs, found {len(data)}"

    for key, expected_val in expected_data.items():
        assert key in data, f"Key '{key}' is missing from correlations.json"

        actual_val = data[key]
        assert isinstance(actual_val, (int, float)), f"Value for '{key}' must be a number"

        # Check if the value is correct to 4 decimal places
        assert abs(actual_val - expected_val) <= 0.0001, f"Value for '{key}' is incorrect. Expected {expected_val}, got {actual_val}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
