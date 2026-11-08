#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_predictor_executable_exists():
    agent_executable = "/home/user/project/build/predictor"
    assert os.path.exists(agent_executable), f"Agent executable missing at {agent_executable}"
    assert os.path.isfile(agent_executable), f"{agent_executable} is not a file"
    assert os.access(agent_executable, os.X_OK), f"{agent_executable} is not executable"

def test_fuzz_equivalence():
    agent_executable = "/home/user/project/build/predictor"
    oracle_executable = "/tests/oracle_predictor"

    assert os.path.exists(oracle_executable), f"Oracle executable missing at {oracle_executable}"

    # We clear LD_LIBRARY_PATH to ensure the agent fixed the RPATH correctly
    env = os.environ.copy()
    if "LD_LIBRARY_PATH" in env:
        del env["LD_LIBRARY_PATH"]

    random.seed(42)
    test_cases = [random.randint(0, 10000) for _ in range(1000)]

    for t in test_cases:
        t_str = str(t)

        try:
            oracle_res = subprocess.run(
                [oracle_executable, t_str],
                capture_output=True,
                text=True,
                check=True,
                env=env
            )
            oracle_output = oracle_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {t_str}. Stderr: {e.stderr}")

        try:
            agent_res = subprocess.run(
                [agent_executable, t_str],
                capture_output=True,
                text=True,
                check=True,
                env=env
            )
            agent_output = agent_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent executable failed on input {t_str}. This may be due to missing shared library (RPATH not set) or a crash. Stderr: {e.stderr}")

        assert agent_output == oracle_output, (
            f"Mismatch on input t={t_str}.\n"
            f"Oracle output: '{oracle_output}'\n"
            f"Agent output:  '{agent_output}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
