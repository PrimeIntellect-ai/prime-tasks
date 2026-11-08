#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import socket
import subprocess
import configparser
import random
import string
import pytest

def test_config_updated():
    config_path = "/home/user/pipeline/config.ini"
    assert os.path.exists(config_path), f"{config_path} does not exist"
    config = configparser.ConfigParser()
    config.read(config_path)
    assert 'server' in config, "[server] section missing in config.ini"
    assert config['server'].get('port') == '8080', "Port in config.ini is not set to 8080"

def test_aggregator_service():
    # Kill any existing aggregator processes to free up port 8080
    subprocess.run(["pkill", "-f", "aggregator.py"])
    time.sleep(0.5)

    log_file = "/home/user/pipeline/agg_out.log"
    if os.path.exists(log_file):
        os.remove(log_file)

    exp_path = "/home/user/pipeline/start_agg.exp"
    assert os.path.exists(exp_path), f"Expect script {exp_path} does not exist"

    # Run the expect script in the background
    p = subprocess.Popen(["expect", exp_path])
    time.sleep(2) # Wait for the service to start and bind

    # Connect to 8080 and send PING\n
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        s.connect(("127.0.0.1", 8080))
        s.sendall(b"PING\n")
        s.close()
    except Exception as e:
        p.kill()
        pytest.fail(f"Could not connect to aggregator on port 8080 or send data: {e}")

    time.sleep(1) # Wait for the aggregator to write to the log
    p.kill()

    assert os.path.exists(log_file), "agg_out.log was not created by the aggregator"
    with open(log_file, "r") as f:
        content = f.read()

    assert "PONG" in content, f"'PONG' not found in agg_out.log. Content was: {content}"

def generate_fuzz_lines():
    lines = []
    num_lines = random.randint(10, 100)
    for _ in range(num_lines):
        if random.random() < 0.8:
            node = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(3, 10)))
            cpu = random.randint(0, 1000)
            mem = random.randint(0, 100000)
            disk = random.randint(0, 10000)
            lines.append(f"DATA node={node} cpu={cpu} mem={mem} disk={disk}")
        else:
            # Generate malformed lines
            choice = random.randint(1, 5)
            if choice == 1:
                lines.append("INVALID prefix node=abc cpu=1 mem=2 disk=3")
            elif choice == 2:
                lines.append("DATA node=abc cpu=1 mem=2") # missing field
            elif choice == 3:
                lines.append("DATA node=abc cpu=xyz mem=2 disk=3") # non-integer
            elif choice == 4:
                lines.append("DATA node=abc  cpu=1 mem=2 disk=3") # extra space
            elif choice == 5:
                lines.append("DATA node=abc_def cpu=1 mem=2 disk=3") # invalid characters in node
    return "\n".join(lines) + "\n"

def test_planner_fuzz_equivalence():
    oracle_path = "/tests/planner_oracle.py"
    agent_path = "/home/user/planner.py"

    assert os.path.exists(oracle_path), f"Oracle script {oracle_path} does not exist"
    assert os.path.exists(agent_path), f"Agent script {agent_path} does not exist"

    random.seed(42)
    for i in range(200):
        input_data = generate_fuzz_lines()

        # Run oracle
        p_oracle = subprocess.run(
            ["python3", oracle_path],
            input=input_data,
            text=True,
            capture_output=True
        )

        # Run agent
        p_agent = subprocess.run(
            ["python3", agent_path],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert p_agent.returncode == 0, f"Agent script failed with error:\n{p_agent.stderr}"

        assert p_agent.stdout == p_oracle.stdout, (
            f"Mismatch on fuzzed input iteration {i}!\n"
            f"Input:\n{input_data}\n"
            f"Oracle Output:\n{p_oracle.stdout}\n"
            f"Agent Output:\n{p_agent.stdout}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
