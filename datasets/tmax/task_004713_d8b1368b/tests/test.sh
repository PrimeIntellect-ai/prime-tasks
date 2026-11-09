#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import subprocess
import pytest

def test_fast_audit_exists():
    path = "/home/user/fast_audit"
    assert os.path.isfile(path), f"Missing executable: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"

def test_fast_audit_correctness_and_speedup():
    c_bin = "/home/user/fast_audit"
    py_script = "/tests/hidden_ref_score.py"

    assert os.path.isfile(c_bin), f"C binary not found at {c_bin}"
    assert os.path.isfile(py_script), f"Reference python script not found at {py_script}"

    # Run C program
    start_c = time.perf_counter()
    res_c = subprocess.run([c_bin], capture_output=True, text=True)
    time_c = time.perf_counter() - start_c

    assert res_c.returncode == 0, f"C program failed with return code {res_c.returncode}\nStderr: {res_c.stderr}"
    try:
        score_c = int(res_c.stdout.strip())
    except ValueError:
        pytest.fail(f"C program did not output a valid integer. Output: {res_c.stdout.strip()}")

    # Run Reference Python
    start_py = time.perf_counter()
    res_py = subprocess.run(["python3", py_script], capture_output=True, text=True)
    time_py = time.perf_counter() - start_py

    assert res_py.returncode == 0, f"Reference Python script failed with return code {res_py.returncode}\nStderr: {res_py.stderr}"
    try:
        score_py = int(res_py.stdout.strip())
    except ValueError:
        pytest.fail(f"Reference Python script did not output a valid integer. Output: {res_py.stdout.strip()}")

    # Check correctness
    assert score_c == score_py, f"Correctness failed: Expected {score_py}, got {score_c}"

    # Check speedup
    speedup = time_py / time_c
    assert speedup >= 10.0, f"Speedup failed: {speedup:.2f}x (Threshold is 10.0x)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
