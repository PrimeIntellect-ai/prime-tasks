#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import urllib.request
import subprocess
import json
import random
import os
import pytest

def test_services_running():
    """
    Checks if the tracker API is running on port 8080 and successfully pings Redis.
    """
    try:
        req = urllib.request.Request("http://127.0.0.1:8080/health")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP status 200, got {response.status}"
            body = response.read().decode('utf-8')
            assert body == "OK", f"Expected body 'OK', got {body}"
    except Exception as e:
        pytest.fail(f"Failed to connect to the tracker API or Redis is not working properly: {e}")

def generate_fuzz_input():
    """
    Generates a single random JSON input for fuzz testing.
    """
    users = []
    events = []

    for _ in range(random.randint(0, 50)):
        u = {"user_id": random.randint(1, 100), "age": random.randint(-10, 100)}
        if random.random() < 0.1:
            if u: u.pop(random.choice(list(u.keys())))
        elif random.random() < 0.1:
            if u:
                k = random.choice(list(u.keys()))
                u[k] = str(u[k])
        users.append(u)

    for _ in range(random.randint(0, 50)):
        e = {"user_id": random.randint(1, 100), "clicks": random.randint(-10, 100), "time": random.uniform(-1, 10)}
        if random.random() < 0.1:
            if e: e.pop(random.choice(list(e.keys())))
        elif random.random() < 0.1:
            if e:
                k = random.choice(list(e.keys()))
                e[k] = str(e[k])
        events.append(e)

    return json.dumps({"users": users, "events": events})

def test_fuzz_equivalence():
    """
    Tests the agent's process.py against the reference oracle_processor using 500 fuzz iterations.
    """
    agent_script = "/home/user/process.py"
    oracle_script = "/tests/oracle_processor"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}"

    random.seed(42)

    for i in range(500):
        input_data = generate_fuzz_input()

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )
        agent_out = agent_proc.stdout.strip()

        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=input_data,
            text=True,
            capture_output=True
        )
        oracle_out = oracle_proc.stdout.strip()

        if agent_out != oracle_out:
            pytest.fail(
                f"Mismatch on iteration {i}.\n"
                f"Input: {input_data}\n"
                f"Oracle Output: {oracle_out}\n"
                f"Agent Output: {agent_out}\n"
                f"Agent Stderr: {agent_proc.stderr}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
