#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_PATH = "/home/user/processed_equations.json"

def test_output_file_exists():
    """Test that the processed_equations.json file exists."""
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing. Did the script run and create it?"

def test_output_is_valid_json():
    """Test that the output file contains valid JSON data."""
    assert os.path.isfile(OUTPUT_PATH), "Output file missing."
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Output file is not valid JSON: {e}")

    assert isinstance(data, list), "The JSON output must be an array of objects."

def test_deduplication_and_ids():
    """Test that the correct rows are retained after deduplication."""
    if not os.path.isfile(OUTPUT_PATH):
        pytest.skip("Output file missing.")
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)

    expected_ids = [1, 2, 4, 5, 7]
    actual_ids = [row.get('id') for row in data]

    assert actual_ids == expected_ids, f"Expected row IDs after deduplication to be {expected_ids}, but got {actual_ids}. Check CSV parsing and deduplication logic."

def test_normalization():
    """Test that the equations are correctly normalized."""
    if not os.path.isfile(OUTPUT_PATH):
        pytest.skip("Output file missing.")
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)

    expected_normalized = {
        1: "3*4+5",
        2: "12/4",
        4: "1+1",
        5: "2^3",
        7: "100/10"
    }

    for row in data:
        row_id = row.get('id')
        if row_id in expected_normalized:
            actual_norm = row.get('normalized')
            expected_norm = expected_normalized[row_id]
            assert actual_norm == expected_norm, f"For ID {row_id}, expected normalized equation '{expected_norm}', got '{actual_norm}'."

def test_hashes():
    """Test that the SHA-256 hashes are correctly computed."""
    if not os.path.isfile(OUTPUT_PATH):
        pytest.skip("Output file missing.")
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)

    expected_hashes = {
        1: "c0ad444dfb22fa600a9da30da7f7a85d321151fc70a9db519808a735e5d33682",
        2: "7cb4a2822a969b4e3321523315750800e8bc1a37c95b682b95c25605d33261a7",
        4: "f6236b283dcc028120ec2c554ce8d19bf74cc5b8cb4604d576a8d0f1eb258a01",
        5: "0a6fdd582496a8eb8caec94c73bfb588de78d387cc8bf2c7bb25dfb45cc16a5b",
        7: "52e1bc60731ff833b70ff99863cefe9cbab7eb03cd5852b0cf668a62f5596e1b"
    }

    for row in data:
        row_id = row.get('id')
        if row_id in expected_hashes:
            actual_hash = row.get('hash')
            expected_hash = expected_hashes[row_id]
            assert actual_hash == expected_hash, f"For ID {row_id}, expected hash '{expected_hash}', got '{actual_hash}'."

def test_rolling_averages():
    """Test that the rolling moving average lengths are calculated correctly."""
    if not os.path.isfile(OUTPUT_PATH):
        pytest.skip("Output file missing.")
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        data = json.load(f)

    expected_avgs = {
        1: 5.0,
        2: 4.5,
        4: 4.0,
        5: 3.33,
        7: 4.0
    }

    for row in data:
        row_id = row.get('id')
        if row_id in expected_avgs:
            actual_avg = row.get('rolling_avg_len')
            expected_avg = expected_avgs[row_id]
            assert isinstance(actual_avg, (int, float)), f"For ID {row_id}, rolling_avg_len should be a number."
            assert abs(actual_avg - expected_avg) < 0.01, f"For ID {row_id}, expected rolling average {expected_avg}, got {actual_avg}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
