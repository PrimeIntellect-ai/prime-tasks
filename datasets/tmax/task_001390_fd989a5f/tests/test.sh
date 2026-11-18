#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

AGENT_EXECUTABLE = "/home/user/bin/storage-daemon"
DEPLOY_SCRIPT = "/home/user/deploy.sh"
ORACLE_EXECUTABLE = "/tests/storage-daemon-ref"

def test_deploy_script_exists_and_executable():
    assert os.path.exists(DEPLOY_SCRIPT), f"Deploy script {DEPLOY_SCRIPT} does not exist."
    assert os.path.isfile(DEPLOY_SCRIPT), f"{DEPLOY_SCRIPT} is not a file."
    assert os.access(DEPLOY_SCRIPT, os.X_OK), f"Deploy script {DEPLOY_SCRIPT} is not executable."

    with open(DEPLOY_SCRIPT, "r") as f:
        content = f.read()
    assert "STORAGE_ENV" in content, f"Deploy script must set STORAGE_ENV."
    assert "STAGING" in content, f"Deploy script must set STORAGE_ENV to STAGING."

def test_agent_executable_exists_and_executable():
    assert os.path.exists(AGENT_EXECUTABLE), f"Agent executable {AGENT_EXECUTABLE} does not exist."
    assert os.path.isfile(AGENT_EXECUTABLE), f"{AGENT_EXECUTABLE} is not a file."
    assert os.access(AGENT_EXECUTABLE, os.X_OK), f"Agent executable {AGENT_EXECUTABLE} is not executable."

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_EXECUTABLE), f"Oracle executable {ORACLE_EXECUTABLE} missing."

    # Generate 10000 random integers from 0 to 5000
    random.seed(42)
    inputs = [str(random.randint(0, 5000)) for _ in range(10000)]
    input_str = "\n".join(inputs) + "\n"
    input_bytes = input_str.encode("utf-8")

    # Run oracle
    oracle_proc = subprocess.run(
        [ORACLE_EXECUTABLE],
        input=input_bytes,
        capture_output=True,
        timeout=10
    )
    assert oracle_proc.returncode == 0, f"Oracle failed with return code {oracle_proc.returncode}"
    oracle_output = oracle_proc.stdout

    # Run agent
    agent_proc = subprocess.run(
        [AGENT_EXECUTABLE],
        input=input_bytes,
        capture_output=True,
        timeout=10
    )
    assert agent_proc.returncode == 0, f"Agent executable failed with return code {agent_proc.returncode}"
    agent_output = agent_proc.stdout

    if oracle_output != agent_output:
        # Find the first mismatch to provide a helpful error message
        oracle_lines = oracle_output.decode("utf-8", errors="replace").splitlines()
        agent_lines = agent_output.decode("utf-8", errors="replace").splitlines()

        for i, (in_val, o_line, a_line) in enumerate(zip(inputs, oracle_lines, agent_lines)):
            if o_line != a_line:
                pytest.fail(f"Mismatch at input {in_val} (line {i+1}). Oracle: {o_line!r}, Agent: {a_line!r}")

        # If lengths differ
        pytest.fail(f"Outputs differ in length. Oracle lines: {len(oracle_lines)}, Agent lines: {len(agent_lines)}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
