#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import string
import random
import subprocess
import urllib.request
import urllib.error
import pytest

def test_nginx_proxy_success():
    """Verify that querying Nginx on port 8080 returns a 200 OK response."""
    url = "http://127.0.0.1:8080"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200 from {url}, got {response.status}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx at {url} or received an error: {e}")

def test_supervisor_script_exists():
    """Verify that the supervisor script exists and is executable."""
    supervisor_path = "/home/user/supervisor.sh"
    assert os.path.isfile(supervisor_path), f"Supervisor script {supervisor_path} is missing."
    assert os.access(supervisor_path, os.X_OK), f"Supervisor script {supervisor_path} is not executable."

def test_backend_processor_fuzz_equivalence():
    """Verify that the user's backend processor matches the oracle on random inputs."""
    agent_path = "/home/user/backend_processor"
    oracle_path = "/tests/oracle_processor.py"

    assert os.path.isfile(agent_path), f"Agent program {agent_path} is missing."
    assert os.access(agent_path, os.X_OK), f"Agent program {agent_path} is not executable."
    assert os.path.isfile(oracle_path), f"Oracle program {oracle_path} is missing."
    assert os.access(oracle_path, os.X_OK), f"Oracle program {oracle_path} is not executable."

    random.seed(42)
    printable_chars = string.printable

    N = 1000
    for i in range(N):
        length = random.randint(1, 500)
        input_text = ''.join(random.choice(printable_chars) for _ in range(length))
        input_bytes = input_text.encode('utf-8')

        oracle_proc = subprocess.run(
            [oracle_path],
            input=input_bytes,
            capture_output=True,
            timeout=2
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input: {repr(input_text)}"
        oracle_output = oracle_proc.stdout

        try:
            agent_proc = subprocess.run(
                [agent_path],
                input=input_bytes,
                capture_output=True,
                timeout=2
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on input: {repr(input_text)}")

        assert agent_proc.returncode == 0, f"Agent program failed (exit code {agent_proc.returncode}) on input: {repr(input_text)}\nStderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
        agent_output = agent_proc.stdout

        if agent_output != oracle_output:
            pytest.fail(
                f"Mismatch on random input!\n"
                f"Input: {repr(input_text)}\n"
                f"Oracle output: {repr(oracle_output.decode('utf-8', errors='replace'))}\n"
                f"Agent output: {repr(agent_output.decode('utf-8', errors='replace'))}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
