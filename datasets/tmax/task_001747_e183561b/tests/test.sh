#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_fix_py_exists():
    assert os.path.isfile("/home/user/fix.py"), "/home/user/fix.py does not exist."

def test_fuzz_equivalence():
    agent_script = "/home/user/fix.py"
    oracle_script = "/tests/oracle_processor.py"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    random.seed(42)

    for i in range(100):
        # Generate random input
        length = random.randint(10, 1000)
        samples = [str(random.randint(-32768, 32767)) for _ in range(length)]
        input_data = ",".join(samples) + "\n"

        # Run oracle
        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=input_data,
            text=True,
            capture_output=True,
            check=False
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on round {i}"
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_data,
            text=True,
            capture_output=True,
            check=False
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed on round {i} with error:\n{agent_proc.stderr}")

        agent_out = agent_proc.stdout.strip()

        if agent_out != oracle_out:
            # Truncate input for display if it's too long
            display_input = input_data if len(input_data) < 100 else input_data[:97] + "..."
            pytest.fail(
                f"Mismatch on round {i}!\n"
                f"Input: {display_input}\n"
                f"Expected (Oracle): {oracle_out[:200]}...\n"
                f"Got (Agent):       {agent_out[:200]}..."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
