#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_predict_script_exists():
    path = "/home/user/predict.py"
    assert os.path.exists(path), f"Missing file: {path}"
    assert os.path.isfile(path), f"Not a file: {path}"

def test_fuzz_equivalence():
    agent_script = "/home/user/predict.py"
    oracle_bin = "/tests/oracle_predict"

    assert os.path.exists(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.exists(oracle_bin), f"Oracle binary missing: {oracle_bin}"

    random.seed(42)
    inputs = [random.uniform(-100.0, 100.0) for _ in range(1000)]

    for x in inputs:
        x_str = f"{x:.6f}"

        # Run oracle
        try:
            oracle_result = subprocess.run(
                [oracle_bin, x_str],
                capture_output=True,
                text=True,
                check=True,
                timeout=2
            )
            oracle_output = oracle_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {x_str}. Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {x_str}.")

        # Run agent
        try:
            agent_result = subprocess.run(
                ["python3", agent_script, x_str],
                capture_output=True,
                text=True,
                check=True,
                timeout=2
            )
            agent_output = agent_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input {x_str}. Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {x_str}.")

        assert agent_output == oracle_output, (
            f"Output mismatch on input {x_str}!\n"
            f"Expected (Oracle): '{oracle_output}'\n"
            f"Got (Agent): '{agent_output}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
