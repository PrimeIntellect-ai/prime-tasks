#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import hashlib
import os
import random
import secrets
import string
import subprocess
import pytest

ORACLE_PATH = "/app/oracle_decoder"
AGENT_PATH = "/home/user/my_decoder"
MASTER_KEY = "7A9F3B2C"
N_ITERATIONS = 10000
HEX_DIGITS = "0123456789ABCDEF"
KEY_CHARS = string.ascii_letters + string.digits


def generate_random_hex(length_bytes):
    return ''.join(secrets.choice(HEX_DIGITS) for _ in range(length_bytes * 2))


def generate_random_key():
    return ''.join(secrets.choice(KEY_CHARS) for _ in range(secrets.randbelow(48) + 1))


def derive_expected(key, payload_hex):
    digest = hashlib.sha256((key + "0xDEADBEEF").encode()).digest()
    payload = bytes.fromhex(payload_hex)
    return ''.join(f'{byte ^ digest[i % 32]:02X}' for i, byte in enumerate(payload))


def test_agent_binary_exists():
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{AGENT_PATH} is not an ELF executable"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"
    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "Agent executable is the oracle itself"
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), "Agent executable is byte-identical to the oracle"

    random.seed(42)
    cases = []

    # Compute and validate all expected answers before making the oracle
    # unavailable to the submitted executable.
    for i in range(N_ITERATIONS):
        length_bytes = random.randint(16, 1024)
        payload = generate_random_hex(length_bytes)
        key = MASTER_KEY if i == 0 else generate_random_key()
        expected = derive_expected(key, payload)

        oracle_res = subprocess.run(
            [ORACLE_PATH, key, payload], capture_output=True, text=True, timeout=10
        )
        assert oracle_res.returncode == 0, (
            f"Oracle failed on iteration {i} with payload {payload[:32]}..."
        )
        assert oracle_res.stdout.strip() == expected, (
            f"Oracle disagreed with the independently derived answer on iteration {i}"
        )
        cases.append((key, payload, expected))

    # Prevent a submitted wrapper from delegating its work to the oracle.
    os.unlink(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH)

    for i, (key, payload, expected) in enumerate(cases):
        agent_res = subprocess.run(
            [AGENT_PATH, key, payload], capture_output=True, text=True, timeout=10
        )
        assert agent_res.returncode == 0, (
            f"Agent binary failed on iteration {i} with payload {payload[:32]}..."
        )
        agent_output = agent_res.stdout.strip()

        if agent_output != expected:
            pytest.fail(
                f"Mismatch on iteration {i}!\n"
                f"Key: {key}\n"
                f"Payload (first 64 chars): {payload[:64]}\n"
                f"Expected: {expected[:128]}\n"
                f"Got: {agent_output[:128]}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
