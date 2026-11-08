#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import string
import base64
import json
import hashlib
import pytest

ORACLE_PATH = "/app/legacy_auth"
AGENT_PATH = "/home/user/auth_migrator.py"
NUM_TESTS = 10000
SECRET = "Sup3rS3cr3t_R0tation_K3y!"

def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode('utf-8').rstrip('=')

def generate_random_string(length: int) -> str:
    charset = string.ascii_letters + string.digits + '.={}":,'
    return ''.join(random.choice(charset) for _ in range(length))

def generate_test_cases(n: int) -> list[str]:
    random.seed(42)
    cases = []

    sensitive_keys = ["password", "ssn", "credit_card", "normal_key", "user"]
    algs = ["none", "md5", "hs256", "rsa"]

    for i in range(n):
        category = random.random()

        if category < 0.10:
            # 10%: Pure random strings from charset
            cases.append(generate_random_string(random.randint(10, 500)))

        elif category < 0.20:
            # 10%: Malformed (wrong number of dots)
            parts = [generate_random_string(random.randint(5, 20)) for _ in range(random.choice([1, 2, 4, 5]))]
            cases.append(".".join(parts))

        elif category < 0.30:
            # 10%: Valid base64, invalid JSON
            h = b64url_encode(b"not json {")
            p = b64url_encode(b"also not json")
            cases.append(f"{h}.{p}.signature")

        else:
            # 70%: Valid JSON header and payload
            alg = random.choice(algs)
            header = {"alg": alg, "typ": "JWT"}

            # Generate random payload
            payload = {}
            for _ in range(random.randint(1, 5)):
                key = random.choice(sensitive_keys)
                payload[key] = generate_random_string(random.randint(5, 15))

            h_b64 = b64url_encode(json.dumps(header).encode())
            p_b64 = b64url_encode(json.dumps(payload).encode())

            if alg == "md5" and random.random() < 0.5:
                # 50% chance of valid signature if MD5
                sig_input = f"{h_b64}.{p_b64}{SECRET}".encode()
                sig = hashlib.md5(sig_input).hexdigest()
            else:
                # Invalid or random signature
                sig = generate_random_string(32)

            cases.append(f"{h_b64}.{p_b64}.{sig}")

    return cases

def run_cmd(cmd: list[str], input_arg: str) -> tuple[int, str, str]:
    try:
        result = subprocess.run(
            cmd + [input_arg],
            capture_output=True,
            text=True,
            timeout=2
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"

def test_auth_migrator_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing: {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary not executable: {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent script missing: {AGENT_PATH}"

    test_cases = generate_test_cases(NUM_TESTS)

    for i, token in enumerate(test_cases):
        oracle_code, oracle_out, oracle_err = run_cmd([ORACLE_PATH], token)
        agent_code, agent_out, agent_err = run_cmd(["python3", AGENT_PATH], token)

        error_msg = (
            f"Mismatch on input {i}:\n"
            f"Input Token: {token}\n"
            f"Oracle Code: {oracle_code} | Agent Code: {agent_code}\n"
            f"Oracle Stdout: {oracle_out!r}\n"
            f"Agent Stdout: {agent_out!r}\n"
            f"Oracle Stderr: {oracle_err!r}\n"
            f"Agent Stderr: {agent_err!r}\n"
        )

        assert oracle_code == agent_code, f"Exit code mismatch. {error_msg}"
        assert oracle_out == agent_out, f"Stdout mismatch. {error_msg}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
