#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import pytest

RAW_DATA_PATH = '/home/user/raw_data.bin'
C_SOURCE_PATH = '/home/user/etl_clean.c'
EXECUTABLE_PATH = '/home/user/etl_clean'
GLOBAL_MEAN_PATH = '/home/user/global_mean.txt'
CLEANED_DATA_PATH = '/home/user/cleaned_data.bin'

def test_c_source_exists():
    assert os.path.exists(C_SOURCE_PATH), f"C source file {C_SOURCE_PATH} is missing."
    assert os.path.isfile(C_SOURCE_PATH), f"{C_SOURCE_PATH} is not a file."

def test_executable_exists():
    assert os.path.exists(EXECUTABLE_PATH), f"Executable {EXECUTABLE_PATH} is missing."
    assert os.path.isfile(EXECUTABLE_PATH), f"{EXECUTABLE_PATH} is not a file."
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"{EXECUTABLE_PATH} is not executable."

def test_global_mean_correct():
    assert os.path.exists(RAW_DATA_PATH), f"Input file {RAW_DATA_PATH} is missing."
    assert os.path.exists(GLOBAL_MEAN_PATH), f"Output file {GLOBAL_MEAN_PATH} is missing."

    with open(RAW_DATA_PATH, 'rb') as f:
        data = f.read()

    num_floats = len(data) // 4
    assert num_floats == 4000, f"Expected 4000 floats in {RAW_DATA_PATH}, found {num_floats}."

    floats = struct.unpack(f'<{num_floats}f', data)
    expected_global_mean = sum(floats) / len(floats)

    with open(GLOBAL_MEAN_PATH, 'r') as f:
        actual_mean_str = f.read()

    assert actual_mean_str.endswith('\n'), f"{GLOBAL_MEAN_PATH} must end with a newline."

    try:
        actual_mean = float(actual_mean_str.strip())
    except ValueError:
        pytest.fail(f"Could not parse float from {GLOBAL_MEAN_PATH}: {actual_mean_str}")

    expected_mean_str = f"{expected_global_mean:.4f}"
    assert actual_mean_str.strip() == expected_mean_str, f"Expected global mean {expected_mean_str}, got {actual_mean_str.strip()}"

def test_cleaned_data_correct():
    assert os.path.exists(RAW_DATA_PATH), f"Input file {RAW_DATA_PATH} is missing."
    assert os.path.exists(CLEANED_DATA_PATH), f"Output file {CLEANED_DATA_PATH} is missing."

    with open(RAW_DATA_PATH, 'rb') as f:
        raw_bytes = f.read()

    num_floats = len(raw_bytes) // 4
    floats = struct.unpack(f'<{num_floats}f', raw_bytes)

    expected_cleaned = []
    for i in range(0, num_floats, 4):
        vec = floats[i:i+4]
        v_mean = sum(vec) / 4.0
        expected_cleaned.extend([x - v_mean for x in vec])

    with open(CLEANED_DATA_PATH, 'rb') as f:
        cleaned_bytes = f.read()

    assert len(cleaned_bytes) == len(raw_bytes), f"Expected {CLEANED_DATA_PATH} to be exactly {len(raw_bytes)} bytes, got {len(cleaned_bytes)} bytes."

    actual_cleaned = struct.unpack(f'<{num_floats}f', cleaned_bytes)

    for i, (expected, actual) in enumerate(zip(expected_cleaned, actual_cleaned)):
        assert abs(expected - actual) < 1e-4, f"Mismatch at float index {i}: expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
