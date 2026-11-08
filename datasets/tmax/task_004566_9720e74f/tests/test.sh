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
import hashlib
import pytest
import sys

def generate_fuzz_inputs(n=10000):
    random.seed(42)
    inputs = []
    for _ in range(n):
        r = random.random()
        if r < 0.1:
            # 10% completely random hex strings (might have odd length, etc.)
            length = random.randint(10, 100)
            inputs.append(''.join(random.choices('0123456789abcdef', k=length)))
        elif r < 0.3:
            # 20% hex-encoded invalid UTF-8 bytes
            b = bytes(random.randint(128, 255) for _ in range(20))
            inputs.append(b.hex())
        elif r < 0.6:
            # 30% valid UTF-8 HTTP requests missing headers or with wrong Certs
            req = "GET / HTTP/1.1\r\n"
            if random.random() < 0.5:
                req += "Cookie: other=123\r\n"
            if random.random() < 0.5:
                req += "X-Cert-Chain: CN=User\r\n"
            req += "\r\n"
            inputs.append(req.encode('utf-8').hex())
        else:
            # 40% perfectly formed HTTP requests
            req = "GET / HTTP/1.1\r\n"

            # Generate cert
            if random.random() < 0.2:
                cert = "CN=Admin" + ''.join(random.choices(string.ascii_letters, k=10))
            else:
                # Valid cert ending with 'f' in MD5
                while True:
                    cert = "CN=Admin" + ''.join(random.choices(string.ascii_letters, k=10))
                    if hashlib.md5(cert.encode('utf-8')).hexdigest().endswith('f'):
                        break

            req += f"X-Cert-Chain: {cert}\r\n"

            # Generate session
            if random.random() < 0.2:
                session = "invalid_base64!@#"
            else:
                if random.random() < 0.5:
                    dec_text = "SECURE_DEV_" + ''.join(random.choices(string.ascii_letters, k=10))
                else:
                    dec_text = "OTHER_PREFIX_" + ''.join(random.choices(string.ascii_letters, k=10))

                if random.random() < 0.1:
                    # Decrypts to invalid UTF-8
                    enc_bytes = bytes([b ^ 85 for b in bytes([255, 254, 253])])
                else:
                    enc_bytes = bytes([b ^ 85 for b in dec_text.encode('utf-8')])

                session = base64.b64encode(enc_bytes).decode('utf-8')

            req += f"Cookie: session={session}\r\n\r\n"
            inputs.append(req.encode('utf-8').hex())

    return inputs

def test_agent_script_exists_and_executable():
    agent_path = '/home/user/auth_analyzer.py'
    assert os.path.isfile(agent_path), f"Agent script missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent script at {agent_path} is not executable"

def test_fuzz_equivalence():
    agent_path = '/home/user/auth_analyzer.py'
    oracle_path = '/tests/oracle_analyzer.py'

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"

    inputs = generate_fuzz_inputs(1000)  # Using 1000 to avoid excessive test execution time while maintaining coverage

    for idx, hex_input in enumerate(inputs):
        # Run verification-only oracle uploaded after the agent has finished.
        oracle_proc = subprocess.run(
            [sys.executable, oracle_path, hex_input],
            capture_output=True,
            text=True
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            [agent_path, hex_input],
            capture_output=True,
            text=True
        )
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on input #{idx}!\n"
            f"Input (hex): {hex_input}\n"
            f"Oracle Output: {oracle_out}\n"
            f"Agent Output:  {agent_out}\n"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
