#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_PATH = "/home/user/analysis_output.json"

def test_output_file_exists():
    """Verify that the analysis_output.json file was created."""
    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"

def test_output_contents():
    """Verify the contents of the analysis_output.json file."""
    assert os.path.isfile(OUTPUT_PATH), "Cannot check contents; file is missing."

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_PATH} does not contain valid JSON.")

    expected_keys = {"primer", "r", "K", "yield_integral"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in JSON output: {missing_keys}"

    # Check primer
    expected_primer = "ATGCGTACGTTAGCTAGCTA"
    assert data["primer"] == expected_primer, f"Expected primer '{expected_primer}', got '{data.get('primer')}'"

    # Check r
    try:
        r = float(data["r"])
    except (ValueError, TypeError):
        pytest.fail(f"Value for 'r' must be a number, got {data.get('r')}")
    assert abs(r - 0.450) <= 0.005, f"Expected 'r' to be ~0.450, got {r}"

    # Check K
    try:
        k = float(data["K"])
    except (ValueError, TypeError):
        pytest.fail(f"Value for 'K' must be a number, got {data.get('K')}")
    assert abs(k - 120.000) <= 0.5, f"Expected 'K' to be ~120.000, got {k}"

    # Check yield_integral
    try:
        yield_integral = float(data["yield_integral"])
    except (ValueError, TypeError):
        pytest.fail(f"Value for 'yield_integral' must be a number, got {data.get('yield_integral')}")
    assert abs(yield_integral - 2567.697) <= 1.0, f"Expected 'yield_integral' to be ~2567.697, got {yield_integral}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
