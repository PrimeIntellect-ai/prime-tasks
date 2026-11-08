#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import random
import pytest

ORACLE_PATH = '/app/profiler_baseline'
TARGET_PATH = '/home/user/profiler_reimpl'
NUM_ITERATIONS = 100

def test_target_exists_and_executable():
    """Check that the target Go binary exists and is executable."""
    assert os.path.exists(TARGET_PATH), f"The target binary {TARGET_PATH} does not exist."
    assert os.path.isfile(TARGET_PATH), f"{TARGET_PATH} is not a file."

    st = os.stat(TARGET_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{TARGET_PATH} is not executable."

def run_program(binary_path, input_data):
    """Run a program with the given input data and return its stdout."""
    try:
        result = subprocess.run(
            [binary_path],
            input=input_data,
            text=True,
            capture_output=True,
            check=True,
            timeout=5
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of {binary_path} failed with return code {e.returncode}.\nStderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {binary_path} timed out.")

def test_fuzz_equivalence():
    """Fuzz both the oracle and the target to ensure bit-exact equivalence."""
    random.seed(42)

    for i in range(NUM_ITERATIONS):
        n_floats = random.randint(1, 100)
        floats = [random.uniform(-1000.0, 1000.0) for _ in range(n_floats)]
        input_data = "\n".join(f"{f:.6f}" for f in floats) + "\n"

        oracle_output = run_program(ORACLE_PATH, input_data)
        target_output = run_program(TARGET_PATH, input_data)

        if oracle_output != target_output:
            # Truncate input data for display if it's too long
            display_input = input_data if len(input_data) < 200 else input_data[:200] + "...\n(truncated)"
            pytest.fail(
                f"Mismatch found on iteration {i+1}!\n"
                f"Input sequence length: {n_floats}\n"
                f"Input data:\n{display_input}\n\n"
                f"Oracle output:\n{oracle_output}\n"
                f"Target output:\n{target_output}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
