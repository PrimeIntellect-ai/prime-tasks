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
import urllib.request
import urllib.error

def generate_random_input():
    num_items = random.randint(15, 60)
    data = []
    for _ in range(num_items):
        text_len = random.randint(5, 100)
        text = "".join(random.choices(string.ascii_letters + string.digits + string.punctuation + " \t\n\r", k=text_len))
        target = random.uniform(-10.0, 10.0)
        data.append({"text": text, "target": target})
    return json.dumps(data)

def test_services_running():
    # Check if Redis is running
    try:
        import redis
        client = redis.Redis(host='127.0.0.1', port=6379)
        assert client.ping(), "Redis is not responding to ping"
    except Exception as e:
        pytest.fail(f"Redis service check failed: {e}")

    # Check if FastAPI is running
    try:
        req = urllib.request.urlopen("http://127.0.0.1:8000/embed?text=test", timeout=2)
        assert req.getcode() == 200, "FastAPI service did not return 200 OK"
    except Exception as e:
        pytest.fail(f"FastAPI service check failed: {e}")

def test_fuzz_equivalence():
    agent_script = "/home/user/clean_pipeline.py"
    oracle_script = "/tests/oracle_pipeline.py"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script at {agent_script} is not executable"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)

    for i in range(50):
        input_data = generate_random_input()

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )

        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert oracle_proc.returncode == 0, f"Oracle script failed on iteration {i}. Stderr: {oracle_proc.stderr}"
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}. Stderr: {agent_proc.stderr}"

        try:
            agent_out = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent script output invalid JSON on iteration {i}.\nOutput: {agent_proc.stdout}")

        try:
            oracle_out = json.loads(oracle_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle script output invalid JSON on iteration {i}.\nOutput: {oracle_proc.stdout}")

        assert agent_out == oracle_out, (
            f"Mismatch on iteration {i}.\n"
            f"Input: {input_data}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output: {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
