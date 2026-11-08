#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import string
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/rename_mapper.sh"
ORACLE_SCRIPT = "/tests/oracle_mapper.sh"
N_TESTS = 200

def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_random_json_array():
    num_objects = random.randint(5, 50)
    data = []
    for _ in range(num_objects):
        obj = {
            "file_id": generate_random_string(random.randint(5, 10)),
            "status": random.choice(["active", "inactive", "pending", "corrupt"]),
            "timestamp": random.randint(10000000, 99999999),
            "confidence": round(random.uniform(0.0, 1.0), 2)
        }
        data.append(obj)
    return json.dumps(data, indent=2)

def test_script_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script at {AGENT_SCRIPT} is not executable"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    random.seed(42)

    for i in range(N_TESTS):
        input_json = generate_random_json_array()

        # Run oracle uploaded only at verification time
        oracle_proc = subprocess.run(
            ["bash", ORACLE_SCRIPT],
            input=input_json,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input:\n{input_json}\nError:\n{oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            [AGENT_SCRIPT],
            input=input_json,
            text=True,
            capture_output=True
        )

        agent_out = agent_proc.stdout

        assert agent_out == oracle_out, (
            f"Output mismatch on test {i + 1}/{N_TESTS}.\n"
            f"Input JSON:\n{input_json}\n\n"
            f"Expected (Oracle):\n{oracle_out}\n\n"
            f"Got (Agent):\n{agent_out}\n\n"
            f"Agent STDERR:\n{agent_proc.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
