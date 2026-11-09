#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import hashlib
import subprocess
import pytest

ORACLE_PATH = "/tests/oracle_decoder"
AGENT_PATH = "/home/user/payload_decoder"

def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def encrypt_payload(plaintext: bytes, key_hex: str, iv_hex: str) -> str:
    # Use openssl to encrypt with AES-128-CBC
    cmd = [
        "openssl", "enc", "-aes-128-cbc",
        "-K", key_hex,
        "-iv", iv_hex
    ]
    result = subprocess.run(cmd, input=plaintext, capture_output=True, check=True)
    return result.stdout.hex()

def generate_test_cases(n=500, seed=42):
    random.seed(seed)
    cases = []

    salt = "S4LT_S3CR3T_99"
    key_hex = "7c5a9b8e2f1d4a6c3b8e9f0d1a2b3c4d"

    for i in range(n):
        case_type = random.random()

        if case_type < 0.10:
            # Malformed
            malform_type = random.choice(['no_body', 'no_cookie', 'no_token'])
            session_id = generate_random_string(16)
            token = hashlib.md5((session_id + salt).encode()).hexdigest()
            body = "1234567890abcdef"

            headers = ["POST / HTTP/1.1", "Host: localhost"]
            if malform_type != 'no_cookie':
                headers.append(f"Cookie: Session-ID={session_id}")
            if malform_type != 'no_token':
                headers.append(f"X-Ransom-Token: {token}")

            req = "\r\n".join(headers) + "\r\n\r\n"
            if malform_type != 'no_body':
                req += body

            cases.append(req)

        elif case_type < 0.50:
            # Invalid token
            session_id = generate_random_string(16)
            bad_token = generate_random_string(32).lower()
            body = "1234567890abcdef"

            headers = [
                "POST / HTTP/1.1",
                "Host: localhost",
                f"Cookie: Session-ID={session_id}",
                f"X-Ransom-Token: {bad_token}"
            ]
            req = "\r\n".join(headers) + "\r\n\r\n" + body
            cases.append(req)

        else:
            # Valid request
            session_id = generate_random_string(16)
            token = hashlib.md5((session_id + salt).encode()).hexdigest()

            plaintext = generate_random_string(random.randint(10, 100)).encode()
            iv_hex = hashlib.md5(session_id.encode()).hexdigest()

            body = encrypt_payload(plaintext, key_hex, iv_hex)

            headers = [
                "POST / HTTP/1.1",
                "Host: localhost",
                f"Cookie: Session-ID={session_id}",
                f"X-Ransom-Token: {token}"
            ]
            req = "\r\n".join(headers) + "\r\n\r\n" + body
            cases.append(req)

    return cases

def run_executable(path, input_data):
    try:
        result = subprocess.run(
            [path],
            input=input_data.encode('utf-8'),
            capture_output=True,
            timeout=2
        )
        return result.stdout.decode('utf-8', errors='replace')
    except subprocess.TimeoutExpired:
        return "<TIMEOUT>"
    except Exception as e:
        return f"<ERROR: {e}>"

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script at {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"

    test_cases = generate_test_cases(500)

    for i, req in enumerate(test_cases):
        oracle_out = run_executable(ORACLE_PATH, req)
        agent_out = run_executable(AGENT_PATH, req)

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on test case {i+1}!\n\n"
                f"INPUT HTTP REQUEST:\n{req}\n\n"
                f"EXPECTED OUTPUT (Oracle):\n{oracle_out}\n\n"
                f"ACTUAL OUTPUT (Agent):\n{agent_out}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
