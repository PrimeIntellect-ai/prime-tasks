#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import subprocess
import pytest

def test_api_config():
    config_path = '/app/config/api.json'
    assert os.path.isfile(config_path), f"{config_path} does not exist."
    with open(config_path, 'r') as f:
        config = json.load(f)
    assert config.get('port') == 8080, f"Expected port to be 8080, got {config.get('port')} in {config_path}"

def test_orchestrator_config():
    config_path = '/app/config/orchestrator.json'
    assert os.path.isfile(config_path), f"{config_path} does not exist."
    with open(config_path, 'r') as f:
        config = json.load(f)
    expected_url = 'redis://127.0.0.1:6379'
    assert config.get('broker_url') == expected_url, f"Expected broker_url to be {expected_url}, got {config.get('broker_url')} in {config_path}"

def test_processor_executable():
    processor_path = '/home/user/processor.py'
    assert os.path.isfile(processor_path), f"{processor_path} does not exist."
    assert os.access(processor_path, os.X_OK), f"{processor_path} is not executable."

def test_fuzz_equivalence():
    agent_script = '/home/user/processor.py'
    oracle_script = '/tests/oracle_processor.py'

    assert os.path.isfile(agent_script), f"Agent script {agent_script} missing."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} missing."

    random.seed(42)

    for i in range(200):
        N = random.randint(10, 100)
        M = random.randint(2, 10)

        data = []
        for _ in range(N):
            row = [random.uniform(-10.0, 10.0) for _ in range(M)]
            data.append(row)

        input_json = json.dumps({"data": data})

        oracle_proc = subprocess.run(
            ['python3', oracle_script],
            input=input_json,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}: {oracle_proc.stderr}"
        oracle_output = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            ['python3', agent_script],
            input=input_json,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}. Stderr: {agent_proc.stderr}"
        agent_output = agent_proc.stdout.strip()

        try:
            oracle_json = json.loads(oracle_output)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle produced invalid JSON: {oracle_output}")

        try:
            agent_json = json.loads(agent_output)
        except json.JSONDecodeError:
            pytest.fail(f"Agent produced invalid JSON: {agent_output}")

        assert agent_json == oracle_json, (
            f"Mismatch on iteration {i}.\n"
            f"Input: {input_json[:100]}...\n"
            f"Expected: {oracle_output}\n"
            f"Got: {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
