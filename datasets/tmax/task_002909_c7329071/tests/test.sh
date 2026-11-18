#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import random
import subprocess
import socket
import tempfile
import urllib.request
import urllib.error
import pytest

def test_services_running():
    """Check if the required services are listening on their respective ports."""
    services = [
        (6379, 'Redis'),
        (5000, 'Flask API'),
        (8080, 'Nginx')
    ]
    for port, name in services:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            result = s.connect_ex(('127.0.0.1', port))
            assert result == 0, f"{name} is not listening on port {port}."

def test_nginx_proxy_and_api():
    """Test the end-to-end flow via Nginx proxy to the Flask API."""
    url = "http://127.0.0.1:8080/api/process"
    signal = [float(i) for i in range(10)]
    payload = json.dumps({"signal": signal}).encode('utf-8')
    req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            res_data = response.read()
            res_json = json.loads(res_data)

            expected_keys = {"total_energy", "weighted_centroid", "peak_index"}
            assert expected_keys.issubset(res_json.keys()), f"Response JSON missing keys. Got: {res_json.keys()}"
    except urllib.error.URLError as e:
        pytest.fail(f"API request to {url} failed. Nginx proxy or Flask app might not be configured correctly. Error: {e}")

def test_fuzz_equivalence():
    """Fuzz equivalence test: compare agent script output with the oracle on 500 random inputs."""
    oracle_path = "/tests/oracle_process_signal"
    agent_script = "/home/user/process_signal.py"

    assert os.path.isfile(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"

    random.seed(42)
    iterations = 500
    signal_length = 1024

    for i in range(iterations):
        signal = [random.uniform(-100.0, 100.0) for _ in range(signal_length)]

        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tmp_file:
            json.dump(signal, tmp_file)
            input_file = tmp_file.name

        try:
            oracle_proc = subprocess.run(
                [oracle_path, input_file],
                capture_output=True, text=True
            )
            assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}: {oracle_proc.stderr}"

            agent_proc = subprocess.run(
                ["python3", agent_script, input_file],
                capture_output=True, text=True
            )
            assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}: {agent_proc.stderr}"

            try:
                oracle_json = json.loads(oracle_proc.stdout)
            except json.JSONDecodeError:
                pytest.fail(f"Oracle produced invalid JSON on iteration {i}: {oracle_proc.stdout}")

            try:
                agent_json = json.loads(agent_proc.stdout)
            except json.JSONDecodeError:
                pytest.fail(f"Agent produced invalid JSON on iteration {i}: {agent_proc.stdout}")

            assert oracle_json == agent_json, (
                f"Output mismatch on iteration {i}.\n"
                f"Oracle: {oracle_json}\n"
                f"Agent:  {agent_json}"
            )

        finally:
            if os.path.exists(input_file):
                os.remove(input_file)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
