#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import random
import string
import subprocess
import tempfile
import pytest

AGENT_SCRIPT = '/home/user/audit_generator.py'
ORACLE_SCRIPT = '/tests/oracle_audit.py'
NUM_ITERATIONS = 50

def generate_random_string(length=10):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_fuzz_input():
    num_objects = random.randint(10, 100)
    data = []
    for _ in range(num_objects):
        obj = {
            'timestamp': random.randint(1600000000, 1700000000),
            'service': random.choice(["SSH", "WAF", "DB", "WEB"])
        }

        # Add auth_method
        obj['auth_method'] = random.choice(["password", "publickey", "keyboard-interactive"])

        # Add payload
        if random.random() < 0.3:
            payload_injection = random.choice([
                "UNION SELECT 1,2",
                "admin' OR 1=1",
                "<script>alert(1)</script>",
                "normal_traffic"
            ])
            obj['payload'] = f"{generate_random_string(5)}_{payload_injection}_{generate_random_string(5)}"
        else:
            obj['payload'] = generate_random_string(20)

        data.append(obj)
    return data

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    random.seed(42)

    for i in range(NUM_ITERATIONS):
        input_data = generate_fuzz_input()

        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.json') as infile:
            json.dump(input_data, infile)
            infile_path = infile.name

        agent_out = infile_path + ".agent.json"
        oracle_out = infile_path + ".oracle.json"

        try:
            # Run Oracle
            subprocess.run(
                ["python3", ORACLE_SCRIPT, infile_path, oracle_out],
                check=True,
                capture_output=True,
                text=True
            )

            # Run Agent
            agent_result = subprocess.run(
                ["python3", AGENT_SCRIPT, infile_path, agent_out],
                capture_output=True,
                text=True
            )

            assert agent_result.returncode == 0, f"Agent script failed on iteration {i}. Stderr: {agent_result.stderr}"
            assert os.path.isfile(agent_out), f"Agent script did not produce output file on iteration {i}"

            with open(oracle_out, 'rb') as f:
                oracle_bytes = f.read()

            with open(agent_out, 'rb') as f:
                agent_bytes = f.read()

            if oracle_bytes != agent_bytes:
                # Try to load as JSON to provide a better error message if possible
                try:
                    oracle_json = json.loads(oracle_bytes)
                    agent_json = json.loads(agent_bytes)
                    msg = f"Output mismatch on iteration {i}.\nInput: {json.dumps(input_data, indent=2)}\nExpected: {json.dumps(oracle_json, indent=2)}\nGot: {json.dumps(agent_json, indent=2)}"
                except Exception:
                    msg = f"Output byte mismatch on iteration {i}.\nExpected bytes: {oracle_bytes}\nGot bytes: {agent_bytes}"
                pytest.fail(msg)

        finally:
            if os.path.exists(infile_path):
                os.remove(infile_path)
            if os.path.exists(agent_out):
                os.remove(agent_out)
            if os.path.exists(oracle_out):
                os.remove(oracle_out)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
