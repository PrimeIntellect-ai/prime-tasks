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

AGENT_PROGRAM = "/home/user/audit_normalizer"
ORACLE_PROGRAM = "/tests/oracle_normalizer.py"

def generate_fuzz_data(n=10000):
    random.seed(42)
    services = ["ssh", "http", "https", "mysql", "rdp", "ftp", "unknown"]
    lines = []
    for _ in range(n):
        ip = f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"
        port = random.randint(1, 65535)
        service = random.choice(services)
        cve_score = round(random.uniform(0.0, 10.0), 1)
        privesc_risk = random.choice([True, False])

        obj = {
            "ip_address": ip,
            "port": port,
            "service": service,
            "cve_score": cve_score,
            "privesc_risk": privesc_risk
        }
        lines.append(json.dumps(obj))
    return "\n".join(lines) + "\n"

def test_audit_normalizer_exists_and_executable():
    assert os.path.exists(AGENT_PROGRAM), f"Agent program not found at {AGENT_PROGRAM}"
    assert os.path.isfile(AGENT_PROGRAM), f"{AGENT_PROGRAM} is not a file"
    assert os.access(AGENT_PROGRAM, os.X_OK), f"{AGENT_PROGRAM} is not executable"

def test_fuzz_equivalence():
    input_data = generate_fuzz_data(10000)

    # Run oracle uploaded only at verification time.
    try:
        oracle_proc = subprocess.run(
            ["python3", ORACLE_PROGRAM],
            input=input_data,
            text=True,
            capture_output=True,
            check=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Oracle program failed unexpectedly: {e.stderr}")

    oracle_output = oracle_proc.stdout.strip().split("\n")

    # Run agent
    agent_proc = subprocess.run(
        [AGENT_PROGRAM],
        input=input_data,
        text=True,
        capture_output=True
    )

    if agent_proc.returncode != 0:
        pytest.fail(f"Agent program failed with return code {agent_proc.returncode}. Stderr: {agent_proc.stderr}")

    agent_output = agent_proc.stdout.strip().split("\n")

    # Compare
    input_lines = input_data.strip().split("\n")

    assert len(agent_output) == len(oracle_output), (
        f"Output line count mismatch. Expected {len(oracle_output)}, got {len(agent_output)}"
    )

    for i, (oracle_line, agent_line) in enumerate(zip(oracle_output, agent_output)):
        if oracle_line != agent_line:
            pytest.fail(
                f"Mismatch at line {i+1}:\n"
                f"Input:  {input_lines[i]}\n"
                f"Oracle: {oracle_line}\n"
                f"Agent:  {agent_line}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
