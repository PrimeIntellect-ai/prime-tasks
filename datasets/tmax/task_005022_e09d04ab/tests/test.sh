#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_EXE = "/home/user/polyglot/compute_engine/target/release/compute_engine"
ORACLE_EXE = "/tests/oracle_engine"
API_SERVER = "/home/user/polyglot/api/server.py"
MAKEFILE = "/home/user/polyglot/Makefile"

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_EXE), f"Agent executable missing at {AGENT_EXE}. Did you build the release version?"

def test_api_server_exists():
    assert os.path.isfile(API_SERVER), f"API server missing at {API_SERVER}."

def test_makefile_exists():
    assert os.path.isfile(MAKEFILE), f"Makefile missing at {MAKEFILE}."

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_EXE), f"Oracle executable missing at {ORACLE_EXE}"
    assert os.path.isfile(AGENT_EXE), f"Agent executable missing at {AGENT_EXE}"

    random.seed(42)
    # Fuzzing parameters from truth
    min_val = 0
    max_val = 100000000
    n_iterations = 5000

    inputs = [random.randint(min_val, max_val) for _ in range(n_iterations)]

    for val in inputs:
        val_str = str(val)

        # Run oracle
        oracle_proc = subprocess.run([ORACLE_EXE, val_str], capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on input {val_str}"
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run([AGENT_EXE, val_str], capture_output=True, text=True)
        assert agent_proc.returncode == 0, f"Agent program failed or crashed on input {val_str}. Stderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mathematical mismatch on input {val_str}.\n"
            f"Oracle expected: {oracle_out}\n"
            f"Agent produced: {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
