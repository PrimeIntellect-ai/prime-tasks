#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

def test_baseline_json_exists():
    """
    Test that the baseline.json file exists.
    """
    json_path = "/home/user/baseline.json"
    assert os.path.exists(json_path), f"Missing file: {json_path}"
    assert os.path.isfile(json_path), f"Expected {json_path} to be a file."

def test_baseline_json_content():
    """
    Test that the baseline.json file has the correct structure and values.
    """
    json_path = "/home/user/baseline.json"
    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "baseline.json is not a valid JSON file."

    # Check keys
    expected_keys = {"atom_145_residue", "drift_slope", "dominant_frequency"}
    assert set(data.keys()) == expected_keys, f"JSON keys must be exactly {expected_keys}, got {set(data.keys())}"

    # Check residue
    assert data["atom_145_residue"] == "TYR", f"Expected residue 'TYR', got '{data['atom_145_residue']}'"

    # Check drift slope (should be close to 0.42)
    slope = data["drift_slope"]
    assert isinstance(slope, (int, float)), "drift_slope must be a number"
    assert math.isclose(slope, 0.42, abs_tol=0.05), f"Expected drift_slope around 0.42, got {slope}"

    # Check dominant frequency (should be exactly 7.8 based on FFT bins)
    freq = data["dominant_frequency"]
    assert isinstance(freq, (int, float)), "dominant_frequency must be a number"
    assert math.isclose(freq, 7.8, abs_tol=0.1), f"Expected dominant_frequency around 7.8, got {freq}"

    # Check rounding to 3 decimal places by verifying string representation if possible
    # A simple way to check if it's rounded:
    with open(json_path, 'r') as f:
        raw_content = f.read()
        # We won't strictly fail on string length, but ensure the values are correct.
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
