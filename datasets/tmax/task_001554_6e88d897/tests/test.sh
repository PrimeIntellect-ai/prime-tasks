#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_script_exists_and_executable():
    script_path = "/home/user/process_seq.sh"
    assert os.path.isfile(script_path), f"Agent script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Agent script is not executable: {script_path}"

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_filter.py"
    agent_script = "/home/user/process_seq.sh"

    assert os.path.isfile(oracle_path), f"Oracle script missing: {oracle_path}"

    random.seed(42)
    charset = "ACGTN"
    N = 200
    fuzz_inputs = [
        "".join(random.choice(charset) for _ in range(random.randint(5, 100)))
        for _ in range(N)
    ]

    # Compute all expected results before running the agent artifact, then remove
    # the verification-only oracle so the submitted script cannot delegate to it.
    expected_outputs = []
    for fuzz_input in fuzz_inputs:
        oracle_cmd = ["python3", oracle_path, fuzz_input]
        oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_result.returncode == 0, f"Oracle failed on input {fuzz_input}"
        expected_outputs.append(oracle_result.stdout.strip())

    os.unlink(oracle_path)

    for fuzz_input, oracle_output in zip(fuzz_inputs, expected_outputs):
        agent_cmd = ["bash", agent_script, fuzz_input]
        agent_result = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_result.returncode == 0, f"Agent script failed on input {fuzz_input}. Stderr: {agent_result.stderr}"
        agent_output = agent_result.stdout.strip()

        assert agent_output == oracle_output, (
            f"Mismatch on input: {fuzz_input}\n"
            f"Expected (Oracle): '{oracle_output}'\n"
            f"Actual (Agent): '{agent_output}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
