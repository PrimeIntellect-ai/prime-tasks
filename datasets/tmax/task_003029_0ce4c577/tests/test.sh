#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_agent_executable_exists():
    agent_exe = "/home/user/prepare_data"
    assert os.path.exists(agent_exe), f"Agent executable {agent_exe} not found."
    assert os.access(agent_exe, os.X_OK), f"Agent executable {agent_exe} is not executable."

def test_library_fixed():
    makefile_path = "/app/libsim_model-1.2.0/Makefile"
    if os.path.exists(makefile_path):
        with open(makefile_path, "r") as f:
            content = f.read()
        assert "-lm" in content, "Makefile was not fixed to include -lm."

    integrator_path = "/app/libsim_model-1.2.0/integrator.c"
    if os.path.exists(integrator_path):
        with open(integrator_path, "r") as f:
            content = f.read()
        assert "tolerance / error" in content or "tolerance/error" in content, "integrator.c step-size bug was not fixed."

def test_fuzz_equivalence():
    agent_exe = "/home/user/prepare_data"
    oracle_exe = "/tests/prepare_data_oracle"

    assert os.path.exists(oracle_exe), f"Oracle executable {oracle_exe} not found."
    assert os.path.exists(agent_exe), f"Agent executable {agent_exe} not found."

    random.seed(42)
    # Generate 200 random inputs uniformly distributed between 0.10 and 5.00, formatted to two decimal places
    inputs = [f"{random.uniform(0.1, 5.0):.2f}" for _ in range(200)]

    for x in inputs:
        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_exe, x],
            capture_output=True,
            text=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {x}: {oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            [agent_exe, x],
            capture_output=True,
            text=True,
            # We don't explicitly set LD_LIBRARY_PATH here because the agent was instructed
            # to handle library loading properly (e.g., via rpath or a wrapper script).
            env=os.environ.copy()
        )
        assert agent_proc.returncode == 0, f"Agent executable failed on input {x}.\nStderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, f"Mismatch on input {x}.\nOracle: {oracle_out}\nAgent: {agent_out}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
