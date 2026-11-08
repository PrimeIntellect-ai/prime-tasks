#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import time
import random
import pytest

def test_env_file_modified():
    env_path = "/app/.env"
    assert os.path.isfile(env_path), f"The configuration file {env_path} is missing."
    with open(env_path, "r") as f:
        content = f.read()
    assert "PORT=5000" in content, "PORT is not set to 5000 in /app/.env"
    assert "REDIS_URL=redis://127.0.0.1:6379/0" in content, "REDIS_URL is not correctly set in /app/.env"

def test_fuzz_equivalence():
    agent_script = "/home/user/process.sh"
    oracle_script = "/tests/oracle_process.sh"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    # Ensure any previous instances are killed
    subprocess.run(["pkill", "-f", "api.py"], capture_output=True)
    subprocess.run(["pkill", "-f", "redis-server"], capture_output=True)
    time.sleep(1)

    # Start the services via the provided startup script
    start_proc = subprocess.Popen(["bash", "/app/start.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(3)

    try:
        random.seed(42)
        for _ in range(100):
            tx_id = f"tx_{random.randint(1000, 999999)}"
            user_id = f"user_{random.randint(1, 9)}"
            amount = f"{random.uniform(10.0, 5000.0):.2f}"
            timestamp = f"{random.randint(1600000000, 1700000000)}"

            csv_line = f"{tx_id},{user_id},{amount},{timestamp}\n"

            # Run oracle supplied only at verification time
            oracle_proc = subprocess.run(
                ["bash", oracle_script],
                input=csv_line,
                text=True,
                capture_output=True
            )
            oracle_out = oracle_proc.stdout.strip()

            # Run agent
            agent_proc = subprocess.run(
                ["bash", agent_script],
                input=csv_line,
                text=True,
                capture_output=True
            )
            agent_out = agent_proc.stdout.strip()

            assert agent_out == oracle_out, (
                f"Mismatch on input '{csv_line.strip()}'.\n"
                f"Oracle output: '{oracle_out}'\n"
                f"Agent output: '{agent_out}'\n"
                f"Agent stderr: '{agent_proc.stderr}'"
            )
    finally:
        start_proc.terminate()
        subprocess.run(["pkill", "-f", "api.py"], capture_output=True)
        subprocess.run(["pkill", "-f", "redis-server"], capture_output=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
