#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_executable_exists():
    agent_executable = '/home/user/query_engine'
    assert os.path.isfile(agent_executable), f"The executable {agent_executable} does not exist. Did you compile your C++ program to the correct path?"
    assert os.access(agent_executable, os.X_OK), f"The file {agent_executable} is not executable."

def test_fuzz_equivalence():
    agent_executable = '/home/user/query_engine'
    oracle_executable = '/tests/oracle_query_engine'

    assert os.path.isfile(oracle_executable), f"Oracle executable missing at {oracle_executable}"
    assert os.access(oracle_executable, os.X_OK), f"Oracle executable is not executable at {oracle_executable}"

    regions = ["North", "South", "East", "West", "InvalidRegion"]
    categories = ["Electronics", "Books", "Clothing", "Toys", "InvalidCategory"]

    random.seed(42)

    for i in range(20):
        region = random.choice(regions)
        category = random.choice(categories)

        try:
            oracle_result = subprocess.run(
                [oracle_executable, region, category],
                capture_output=True,
                text=True,
                timeout=5
            )
            oracle_stdout = oracle_result.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on inputs: region='{region}', category='{category}'")

        try:
            agent_result = subprocess.run(
                [agent_executable, region, category],
                capture_output=True,
                text=True,
                timeout=5
            )
            agent_stdout = agent_result.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Your program timed out on inputs: region='{region}', category='{category}'")

        assert agent_result.returncode == oracle_result.returncode, (
            f"Return code mismatch for inputs: region='{region}', category='{category}'. "
            f"Expected {oracle_result.returncode}, got {agent_result.returncode}."
        )

        assert agent_stdout == oracle_stdout, (
            f"Output mismatch for inputs: region='{region}', category='{category}'.\n"
            f"Expected Output:\n{oracle_stdout}\n"
            f"Your Output:\n{agent_stdout}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
