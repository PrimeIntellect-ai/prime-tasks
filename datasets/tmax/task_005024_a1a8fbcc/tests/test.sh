#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess
import random
import numpy as np
import pytest

def test_poly_basis_installed_and_working():
    """Check if poly_basis is correctly installed and functional."""
    try:
        import poly_basis
    except ImportError:
        pytest.fail("The 'poly_basis' package is not installed or cannot be imported. Did you fix setup.py and install it?")

    try:
        x = np.array([2.0], dtype=np.float64)
        res = poly_basis.expand(x, 3)
        assert len(res) == 3, f"Expected length 3, got {len(res)}"
        assert np.allclose(res, [2.0, 4.0, 8.0]), f"Expected [2.0, 4.0, 8.0], got {res}"
    except Exception as e:
        pytest.fail(f"poly_basis.expand failed to execute correctly: {e}")

def test_fuzz_equivalence():
    """Fuzz test the agent's script against the oracle implementation."""
    agent_script = "/home/user/run_model.py"
    oracle_script = "/tests/run_model_oracle"

    assert os.path.exists(agent_script), f"Agent script is missing at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script is missing at {oracle_script}"

    rng = random.Random(42)

    for i in range(50):
        num_args = rng.randint(3, 6)
        args = [str(round(rng.uniform(-5.0, 5.0), 4)) for _ in range(num_args)]

        oracle_cmd = [sys.executable, oracle_script] + args
        agent_cmd = [sys.executable, agent_script] + args

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        assert oracle_res.returncode == 0, f"Oracle failed unexpectedly on input {args}. Stderr: {oracle_res.stderr}"
        assert agent_res.returncode == 0, f"Agent script failed on input {args}.\nStderr: {agent_res.stderr}\nStdout: {agent_res.stdout}"

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Output mismatch on iteration {i+1} with input {args}.\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent):       {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
