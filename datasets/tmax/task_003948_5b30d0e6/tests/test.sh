#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import random
import string
import json
import urllib.request
import urllib.error
import time
import pytest

def test_backend_env_file():
    env_path = "/home/user/backend/.env"
    assert os.path.isfile(env_path), f"Missing .env file at {env_path}"

    with open(env_path, "r") as f:
        content = f.read().strip()

    assert content == "AUTH_KEY=AlphaBravo123", f"Incorrect content in {env_path}"

    st = os.stat(env_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Incorrect permissions on {env_path}: expected 600, got {oct(perms)}"

def test_nginx_config():
    conf_path = "/home/user/proxy/nginx.conf"
    assert os.path.isfile(conf_path), f"Missing Nginx config at {conf_path}"

    with open(conf_path, "r") as f:
        content = f.read()

    assert "/inspect" in content, "Nginx config does not contain a location block for /inspect"
    assert "127.0.0.1:5000" in content or "localhost:5000" in content, "Nginx config does not proxy to port 5000"

def test_end_to_end_flow():
    # Attempt to hit the endpoint
    url = "http://127.0.0.1:8080/inspect"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            data = json.loads(response.read().decode('utf-8'))
            assert data.get("status") == "success", "Expected status: success in JSON"
            assert "token" in data, "Expected 'token' in JSON response"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to {url} or bad response: {e}")

def test_fuzz_equivalence():
    oracle_path = "/app/legacy_parser"
    agent_script = "/home/user/parse_token.py"

    assert os.path.isfile(agent_script), f"Missing agent script at {agent_script}"

    random.seed(42)
    charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="

    # Generate random inputs
    inputs = []
    for _ in range(500):
        length = random.randint(1, 100)
        inp = "".join(random.choice(charset) for _ in range(length))
        inputs.append(inp)

    # Add some specific edge cases
    inputs.extend([
        "TkVUOg==", # "NET:"
        "TkVUOmhlbGxv", # "NET:hello"
        "TkVU", # "NET" (invalid base64 length or missing padding)
        "invalid_base64!!!",
        "TkVU", # valid base64 but bad header
        "QkFEOg==", # "BAD:"
    ])

    for inp in inputs:
        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_path, inp],
            capture_output=True,
            text=True
        )

        # Run agent
        agent_proc = subprocess.run(
            ["python3", agent_script, inp],
            capture_output=True,
            text=True
        )

        assert agent_proc.returncode == oracle_proc.returncode, \
            f"Return code mismatch on input '{inp}'. Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"

        assert agent_proc.stdout == oracle_proc.stdout, \
            f"Stdout mismatch on input '{inp}'. Oracle: {oracle_proc.stdout!r}, Agent: {agent_proc.stdout!r}"

        assert agent_proc.stderr == oracle_proc.stderr, \
            f"Stderr mismatch on input '{inp}'. Oracle: {oracle_proc.stderr!r}, Agent: {agent_proc.stderr!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
