#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest
import sys

def test_fast_mcmc_utils_installed():
    """Verify that the fast_mcmc_utils package is installed and importable."""
    try:
        import fast_mcmc_utils
        # Test the function to ensure it works
        result = fast_mcmc_utils.init_chain(1.0)
        assert isinstance(result, float), "init_chain should return a float"
    except ImportError as e:
        pytest.fail(f"Failed to import fast_mcmc_utils. The package was not installed correctly. Error: {e}")
    except Exception as e:
        pytest.fail(f"fast_mcmc_utils is installed but raised an error when called: {e}")

def test_agent_script_exists_and_executable():
    """Verify that the agent script exists and is executable."""
    script_path = '/home/user/generate_features.py'
    assert os.path.isfile(script_path), f"Agent script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Agent script {script_path} is not executable."

def test_fuzz_equivalence():
    """Fuzz test the agent script against the oracle."""
    oracle_path = '/tests/generate_features_oracle.py'
    agent_path = '/home/user/generate_features.py'

    assert os.path.isfile(oracle_path), f"Oracle script {oracle_path} does not exist."
    assert os.path.isfile(agent_path), f"Agent script {agent_path} does not exist."

    random.seed(42)
    N = 200
    inputs = [random.uniform(-150.0, 150.0) for _ in range(N)]

    for x in inputs:
        x_str = str(x)

        # Run Oracle
        oracle_cmd = [sys.executable, oracle_path, x_str]
        oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_result.returncode == 0, f"Oracle failed on input {x_str}:\n{oracle_result.stderr}"
        oracle_output = oracle_result.stdout.strip()

        # Run Agent
        agent_cmd = [sys.executable, agent_path, x_str]
        agent_result = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_result.returncode == 0, f"Agent script failed on input {x_str}:\n{agent_result.stderr}"
        agent_output = agent_result.stdout.strip()

        # Compare
        assert agent_output == oracle_output, (
            f"Output mismatch for input x={x_str}.\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
