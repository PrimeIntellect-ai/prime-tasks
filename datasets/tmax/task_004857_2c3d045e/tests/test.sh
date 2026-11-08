#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import numpy as np
import time
import tempfile
import pytest


def generate_test_case(filename, n):
    """Generate a random molecular network test case."""
    masses = np.random.uniform(1.0, 100.0, n)
    A = np.random.uniform(0.0, 10.0, (n, n))
    A = (A + A.T) / 2
    np.fill_diagonal(A, 0.0)
    mask = np.random.rand(n, n) > 0.5
    mask = np.logical_or(mask, mask.T)
    A[mask] = 0.0

    with open(filename, 'w') as f:
        f.write(f"{n}\n")
        f.write(" ".join(map(str, masses)) + "\n")
        for row in A:
            f.write(" ".join(map(str, row)) + "\n")


def test_fast_sim_correctness_and_speed():
    script_path = "/home/user/fast_sim.py"
    binary_path = "/app/spectro_sim"

    assert os.path.exists(script_path), f"Script not found at {script_path}"
    assert os.path.exists(binary_path), f"Oracle binary not found at {binary_path}"

    num_tests = 50
    np.random.seed(42)

    total_time_bin = 0.0
    total_time_py = 0.0
    max_error = 0.0

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(num_tests):
            n = np.random.randint(10, 101)
            test_file = os.path.join(tmpdir, f"test_{i}.txt")
            generate_test_case(test_file, n)

            start_bin = time.time()
            res_bin = subprocess.run([binary_path, test_file], capture_output=True, text=True)
            total_time_bin += time.time() - start_bin
            assert res_bin.returncode == 0, f"Oracle binary failed on test {i}:\n{res_bin.stderr}"

            start_py = time.time()
            res_py = subprocess.run(["python3", script_path, test_file], capture_output=True, text=True)
            total_time_py += time.time() - start_py
            assert res_py.returncode == 0, f"Python script failed on test {i}:\n{res_py.stderr}"

            try:
                out_bin = np.array([float(x) for x in res_bin.stdout.strip().split()])
            except ValueError:
                pytest.fail(f"Could not parse oracle output as floats on test {i}")

            try:
                out_py = np.array([float(x) for x in res_py.stdout.strip().split()])
            except ValueError:
                pytest.fail(f"Could not parse Python script output as floats on test {i}")

            assert len(out_bin) == n, f"Oracle output length mismatch on test {i}"
            assert len(out_py) == n, f"Python script output length mismatch on test {i}. Expected {n}, got {len(out_py)}"

            error = np.max(np.abs(out_bin - out_py))
            max_error = max(max_error, error)

    assert max_error <= 1e-3, f"Max absolute error {max_error} exceeds threshold 1e-3"

    speedup = total_time_bin / total_time_py if total_time_py > 0 else float('inf')
    assert speedup >= 10.0, f"Speedup {speedup:.2f}x is less than the required 10.0x (Binary: {total_time_bin:.3f}s, Script: {total_time_py:.3f}s)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
