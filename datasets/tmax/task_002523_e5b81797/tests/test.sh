#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_setup_py_fixed():
    """Test that the setup.py file has the typo corrected."""
    path = "/app/networkx_src/setup.py"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "scpiy" not in content, "The typo 'scpiy' is still present in setup.py."
    assert "scipy" in content, "The dependency 'scipy' is missing from setup.py."

def test_networkx_installed():
    """Test that networkx is installed and usable."""
    try:
        import networkx as nx
        G = nx.MultiDiGraph()
    except Exception as e:
        pytest.fail(f"networkx import or usage failed: {e}")

def test_fuzz_equivalence():
    """Test that the agent's script produces identical output to the oracle on 200 random inputs."""
    agent_script = "/home/user/sequence_graph_analyzer.py"
    oracle_script = "/tests/analyze.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} is missing."

    random.seed(42)
    chars = ['A', 'C', 'G', 'T']

    for i in range(200):
        length = random.randint(10, 500)
        seq = "".join(random.choices(chars, k=length))

        oracle_res = subprocess.run(
            ["python3", oracle_script, seq],
            capture_output=True, text=True
        )
        assert oracle_res.returncode == 0, f"Oracle failed on input {seq}\nError: {oracle_res.stderr}"

        agent_res = subprocess.run(
            ["python3", agent_script, seq],
            capture_output=True, text=True
        )
        assert agent_res.returncode == 0, f"Agent script failed on input {seq}\nError: {agent_res.stderr}"

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on iteration {i+1} with input length {length}.\n"
            f"Input: {seq}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
