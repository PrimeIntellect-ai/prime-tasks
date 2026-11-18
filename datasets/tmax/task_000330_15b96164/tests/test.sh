#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import struct
import tempfile
import pytest

ORACLE_PATH = "/tests/oracle_vm"
AGENT_SCRIPT = "/home/user/run_vm.sh"
NUM_FUZZ_ITERATIONS = 1000

def generate_random_bytecode():
    """Generates a random sequence of valid VM instructions."""
    opcodes = [0x01, 0x02, 0x10, 0x11, 0x12, 0x13]
    num_instructions = random.randint(5, 50)
    bytecode = bytearray()

    # Ensure at least some SETs and PRINTs
    bytecode.extend(struct.pack("BBBB", 0x01, 0, 0, 0))
    bytecode.extend(b"Initial\0")

    for _ in range(num_instructions):
        op = random.choice(opcodes)
        regA = random.randint(0, 15)
        regB = random.randint(0, 15)
        regC = random.randint(0, 15)

        bytecode.extend(struct.pack("BBBB", op, regA, regB, regC))

        if op == 0x01:
            length = random.randint(1, 20)
            charset = string.ascii_letters + string.digits + string.punctuation + " "
            s = ''.join(random.choices(charset, k=length))
            bytecode.extend(s.encode('ascii'))
            bytecode.append(0)

    # Add a final print
    bytecode.extend(struct.pack("BBBB", 0x02, random.randint(0, 15), 0, 0))
    return bytecode

def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"{AGENT_SCRIPT} is not executable"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle not executable at {ORACLE_PATH}"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(NUM_FUZZ_ITERATIONS):
            bytecode = generate_random_bytecode()
            input_file = os.path.join(tmpdir, f"input_{i}.bin")

            with open(input_file, "wb") as f:
                f.write(bytecode)

            oracle_proc = subprocess.run(
                [ORACLE_PATH, input_file],
                capture_output=True,
                text=True
            )

            agent_proc = subprocess.run(
                [AGENT_SCRIPT, input_file],
                capture_output=True,
                text=True
            )

            assert agent_proc.returncode == oracle_proc.returncode, \
                f"Return code mismatch on iteration {i}.\nOracle: {oracle_proc.returncode}\nAgent: {agent_proc.returncode}"

            assert agent_proc.stdout == oracle_proc.stdout, \
                f"Stdout mismatch on iteration {i}.\nOracle stdout:\n{oracle_proc.stdout}\nAgent stdout:\n{agent_proc.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
