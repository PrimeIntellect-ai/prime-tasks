#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_package_installed():
    try:
        import seqmotif
    except ImportError as e:
        pytest.fail(f"Failed to import 'seqmotif'. The package was not installed correctly. Error: {e}")

def test_fuzz_equivalence():
    agent_script = "/home/user/analyze_motif.py"
    oracle_script = "/tests/analyze_motif_oracle.py"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)
    bases = ['A', 'C', 'G', 'T']

    for i in range(50):
        length = random.randint(20, 100)
        seq = "".join(random.choices(bases, k=length))

        agent_cmd = ["python3", agent_script, seq]
        oracle_cmd = ["python3", oracle_script, seq]

        try:
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, check=True)
            agent_out = agent_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input {seq}\nStderr: {e.stderr}")

        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, check=True)
            oracle_out = oracle_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle script failed on input {seq}\nStderr: {e.stderr}")

        assert agent_out == oracle_out, (
            f"Output mismatch on input {seq}\n"
            f"Expected (Oracle):\n{oracle_out}\n"
            f"Got (Agent):\n{agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
