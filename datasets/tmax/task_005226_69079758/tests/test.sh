#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_fuzz_equivalence():
    agent_file = "/home/user/backup_route.go"
    oracle_bin = "/tests/oracle_bin"

    assert os.path.isfile(agent_file), f"Agent program not found at {agent_file}"
    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"

    nodes = ["NodeA", "NodeB", "NodeC", "NodeD", "NodeE", "MASTER"]

    # Obtain all expected outputs before executing any submitted code, then
    # remove the oracle so the submitted program cannot invoke it.
    expected = {}
    for node in nodes:
        try:
            oracle_result = subprocess.run(
                [oracle_bin, node],
                capture_output=True,
                text=True,
                check=True,
                timeout=5
            )
            expected[node] = oracle_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input '{node}': {e.stderr}")

    os.remove(oracle_bin)

    random.seed(42)

    for i in range(50):
        node = random.choice(nodes)
        oracle_output = expected[node]

        try:
            agent_result = subprocess.run(
                ["go", "run", agent_file, node],
                capture_output=True,
                text=True,
                check=True,
                timeout=10
            )
            agent_output = agent_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program failed on input '{node}'.\nStderr: {e.stderr}")

        assert agent_output == oracle_output, (
            f"Output mismatch on input '{node}'\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
