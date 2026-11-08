#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess


def test_fuzz_equivalence():
    agent_path = "/home/user/project/engine"
    oracle_path = "/tests/engine"

    assert os.path.isfile(agent_path), f"Agent binary {agent_path} does not exist. Did you compile the project?"
    assert os.access(agent_path, os.X_OK), f"Agent binary {agent_path} is not executable."

    assert os.path.isfile(oracle_path), f"Oracle binary {oracle_path} does not exist."
    assert os.access(oracle_path, os.X_OK), f"Oracle binary {oracle_path} is not executable."

    with open(agent_path, "rb") as agent_file, open(oracle_path, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent binary must not be a copy of the reference oracle."

    random.seed(42)
    inputs = [random.randint(1, 1000000) for _ in range(50)]
    expected = {}

    for val in inputs:
        val_str = str(val)
        oracle_res = subprocess.run([oracle_path, val_str], capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle binary failed on input {val_str}"
        expected[val] = oracle_res.stdout.strip()

    # Do not leave the oracle available while the submitted executable runs.
    os.unlink(oracle_path)

    for val in inputs:
        val_str = str(val)
        agent_res = subprocess.run([agent_path, val_str], capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent binary failed on input {val_str} with stderr: {agent_res.stderr}"

        agent_out = agent_res.stdout.strip()
        oracle_out = expected[val]

        assert agent_out == oracle_out, (
            f"Mismatch on input {val_str}.\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}\n"
            "The constants extracted from the image might be incorrect or the build is outdated."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
