#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import urllib.request
import urllib.error
import pytest

def generate_pdb(seed):
    random.seed(seed)
    num_atoms = random.randint(20, 100)
    lines = []
    for i in range(1, num_atoms + 1):
        x = random.uniform(0.0, 5.0)
        y = random.uniform(0.0, 5.0)
        z = random.uniform(0.0, 5.0)
        lines.append(f"ATOM {i} {x:.6f} {y:.6f} {z:.6f}")
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    agent_script = "/home/user/graph_metric.py"
    oracle_script = "/tests/oracle"

    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."

    for i in range(100):
        pdb_data = generate_pdb(i)

        oracle_proc = subprocess.run(
            [oracle_script],
            input=pdb_data,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=pdb_data,
            text=True,
            capture_output=True
        )
        agent_out = agent_proc.stdout.strip()

        assert agent_proc.returncode == 0, f"Agent script failed on seed {i}. Error: {agent_proc.stderr}"
        assert agent_out == oracle_out, f"Mismatch on seed {i}.\nInput:\n{pdb_data}\nOracle output: {oracle_out}\nAgent output: {agent_out}"

def test_flask_direct():
    pdb_data = "ATOM 1 0.0 0.0 0.0\nATOM 2 0.5 0.0 0.0\n"
    req = urllib.request.Request(
        "http://localhost:5000/calc",
        data=pdb_data.encode('utf-8'),
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200 from Flask, got {response.status}"
            body = response.read().decode('utf-8').strip()
            assert body == "1.00000000", f"Expected '1.00000000' from Flask, got {body}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Flask at port 5000: {e}")

def test_nginx_flask_integration():
    pdb_data = "ATOM 1 0.0 0.0 0.0\nATOM 2 0.5 0.0 0.0\n"
    req = urllib.request.Request(
        "http://localhost:8080/api/calc",
        data=pdb_data.encode('utf-8'),
        method="POST"
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200 from Nginx, got {response.status}"
            body = response.read().decode('utf-8').strip()
            assert body == "1.00000000", f"Expected '1.00000000' from Nginx proxy, got {body}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx at port 8080: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
