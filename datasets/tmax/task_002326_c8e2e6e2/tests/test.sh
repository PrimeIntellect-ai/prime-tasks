#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import ipaddress
import pytest

def test_critical_nodes():
    """Test Part 1: Diagnostic Extraction (Video)"""
    expected_ips = [
        "10.5.2.11",
        "172.16.8.99",
        "192.168.100.4",
        "192.168.100.5"
    ]
    file_path = "/home/user/critical_nodes.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        actual_ips = [line.strip() for line in f if line.strip()]

    assert actual_ips == expected_ips, (
        f"Contents of {file_path} do not match expected output.\n"
        f"Expected: {expected_ips}\n"
        f"Got: {actual_ips}"
    )

def generate_random_ip():
    return str(ipaddress.IPv4Address(random.randint(0, 2**32 - 1)))

def generate_random_route():
    ip = generate_random_ip()
    mask = random.randint(0, 32)
    # strict=False allows masking off the host bits to get a valid network address
    network = str(ipaddress.IPv4Network(f"{ip}/{mask}", strict=False).network_address)
    next_hop = generate_random_ip()
    return f"{network}/{mask} {next_hop}"

def generate_routing_table(num_lines):
    return "\n".join(generate_random_route() for _ in range(num_lines)) + "\n"

def test_fuzz_route_filter():
    """Test Part 2: Failover Route Evaluator (Bash) via Fuzzing"""
    random.seed(42)
    oracle_path = "/tests/oracle_route_filter"
    agent_script = "/home/user/route_filter.sh"

    assert os.path.isfile(oracle_path), f"Oracle {oracle_path} is missing."
    assert os.access(oracle_path, os.X_OK), f"Oracle {oracle_path} is not executable."
    assert os.path.isfile(agent_script), f"Agent script {agent_script} is missing."

    N = 500
    for i in range(N):
        target_ip = generate_random_ip()
        num_routes = random.randint(10, 50)

        # Inject an edge case sometimes
        if random.random() < 0.1:
            routing_table = "0.0.0.0/0 " + generate_random_ip() + "\n" + generate_routing_table(num_routes - 1)
        else:
            routing_table = generate_routing_table(num_routes)

        # Run Oracle
        oracle_proc = subprocess.run(
            [oracle_path, target_ip],
            input=routing_table,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, "Oracle script failed unexpectedly."
        oracle_out = oracle_proc.stdout.strip()

        # Run Agent
        agent_proc = subprocess.run(
            ["/bin/bash", agent_script, target_ip],
            input=routing_table,
            text=True,
            capture_output=True
        )
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch found on fuzz iteration {i+1}/{N}.\n"
            f"Target IP: {target_ip}\n"
            f"Routing Table (stdin):\n{routing_table}\n"
            f"Expected Output (Oracle): '{oracle_out}'\n"
            f"Actual Output (Agent): '{agent_out}'\n"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
