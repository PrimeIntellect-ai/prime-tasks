#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/safe_parser.py"
ORACLE_SCRIPT = "/tests/oracle_safe_parser.py"
MAGIC_HEADER = b"Z3R0_D4Y_P4YL04D\n"

def generate_fuzz_inputs(n=100):
    random.seed(42)
    inputs = []
    for i in range(n):
        if i % 2 == 0:
            # 50% valid inputs
            payload_len = random.randint(1, 200)
            payload = bytes([random.randint(0, 255) for _ in range(payload_len)])
            inputs.append(MAGIC_HEADER + payload)
        else:
            # 50% invalid inputs
            if random.random() < 0.5:
                # Malformed header (e.g. missing newline or wrong char)
                malformed = bytearray(MAGIC_HEADER)
                malformed[random.randint(0, len(malformed)-1)] ^= 0x01
                payload_len = random.randint(1, 200)
                payload = bytes([random.randint(0, 255) for _ in range(payload_len)])
                inputs.append(bytes(malformed) + payload)
            else:
                # Completely random string
                header_len = random.randint(5, 20)
                header = "".join(random.choices(string.ascii_letters + string.digits, k=header_len)).encode()
                payload_len = random.randint(1, 200)
                payload = bytes([random.randint(0, 255) for _ in range(payload_len)])
                inputs.append(header + b"\n" + payload)
    return inputs

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), f"Missing {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_SCRIPT), f"Missing {ORACLE_SCRIPT}"

    inputs = generate_fuzz_inputs(100)

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, "fuzz_input.bin")

        for idx, data in enumerate(inputs):
            with open(input_path, "wb") as f:
                f.write(data)

            # Run Oracle
            oracle_proc = subprocess.run(
                ["python3", ORACLE_SCRIPT, input_path],
                capture_output=True
            )

            # Run Agent
            agent_proc = subprocess.run(
                ["python3", AGENT_SCRIPT, input_path],
                capture_output=True
            )

            # Compare return codes
            assert agent_proc.returncode == oracle_proc.returncode, (
                f"Return code mismatch on input {idx}.\n"
                f"Input data (hex): {data.hex()}\n"
                f"Oracle return code: {oracle_proc.returncode}\n"
                f"Agent return code: {agent_proc.returncode}\n"
                f"Oracle stdout: {oracle_proc.stdout}\n"
                f"Agent stdout: {agent_proc.stdout}\n"
                f"Agent stderr: {agent_proc.stderr}"
            )

            # Compare stdout
            assert agent_proc.stdout == oracle_proc.stdout, (
                f"Stdout mismatch on input {idx}.\n"
                f"Input data (hex): {data.hex()}\n"
                f"Oracle stdout (hex): {oracle_proc.stdout.hex()}\n"
                f"Agent stdout (hex): {agent_proc.stdout.hex()}\n"
                f"Agent stderr: {agent_proc.stderr}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
