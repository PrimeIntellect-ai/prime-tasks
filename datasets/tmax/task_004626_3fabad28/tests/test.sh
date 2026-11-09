#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import tempfile
import pytest

ORACLE_PATH = "/app/graph_oracle.bin"
AGENT_PATH = "/home/user/solution"

def test_solution_exists_and_executable():
    """Check if the agent's solution binary exists and is executable."""
    assert os.path.exists(AGENT_PATH), f"Missing solution binary at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Path {AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Solution binary at {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    """Fuzz the agent's solution against the oracle to ensure equivalence."""
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary is not executable at {ORACLE_PATH}"

    random.seed(1337)

    num_tests = 100
    for i in range(num_tests):
        num_v = random.randint(10, 500)
        num_e = random.randint(20, 2000)

        edges = []
        for _ in range(num_e):
            u = random.randint(0, num_v - 1)
            v = random.randint(0, num_v - 1)
            edges.append((u, v))

        target_node = random.randint(0, num_v - 1)

        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            for u, v in edges:
                f.write(f"{u} {v}\n")
            temp_path = f.name

        try:
            oracle_cmd = [ORACLE_PATH, temp_path, str(target_node)]
            agent_cmd = [AGENT_PATH, temp_path, str(target_node)]

            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert oracle_res.returncode == 0, f"Oracle failed on test case {i+1} with target node {target_node}"
            assert agent_res.returncode == 0, f"Agent solution failed on test case {i+1} with target node {target_node}. Stderr: {agent_res.stderr}"

            oracle_out = oracle_res.stdout.strip()
            agent_out = agent_res.stdout.strip()

            assert agent_out == oracle_out, (
                f"Output mismatch on test case {i+1}:\n"
                f"Target Node: {target_node}\n"
                f"Graph: |V|={num_v}, |E|={num_e}\n"
                f"Oracle Output: '{oracle_out}'\n"
                f"Agent Output: '{agent_out}'\n"
            )
        finally:
            os.remove(temp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
