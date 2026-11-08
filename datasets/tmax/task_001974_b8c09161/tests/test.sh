#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/archive_tool.py"
ORACLE_SCRIPT = "/tests/oracle_archive_tool.py"
N_TESTS = 50
MIN_LEN = 10
MAX_LEN = 100000

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    random.seed(42)

    for i in range(N_TESTS):
        length = random.randint(MIN_LEN, MAX_LEN)
        input_data = bytearray(random.getrandbits(8) for _ in range(length))

        with tempfile.NamedTemporaryFile(delete=False) as f_in, \
             tempfile.NamedTemporaryFile(delete=False) as f_oracle_out, \
             tempfile.NamedTemporaryFile(delete=False) as f_agent_out:

            f_in.write(input_data)
            f_in.flush()

            input_path = f_in.name
            oracle_out_path = f_oracle_out.name
            agent_out_path = f_agent_out.name

        try:
            oracle_res = subprocess.run(
                ["python3", ORACLE_SCRIPT, input_path, oracle_out_path],
                capture_output=True, text=True
            )
            assert oracle_res.returncode == 0, f"Oracle failed on test {i}: {oracle_res.stderr}"

            agent_res = subprocess.run(
                ["python3", AGENT_SCRIPT, input_path, agent_out_path],
                capture_output=True, text=True
            )
            assert agent_res.returncode == 0, f"Agent script failed on test {i}: {agent_res.stderr}"

            with open(oracle_out_path, 'rb') as f:
                oracle_output = f.read()

            with open(agent_out_path, 'rb') as f:
                agent_output = f.read()

            assert oracle_output == agent_output, (
                f"Mismatch on test {i} (input length {length}).\n"
                f"Agent output length: {len(agent_output)}, Oracle output length: {len(oracle_output)}\n"
                f"Agent output ending: {agent_output[-100:]}\n"
                f"Oracle output ending: {oracle_output[-100:]}"
            )
        finally:
            for p in [input_path, oracle_out_path, agent_out_path]:
                if os.path.exists(p):
                    os.remove(p)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
