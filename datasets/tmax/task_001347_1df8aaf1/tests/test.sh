#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import urllib.request
import json
import pytest


def test_processor_fuzz_equivalence():
    """Fuzz test the agent's processor against the test-only oracle."""
    oracle_path = '/tests/oracle_processor'
    agent_path = '/home/user/processor'

    assert os.path.isfile(oracle_path), f"Oracle not found at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent processor not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent processor at {agent_path} is not executable"

    random.seed(42)
    N = 500

    for i in range(N):
        length = random.randint(10, 1000)
        nums = [random.uniform(-1000.0, 1000.0) for _ in range(length)]
        input_str = " ".join(map(str, nums)) + "\n"

        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=input_str,
                text=True,
                capture_output=True,
                check=True
            )
            oracle_out = oracle_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i}. Stderr: {e.stderr}")

        try:
            agent_proc = subprocess.run(
                [agent_path],
                input=input_str,
                text=True,
                capture_output=True,
                check=True
            )
            agent_out = agent_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent processor failed on iteration {i}. Stderr: {e.stderr}")

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on iteration {i}.\n"
                f"Input length: {length}\n"
                f"Oracle output: {oracle_out}\n"
                f"Agent output: {agent_out}"
            )


def test_emitter_config_corrected():
    """Check if the emitter config has the correct REDIS_PORT."""
    config_path = '/home/user/services/emitter/config.env'
    assert os.path.isfile(config_path), f"{config_path} does not exist."
    with open(config_path, 'r') as f:
        content = f.read()

    assert 'REDIS_PORT=6379' in content, f"Expected REDIS_PORT=6379 in {config_path}."
    assert 'REDIS_PORT=6380' not in content, f"REDIS_PORT=6380 should be removed from {config_path}."


def test_analyzer_config_corrected():
    """Check if the analyzer config has the correct REDIS_PORT and PROCESSOR_PATH."""
    config_path = '/home/user/services/analyzer/config.env'
    assert os.path.isfile(config_path), f"{config_path} does not exist."
    with open(config_path, 'r') as f:
        content = f.read()

    assert 'REDIS_PORT=6379' in content, f"Expected REDIS_PORT=6379 in {config_path}."
    assert 'REDIS_PORT=6380' not in content, f"REDIS_PORT=6380 should be removed from {config_path}."
    assert 'PROCESSOR_PATH=/home/user/processor' in content, f"Expected PROCESSOR_PATH=/home/user/processor in {config_path}."


def test_analyzer_endpoint():
    """Check if the analyzer endpoint returns 200 OK and valid JSON with kl_divergence."""
    url = "http://127.0.0.1:5001/analyze"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as response:
            assert response.status == 200, f"Expected HTTP 200 OK, got {response.status}"
            data = json.loads(response.read().decode('utf-8'))

            assert "status" in data, "Response JSON missing 'status' key."
            assert data["status"] == "ok", f"Expected status 'ok', got {data['status']}"
            assert "kl_divergence" in data, "Response JSON missing 'kl_divergence' key."
            assert isinstance(data["kl_divergence"], float), "kl_divergence must be a float."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to analyzer endpoint at {url}. Are the services running? Error: {e}")
    except json.JSONDecodeError:
        pytest.fail("Analyzer endpoint did not return valid JSON.")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
