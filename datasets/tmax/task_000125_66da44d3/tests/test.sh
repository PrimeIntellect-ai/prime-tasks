#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/machine.sh"
ORACLE_SCRIPT = "/tests/oracle_machine"
NUM_TESTS = 500

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script at {AGENT_SCRIPT} is not executable"

def test_fuzz_equivalence():
    random.seed(42)
    chars = ['A', 'B', 'C', 'D']

    for _ in range(NUM_TESTS):
        length = random.randint(5, 50)
        input_str = "".join(random.choices(chars, k=length))

        oracle_proc = subprocess.run(["bash", ORACLE_SCRIPT, input_str], capture_output=True, text=True)
        agent_proc = subprocess.run([AGENT_SCRIPT, input_str], capture_output=True, text=True)

        assert oracle_proc.returncode == 0, f"Oracle failed on input {input_str}: {oracle_proc.stderr}"
        assert agent_proc.returncode == 0, f"Agent script failed on input {input_str} with error: {agent_proc.stderr}"

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on input: {input_str}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
