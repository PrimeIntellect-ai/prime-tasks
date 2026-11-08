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
    agent_script = "/home/user/transform.py"
    oracle_script = "/tests/oracle_transform"

    assert os.path.exists(agent_script), f"Agent script {agent_script} not found."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} not found."

    random.seed(42)
    num_tests = 20

    for i in range(num_tests):
        N = random.randint(20, 80)
        num_floats = random.randint(150, 300)

        floats = []
        for _ in range(num_floats):
            if random.random() < 0.10:
                floats.append(-999.0)
            else:
                floats.append(random.uniform(-100.0, 100.0))

        input_str = "\n".join(f"{x}" for x in floats) + "\n"

        # Run agent
        agent_cmd = ["python3", agent_script, str(N)]
        agent_proc = subprocess.run(agent_cmd, input=input_str, text=True, capture_output=True)

        # Run oracle
        oracle_cmd = ["python3", oracle_script, str(N)]
        oracle_proc = subprocess.run(oracle_cmd, input=input_str, text=True, capture_output=True)

        assert agent_proc.returncode == 0, f"Agent script failed on test {i+1} with error: {agent_proc.stderr}"
        assert oracle_proc.returncode == 0, f"Oracle script failed on test {i+1} with error: {oracle_proc.stderr}"

        agent_out = agent_proc.stdout.strip()
        oracle_out = oracle_proc.stdout.strip()

        if agent_out != oracle_out:
            pytest.fail(f"Mismatch on test {i+1} (N={N}).\nInput length: {num_floats}\nExpected output starts with:\n{oracle_out[:200]}\nGot output starts with:\n{agent_out[:200]}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
