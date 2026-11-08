#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import pytest

def generate_random_input(seed):
    random.seed(seed)
    length = random.randint(2000, 15000)
    out = bytearray()

    while len(out) < length:
        rand_val = random.random()
        if rand_val < 0.1:
            # Inject valid pattern: [A-Z]{4}-[0-9]{4}:[0-9]{1,5}
            letters = "".join(random.choices(string.ascii_uppercase, k=4))
            digits1 = "".join(random.choices(string.digits, k=4))
            digits2 = "".join(random.choices(string.digits, k=random.randint(1, 5)))
            pattern = f"{letters}-{digits1}:{digits2}".encode('ascii')
            out.extend(pattern)
        elif rand_val < 0.2:
            # Inject decoy pattern: [0-9]{4}-[A-Z]{4}:[0-9]{1,5}
            digits1 = "".join(random.choices(string.digits, k=4))
            letters = "".join(random.choices(string.ascii_uppercase, k=4))
            digits2 = "".join(random.choices(string.digits, k=random.randint(1, 5)))
            pattern = f"{digits1}-{letters}:{digits2}".encode('ascii')
            out.extend(pattern)
        else:
            # Random byte
            out.append(random.randint(0, 255))

    return bytes(out)

def test_wal_recover_script_exists_and_executable():
    agent_script = "/home/user/wal_recover.sh"
    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(agent_script), f"{agent_script} is not a file."
    assert os.access(agent_script, os.X_OK), f"{agent_script} is not executable."

def test_fuzz_equivalence():
    agent_script = "/home/user/wal_recover.sh"
    oracle_script = "/tests/oracle_wal_recover.sh"

    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} is missing."

    for i in range(50):
        test_input = generate_random_input(i)

        oracle_proc = subprocess.run(["/bin/bash", oracle_script], input=test_input, capture_output=True)
        agent_proc = subprocess.run(["/bin/bash", agent_script], input=test_input, capture_output=True)

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on random input {i}.\n"
            f"Expected output length: {len(oracle_proc.stdout)}\n"
            f"Actual output length: {len(agent_proc.stdout)}\n"
            f"Expected head: {oracle_proc.stdout[:100]}\n"
            f"Actual head: {agent_proc.stdout[:100]}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
