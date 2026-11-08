#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import pytest

def generate_valid_format_input():
    # Username: root, short, or long
    choice = random.random()
    if choice < 0.1:
        user = "root"
    elif choice < 0.3:
        user = "".join(random.choices(string.ascii_lowercase, k=random.randint(1, 4)))
    else:
        user = "".join(random.choices(string.ascii_lowercase, k=random.randint(5, 12)))

    # IP: valid or invalid components
    ip_parts = []
    for _ in range(4):
        if random.random() < 0.1:
            ip_parts.append(str(random.randint(256, 300)))
        else:
            ip_parts.append(str(random.randint(0, 255)))
    ip = ".".join(ip_parts)

    return f"{user} {ip}"

def generate_malformed_input():
    choice = random.random()
    if choice < 0.2:
        return "".join(random.choices(string.ascii_lowercase, k=random.randint(3, 10)))
    elif choice < 0.4:
        return f"user {' '.join([str(random.randint(0, 255)) for _ in range(4)])}"
    elif choice < 0.6:
        return f"user  192.168.1.1" # extra space
    elif choice < 0.8:
        return f"user 192.168.1" # missing part
    else:
        return f"user 192.168.1.1 extra"

def test_ssh_config():
    config_path = "/home/user/.ssh/config"
    assert os.path.exists(config_path), "SSH config file does not exist at /home/user/.ssh/config"
    with open(config_path, "r") as f:
        content = f.read()

    # Simple check for Host local_tunnel, HostName 127.0.0.1, Port 2222
    assert "Host local_tunnel" in content or "Host  local_tunnel" in content, "Host local_tunnel not found in SSH config"
    assert "127.0.0.1" in content, "127.0.0.1 not found in SSH config"
    assert "2222" in content, "Port 2222 not found in SSH config"

def test_filter_fuzz_equivalence():
    agent_script = "/home/user/filter.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)
    inputs = []
    for _ in range(2500):
        inputs.append(generate_valid_format_input())
    for _ in range(2500):
        inputs.append(generate_malformed_input())

    random.shuffle(inputs)

    for i, inp in enumerate(inputs):
        # Run oracle
        oracle_proc = subprocess.run(
            ["/usr/bin/python3", oracle_script],
            input=inp,
            text=True,
            capture_output=True
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            ["/usr/bin/python3", agent_script],
            input=inp,
            text=True,
            capture_output=True
        )
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch on input {i}: {repr(inp)}\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output: {repr(agent_out)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
