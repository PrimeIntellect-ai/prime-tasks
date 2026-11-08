#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import base64
import random
import string
import subprocess
import pytest

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')

def generate_fuzz_inputs(n=10000):
    random.seed(42)
    inputs = []
    for _ in range(n):
        r = random.random()
        if r < 0.4:
            # 40% valid JSON, alg=none
            header = {"alg": random.choice(["none", "None", "NONE", "nOnE"])}
            payload = {"claim1": random.randint(1, 10000)}
            if random.random() < 0.5:
                payload["role"] = "admin"
            else:
                payload["role"] = random.choice(["user", "guest", "moderator"])

            token = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}."
            inputs.append(token)
        elif r < 0.8:
            # 40% valid JSON, alg=HS256
            header = {"alg": "HS256"}
            payload = {"claim2": "".join(random.choices(string.ascii_letters, k=10))}
            if random.random() < 0.5:
                payload["role"] = "admin"
            token = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}.{b64url(b'fakesig')}"
            inputs.append(token)
        else:
            # 20% completely malformed garbage strings
            length = random.randint(10, 500)
            chars = string.ascii_letters + string.digits + "-_." + "{}\" :"
            garbage = "".join(random.choice(chars) for _ in range(length))
            inputs.append(garbage)
    return inputs

def test_fuzz_equivalence():
    agent_binary = "/home/user/token_analyzer"
    oracle_binary = "/tests/token_analyzer_oracle"

    assert os.path.isfile(agent_binary), f"Agent binary not found at {agent_binary}"
    assert os.access(agent_binary, os.X_OK), f"Agent binary is not executable: {agent_binary}"

    assert os.path.isfile(oracle_binary), f"Oracle binary not found at {oracle_binary}"
    assert os.access(oracle_binary, os.X_OK), f"Oracle binary is not executable: {oracle_binary}"

    inputs = generate_fuzz_inputs(10000)

    for i, token in enumerate(inputs):
        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_binary, token],
            capture_output=True,
            text=True
        )

        # Run agent
        agent_proc = subprocess.run(
            [agent_binary, token],
            capture_output=True,
            text=True
        )

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Exit code mismatch on input {i}:\n"
            f"Input token: {token}\n"
            f"Oracle exit code: {oracle_proc.returncode}\n"
            f"Agent exit code: {agent_proc.returncode}\n"
            f"Oracle stdout: {oracle_proc.stdout!r}\n"
            f"Agent stdout: {agent_proc.stdout!r}"
        )

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Stdout mismatch on input {i}:\n"
            f"Input token: {token}\n"
            f"Oracle stdout: {oracle_proc.stdout!r}\n"
            f"Agent stdout: {agent_proc.stdout!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
