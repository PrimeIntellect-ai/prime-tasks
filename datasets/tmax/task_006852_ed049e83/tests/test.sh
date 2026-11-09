#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import math
import pytest

def test_cpp_file_exists():
    cpp_path = "/home/user/compute_cov.cpp"
    assert os.path.exists(cpp_path), f"Missing C++ source file: {cpp_path}"

def test_cov_matrix_exists_and_size():
    cov_path = "/home/user/cov_matrix.bin"
    assert os.path.exists(cov_path), f"Missing output file: {cov_path}"

    size = os.path.getsize(cov_path)
    assert size == 100, f"Expected {cov_path} to be exactly 100 bytes (25 floats), got {size} bytes."

def test_cov_matrix_correctness():
    cov_path = "/home/user/cov_matrix.bin"
    if not os.path.exists(cov_path) or os.path.getsize(cov_path) != 100:
        pytest.skip("Output file missing or incorrect size.")

    N = 100000

    # Read input data
    with open("/home/user/data_A.bin", "rb") as f:
        A_data = struct.unpack(f"{N*3}f", f.read(N*3*4))
    with open("/home/user/data_B.bin", "rb") as f:
        B_data = struct.unpack(f"{N*2}f", f.read(N*2*4))

    # Compute means
    sums = [0.0] * 5
    for i in range(N):
        sums[0] += A_data[i*3]
        sums[1] += A_data[i*3+1]
        sums[2] += A_data[i*3+2]
        sums[3] += B_data[i*2]
        sums[4] += B_data[i*2+1]

    means = [s / N for s in sums]

    # Compute covariance matrix (N-1)
    cov = [[0.0] * 5 for _ in range(5)]
    for i in range(N):
        row = [
            A_data[i*3] - means[0],
            A_data[i*3+1] - means[1],
            A_data[i*3+2] - means[2],
            B_data[i*2] - means[3],
            B_data[i*2+1] - means[4]
        ]
        for j in range(5):
            for k in range(5):
                cov[j][k] += row[j] * row[k]

    for j in range(5):
        for k in range(5):
            cov[j][k] /= (N - 1)

    # Read actual output
    with open(cov_path, "rb") as f:
        actual_data = struct.unpack("25f", f.read(100))

    # Compare expected and actual
    for j in range(5):
        for k in range(5):
            expected = cov[j][k]
            actual = actual_data[j*5 + k]
            assert math.isclose(expected, actual, rel_tol=1e-3, abs_tol=1e-4), \
                f"Covariance mismatch at row {j}, col {k}: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
