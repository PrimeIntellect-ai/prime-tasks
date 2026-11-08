#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import struct
import subprocess
import sys
import pytest

SOLUTION_FILE = "/home/user/solution.txt"
REPO_DIR = "/home/user/suspicious_repo"
GENERATE_HASH = os.path.join(REPO_DIR, "generate_hash.py")

def to_f32(val):
    """Simulate numpy.float32 precision using standard library struct."""
    return struct.unpack('f', struct.pack('f', val))[0]

def compute_expected_truth():
    seed = 0.123456789
    x32 = to_f32(seed)
    x64 = float(seed)

    idx = -1
    for i in range(100):
        # The numpy code does: x = np.float32(3.9) * x * (np.float32(1.0) - x)
        # Note: In the original script, it's np.float32(1.0) - x.
        # When x is float32, the result of subtraction is float32.
        # Then it's multiplied by np.float32(3.9) and x.
        term1 = to_f32(3.9)
        term2 = to_f32(1.0)

        # Operations in numpy with float32 yield float32
        sub_res = to_f32(term2 - x32)
        mul1 = to_f32(term1 * x32)
        x32 = to_f32(mul1 * sub_res)

        x64 = 3.9 * x64 * (1.0 - x64)

        if abs(x32 - x64) > 0.5:
            idx = i
            break

    return seed, idx

def test_generate_hash_runs_successfully():
    assert os.path.isfile(GENERATE_HASH), f"Main script {GENERATE_HASH} does not exist."
    env = os.environ.copy()
    env["SEED"] = "0.123456789"
    result = subprocess.run(
        [sys.executable, GENERATE_HASH],
        cwd=REPO_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{GENERATE_HASH} still fails when run from its repository directory.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert "Final hash:" in result.stdout, (
        f"{GENERATE_HASH} did not produce its expected hash output. "
        f"stdout was: {result.stdout!r}"
    )

def test_solution_file_exists():
    assert os.path.isfile(SOLUTION_FILE), (
        f"Solution file {SOLUTION_FILE} does not exist."
    )

def test_solution_content():
    seed, expected_idx = compute_expected_truth()

    with open(SOLUTION_FILE, "r") as f:
        content = f.read().strip()

    expected_seed_line = f"SEED: {seed}"
    expected_idx_line = f"DIVERGENCE_INDEX: {expected_idx}"

    assert expected_seed_line in content, (
        f"Could not find the correct SEED line in {SOLUTION_FILE}. "
        f"Expected to find '{expected_seed_line}'."
    )

    assert expected_idx_line in content, (
        f"Could not find the correct DIVERGENCE_INDEX line in {SOLUTION_FILE}. "
        f"Expected to find '{expected_idx_line}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
