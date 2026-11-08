#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import json
import urllib.request
import urllib.error
import pytest

def test_sign_build_fuzz_equivalence():
    """Test that the agent's sign_build.sh matches the oracle bit-for-bit on random inputs."""
    agent_script = "/home/user/sign_build.sh"
    oracle_script = "/tests/oracle_signer"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)
    chars = string.ascii_letters + string.digits

    for _ in range(500):
        length = random.randint(8, 32)
        input_str = ''.join(random.choice(chars) for _ in range(length))

        agent_proc = subprocess.run([agent_script, input_str], capture_output=True, text=True)
        oracle_proc = subprocess.run([oracle_script, input_str], capture_output=True, text=True)

        assert agent_proc.returncode == 0, f"Agent script failed (non-zero exit) on input '{input_str}': {agent_proc.stderr}"
        assert oracle_proc.returncode == 0, f"Oracle script failed on input '{input_str}'"

        agent_out = agent_proc.stdout.strip()
        oracle_out = oracle_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Fuzz equivalence mismatch on input '{input_str}'.\n"
            f"Expected (Oracle): '{oracle_out}'\n"
            f"Got (Agent):       '{agent_out}'"
        )

def test_nginx_and_api_integration():
    """Test that Nginx reverse proxies to the Bash API and returns correct JSON."""
    random.seed(1337)
    chars = string.ascii_letters + string.digits
    input_str = ''.join(random.choice(chars) for _ in range(16))

    url = f"http://127.0.0.1:8080/api/sign?build_id={input_str}"

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            body = response.read().decode('utf-8')
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                pytest.fail(f"Response body is not valid JSON: {body}")

            assert "signature" in data, f"JSON response missing 'signature' key. Got: {data}"

            # Verify signature using oracle uploaded only at verification time
            oracle_script = "/tests/oracle_signer"
            oracle_proc = subprocess.run([oracle_script, input_str], capture_output=True, text=True)
            oracle_out = oracle_proc.stdout.strip()

            assert data["signature"] == oracle_out, (
                f"API returned incorrect signature for input '{input_str}'.\n"
                f"Expected: {oracle_out}\n"
                f"Got:      {data['signature']}"
            )

    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx reverse proxy at {url}. Is Nginx running on port 8080? Error: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
