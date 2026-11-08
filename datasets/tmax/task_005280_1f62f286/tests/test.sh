#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import string

def test_payload_gen_equivalence():
    oracle_path = "/app/payload_gen"
    agent_script = "/home/user/payload_gen.py"

    assert os.path.exists(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"

    random.seed(42)
    hex_chars = "0123456789abcdef"

    num_tests = 1000

    for i in range(num_tests):
        # Generate a random 64-character hex string
        test_input = "".join(random.choice(hex_chars) for _ in range(64))

        # Run oracle
        oracle_result = subprocess.run(
            [oracle_path, test_input],
            capture_output=True,
            text=True
        )
        assert oracle_result.returncode == 0, f"Oracle failed on input {test_input}"
        oracle_output = oracle_result.stdout.strip()

        # Run agent
        agent_result = subprocess.run(
            ["python3", agent_script, test_input],
            capture_output=True,
            text=True
        )
        assert agent_result.returncode == 0, f"Agent script failed on input {test_input}. Stderr: {agent_result.stderr}"
        agent_output = agent_result.stdout.strip()

        # Compare
        assert agent_output == oracle_output, (
            f"Mismatch on input {test_input}.\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent):       {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
