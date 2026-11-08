#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import base64
import subprocess
import pytest

def generate_valid_token():
    L = random.randint(0, 80)
    payload = bytes([random.randint(0, 255) for _ in range(L)])
    decoded = bytearray([0xCA, 0xFE, L])
    decoded.extend(payload)
    chk = 0x5A
    for b in decoded:
        chk ^= b
    decoded.append(chk)
    return base64.b64encode(decoded).decode('utf-8')

def generate_invalid_token():
    corruption_type = random.choice(['bad_b64', 'bad_magic', 'bad_len', 'bad_chk', 'trunc', 'random_bytes'])
    if corruption_type == 'bad_b64':
        return "Not_A_Base64_String!@#" + str(random.randint(0, 1000))
    elif corruption_type == 'random_bytes':
        return base64.b64encode(bytes([random.randint(0, 255) for _ in range(random.randint(1, 100))])).decode('utf-8')
    else:
        L = random.randint(0, 80)
        payload = bytes([random.randint(0, 255) for _ in range(L)])
        decoded = bytearray([0xCA, 0xFE, L])
        decoded.extend(payload)
        chk = 0x5A
        for b in decoded:
            chk ^= b
        decoded.append(chk)

        if corruption_type == 'bad_magic':
            decoded[0] = 0xCB
        elif corruption_type == 'bad_len':
            decoded[2] = (L + 1) % 256
        elif corruption_type == 'bad_chk':
            decoded[-1] = (chk + 1) % 256
        elif corruption_type == 'trunc':
            decoded = decoded[:-2]
            if len(decoded) == 0:
                decoded = bytearray([0xCA])

        return base64.b64encode(decoded).decode('utf-8')

def get_fuzz_inputs(n):
    random.seed(42)
    inputs = []
    for _ in range(n // 2):
        inputs.append(generate_valid_token())
    for _ in range(n - n // 2):
        inputs.append(generate_invalid_token())
    random.shuffle(inputs)
    return inputs

def test_fuzz_equivalence():
    oracle_path = "/app/waf_auth_filter"
    agent_path = "/home/user/token_decoder.py"

    assert os.path.exists(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent script not found at {agent_path}"

    # We will use 10,000 inputs as specified in the truth
    inputs = get_fuzz_inputs(10000)

    for i, b64_input in enumerate(inputs):
        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_path, b64_input],
                capture_output=True,
                timeout=1
            )
            oracle_out = oracle_proc.stdout
            oracle_code = oracle_proc.returncode
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input: {b64_input}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                ["python3", agent_path, b64_input],
                capture_output=True,
                timeout=1
            )
            agent_out = agent_proc.stdout
            agent_code = agent_proc.returncode
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent timed out on input: {b64_input}")

        assert agent_code == oracle_code, (
            f"Exit code mismatch on input {b64_input}\n"
            f"Oracle exited with {oracle_code}, Agent exited with {agent_code}\n"
            f"Oracle stdout: {oracle_out!r}\n"
            f"Agent stdout: {agent_out!r}"
        )

        assert agent_out == oracle_out, (
            f"Stdout mismatch on input {b64_input}\n"
            f"Oracle stdout: {oracle_out!r}\n"
            f"Agent stdout: {agent_out!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
