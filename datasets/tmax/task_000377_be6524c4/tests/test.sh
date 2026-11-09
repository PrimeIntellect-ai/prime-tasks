#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import string
import subprocess


def generate_random_input():
    name_length = random.randint(1, 50)
    dataset_name = ''.join(random.choices(string.ascii_letters + string.digits, k=name_length))
    num_rows = random.randint(1, 10_000_000)
    is_public = random.choice([True, False])
    return {
        "dataset_name": dataset_name,
        "num_rows": num_rows,
        "is_public": is_public
    }


def test_fuzz_equivalence():
    agent_script = "/home/user/dataset_encoder.py"
    oracle_program = "/tests/oracle_encoder"

    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.exists(oracle_program), f"Oracle program {oracle_program} does not exist."

    random.seed(42)
    N = 10000
    inputs = [generate_random_input() for _ in range(N)]

    for i, input_data in enumerate(inputs):
        input_json = json.dumps(input_data)

        oracle_proc = subprocess.run(
            ["python3", oracle_program],
            input=input_json,
            text=True,
            capture_output=True
        )
        oracle_output = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_json,
            text=True,
            capture_output=True
        )
        agent_output = agent_proc.stdout.strip()

        assert agent_proc.returncode == 0, f"Agent script failed on input: {input_json}\nError: {agent_proc.stderr}"
        assert oracle_output == agent_output, (
            f"Mismatch on input {i+1}/{N}:\n"
            f"Input: {input_json}\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
