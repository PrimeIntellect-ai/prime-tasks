#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

AGENT_SCRIPT = "/home/user/analyze_primer.py"
ORACLE_PROGRAM = "/tests/analyze_oracle"

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PROGRAM), f"Oracle program missing: {ORACLE_PROGRAM}"
    assert os.access(ORACLE_PROGRAM, os.X_OK), f"Oracle program not executable: {ORACLE_PROGRAM}"

    random.seed(42)
    chars = ['A', 'C', 'G', 'T']

    for i in range(100):
        length = random.randint(30, 100)
        seq = "".join(random.choice(chars) for _ in range(length))

        # Run oracle
        oracle_cmd = [ORACLE_PROGRAM, seq]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input {seq}: {oracle_res.stderr}"
        oracle_output = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ["python3", AGENT_SCRIPT, seq]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input {seq}: {agent_res.stderr}"
        agent_output = agent_res.stdout.strip()

        # Compare
        assert agent_output == oracle_output, (
            f"Output mismatch on input {seq} (length {length}).\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output:  {agent_output}"
        )

def test_package_installed():
    # Verify the package can be imported in python
    cmd = ["python3", "-c", "import primer_score"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 0, f"Failed to import primer_score: {res.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
