#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import pytest

def generate_fuzz_inputs(n=1000):
    random.seed(42)
    inputs = []
    for _ in range(n):
        # Field 1 (ID)
        r1 = random.random()
        if r1 < 0.1:
            f1 = ""
        elif r1 < 0.2:
            f1 = "invalid"
        else:
            f1 = str(random.randint(1, 999999))

        # Field 2 (Temperature)
        r2 = random.random()
        if r2 < 0.1:
            f2 = ""
        elif r2 < 0.2:
            f2 = "NaN"
        elif r2 < 0.3:
            f2 = "invalid_temp"
        else:
            f2 = str(round(random.uniform(-50.0, 150.0), random.randint(1, 5)))

        # Field 3 (Status)
        r3 = random.random()
        if r3 < 0.1:
            f3 = ""
        else:
            f3 = random.choice(['A', 'I', 'U', 'X', 'B', 'Active'])

        # Field 4 (Date)
        if random.random() < 0.2:
            f4 = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(4, 12)))
        else:
            y = random.randint(1900, 2100)
            m = random.randint(1, 12)
            d = random.randint(1, 28)
            f4 = f"{y:04d}-{m:02d}-{d:02d}"

        inputs.append(f"{f1},{f2},{f3},{f4}")

    # Add some edge cases
    inputs.append(",,,")
    inputs.append("123,45.67,A,2021-01-01")
    inputs.append("99999999999999,-100.55,I,1999-12-31")
    return inputs

def test_cleaner_script_exists():
    assert os.path.isfile("/home/user/cleaner.py"), "/home/user/cleaner.py does not exist."

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_cleaner.py"
    agent_script = "/home/user/cleaner.py"

    assert os.path.isfile(oracle_path), f"Oracle script missing at {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"

    inputs = generate_fuzz_inputs(1000)

    for i, inp in enumerate(inputs):
        # Run oracle
        oracle_cmd = ["python3", oracle_path, inp]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input: {inp}"
        oracle_out = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ["python3", agent_script, inp]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input: {inp}\nStderr: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input {i}:\n"
            f"Input:  {inp}\n"
            f"Oracle: {oracle_out}\n"
            f"Agent:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
