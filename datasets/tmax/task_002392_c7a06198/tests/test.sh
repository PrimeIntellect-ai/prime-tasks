#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import base64
import subprocess
import pytest

def generate_fuzz_inputs(n=500):
    random.seed(42)
    inputs = []
    for _ in range(n):
        path = f"/api/{''.join(random.choices(string.ascii_lowercase, k=random.randint(3, 10)))}"
        raw_payload = bytes(random.choices(range(256), k=random.randint(10, 256)))
        b64_payload = base64.b64encode(raw_payload).decode('utf-8')
        checksum = str(random.randint(0, 1000000))

        choice = random.random()
        if choice < 0.1:
            inputs.append(f"malformed_url_{random.randint(1, 100)}")
        elif choice < 0.2:
            inputs.append(f"{path}?payload={b64_payload[:-1]}&checksum={checksum}")
        elif choice < 0.3:
            inputs.append(f"{path}?checksum={checksum}")
        elif choice < 0.4:
            inputs.append(f"{path}?payload={b64_payload}")
        else:
            if random.random() < 0.5:
                inputs.append(f"{path}?payload={b64_payload}&checksum={checksum}")
            else:
                inputs.append(f"{path}?checksum={checksum}&payload={b64_payload}")
    return inputs

def test_fast_router_fuzz_equivalence():
    agent_executable = "/home/user/fast_router"
    oracle_executable = "/tests/fast_router_oracle"

    assert os.path.isfile(agent_executable), f"Agent executable {agent_executable} not found."
    assert os.access(agent_executable, os.X_OK), f"Agent executable {agent_executable} is not executable."
    assert os.path.isfile(oracle_executable), f"Oracle executable {oracle_executable} not found."

    inputs = generate_fuzz_inputs(500)

    for i, test_input in enumerate(inputs):
        oracle_proc = subprocess.run(
            [oracle_executable, test_input],
            capture_output=True,
            text=True
        )

        agent_proc = subprocess.run(
            [agent_executable, test_input],
            cwd="/home/user",
            capture_output=True,
            text=True
        )

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Exit code mismatch on input {i}: {test_input!r}\n"
            f"Oracle: {oracle_proc.returncode}\nAgent: {agent_proc.returncode}\n"
            f"Oracle stderr: {oracle_proc.stderr}\nAgent stderr: {agent_proc.stderr}"
        )

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Stdout mismatch on input {i}: {test_input!r}\n"
            f"Oracle stdout:\n{oracle_proc.stdout}\n"
            f"Agent stdout:\n{agent_proc.stdout}"
        )

        assert agent_proc.stderr == oracle_proc.stderr, (
            f"Stderr mismatch on input {i}: {test_input!r}\n"
            f"Oracle stderr:\n{oracle_proc.stderr}\n"
            f"Agent stderr:\n{agent_proc.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
