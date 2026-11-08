#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import string
import binascii
import hmac
import hashlib
import pytest

KEY = b'CorpPolicySecuXY'
ORACLE_PATH = "/tests/oracle.py"
AGENT_SCRIPT = "/home/user/verify_payload.sh"

def generate_fuzz_inputs(n=200, seed=42):
    random.seed(seed)
    inputs = []

    # 20% invalid length or non-hex
    for _ in range(int(n * 0.2)):
        if random.choice([True, False]):
            # non-hex
            s = ''.join(random.choices(string.ascii_letters + string.digits + string.punctuation, k=random.randint(10, 100)))
            inputs.append(s)
        else:
            # hex but length < 128 chars (64 bytes)
            s = ''.join(random.choices(string.hexdigits, k=random.randint(10, 126)))
            inputs.append(s)

    # 30% valid hex, len >= 64, bad HMAC
    for _ in range(int(n * 0.3)):
        length = random.randint(64, 100) * 2
        s = ''.join(random.choices(string.hexdigits, k=length))
        inputs.append(s)

    # 25% valid HMAC, but corrupted ciphertext (padding errors)
    for _ in range(int(n * 0.25)):
        iv = bytes(random.choices(range(256), k=16))
        # Random bytes for ciphertext will almost certainly fail padding
        ciphertext = bytes(random.choices(range(256), k=random.randint(1, 4) * 16))
        mac = hmac.new(KEY, iv + ciphertext, hashlib.sha256).digest()
        payload = iv + mac + ciphertext
        inputs.append(binascii.hexlify(payload).decode('utf-8'))

    # 25% perfectly valid payloads
    for _ in range(int(n * 0.25)):
        iv = bytes(random.choices(range(256), k=16))
        plaintext = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(1, 50))).encode('utf-8')

        hex_key = binascii.hexlify(KEY).decode('utf-8')
        hex_iv = binascii.hexlify(iv).decode('utf-8')

        p = subprocess.run(
            ['openssl', 'enc', '-aes-128-cbc', '-K', hex_key, '-iv', hex_iv],
            input=plaintext,
            capture_output=True,
            check=True
        )
        ciphertext = p.stdout
        mac = hmac.new(KEY, iv + ciphertext, hashlib.sha256).digest()
        payload = iv + mac + ciphertext
        inputs.append(binascii.hexlify(payload).decode('utf-8'))

    random.shuffle(inputs)
    return inputs

def test_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK) or os.access(AGENT_SCRIPT, os.R_OK), f"Agent script is not readable/executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"

    inputs = generate_fuzz_inputs(n=200, seed=1337)

    for idx, payload_hex in enumerate(inputs):
        oracle_proc = subprocess.run(
            ["python3", ORACLE_PATH, payload_hex],
            capture_output=True
        )

        agent_proc = subprocess.run(
            ["bash", AGENT_SCRIPT, payload_hex],
            capture_output=True
        )

        assert oracle_proc.returncode == agent_proc.returncode, (
            f"Return code mismatch on input {idx}!\n"
            f"Input: {payload_hex}\n"
            f"Oracle returncode: {oracle_proc.returncode}\n"
            f"Agent returncode: {agent_proc.returncode}\n"
            f"Oracle stdout: {oracle_proc.stdout!r}\n"
            f"Agent stdout: {agent_proc.stdout!r}"
        )

        assert oracle_proc.stdout == agent_proc.stdout, (
            f"Stdout mismatch on input {idx}!\n"
            f"Input: {payload_hex}\n"
            f"Oracle stdout: {oracle_proc.stdout!r}\n"
            f"Agent stdout: {agent_proc.stdout!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
