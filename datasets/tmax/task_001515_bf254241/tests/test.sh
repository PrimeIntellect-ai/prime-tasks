#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import random
import subprocess
import pytest


def test_transform_script_exists():
    """Verify that the user created the transform.py script."""
    user_script = "/home/user/transform.py"
    assert os.path.exists(user_script), f"User script not found at {user_script}"
    assert os.path.isfile(user_script), f"Path {user_script} is not a file"


def test_fuzz_equivalence():
    """Fuzz the user's script against the oracle script to ensure bit-exact equivalence."""
    user_script = "/home/user/transform.py"
    oracle_script = "/tests/oracle_transform.py"

    assert os.path.exists(oracle_script), f"Oracle script missing at {oracle_script}"

    # Use fresh cases on every verification to prevent hardcoded-output solutions.
    rng = random.SystemRandom()
    N = 100
    cases = [
        [
            str(rng.uniform(-1000.0, 1000.0)),
            str(rng.uniform(-1000.0, 1000.0)),
            str(rng.uniform(-1000.0, 1000.0)),
        ]
        for _ in range(N)
    ]

    expected_outputs = []
    for args in cases:
        oracle_cmd = [sys.executable, oracle_script] + args
        try:
            oracle_res = subprocess.run(
                oracle_cmd, capture_output=True, text=True, check=True, timeout=5
            )
            expected_outputs.append(oracle_res.stdout.strip())
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {args}. Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {args}.")

    # The submitted program must implement the transform, not delegate to the oracle.
    os.unlink(oracle_script)

    for i, (args, oracle_out) in enumerate(zip(cases, expected_outputs)):
        user_cmd = [sys.executable, user_script] + args
        try:
            user_res = subprocess.run(
                user_cmd, capture_output=True, text=True, check=True, timeout=5
            )
            user_out = user_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"User script failed on input {args}. Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"User script timed out on input {args}.")

        assert user_out == oracle_out, (
            f"Mismatch on iteration {i+1}/{N}.\n"
            f"Input: {args}\n"
            f"Expected (Oracle): '{oracle_out}'\n"
            f"Actual (User): '{user_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
