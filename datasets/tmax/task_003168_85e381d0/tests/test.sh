#!/bin/bash
set -e
mkdir -p /logs/verifier
chmod +x /tests/oracle_filter

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import pytest

def test_agent_executable_exists():
    agent_path = "/home/user/filter"
    assert os.path.isfile(agent_path), f"Agent executable {agent_path} is missing."
    assert os.access(agent_path, os.X_OK), f"Agent executable {agent_path} is not executable."

def generate_fuzz_inputs(n=10000):
    random.seed(42)
    inputs = []
    token = b"X9vPq2"
    block = b"alert(1)"

    for _ in range(n):
        choice = random.random()
        if choice < 0.2:
            body = os.urandom(random.randint(0, 500))
            inputs.append(b"AUTH " + token + b"\n\n" + body)
        elif choice < 0.4:
            body1 = os.urandom(random.randint(0, 250))
            body2 = os.urandom(random.randint(0, 250))
            inputs.append(b"AUTH " + token + b"\n\n" + body1 + block + body2)
        elif choice < 0.6:
            wrong_token = os.urandom(6)
            body = os.urandom(random.randint(0, 500))
            inputs.append(b"AUTH " + wrong_token + b"\n\n" + body)
        elif choice < 0.8:
            val = os.urandom(random.randint(0, 500)).replace(b'\n', b'')
            if random.random() < 0.5:
                inputs.append(b"AUTH " + token + val)
            else:
                inputs.append(b"AUTH " + token + b"\n" + val)
        else:
            inputs.append(os.urandom(random.randint(0, 1000)))

    inputs.append(b"AUTH " + token)
    inputs.append(b"AUTH " + token + b"\n")
    inputs.append(b"AUTH " + token + b"\n\n")
    inputs.append(b"")
    return inputs

def test_fuzz_equivalence():
    agent_path = "/home/user/filter"
    oracle_path = "/tests/oracle_filter"

    assert os.path.isfile(agent_path), "Agent executable not found at /home/user/filter."
    assert os.path.isfile(oracle_path), "Oracle executable not found at /tests/oracle_filter."

    inputs = generate_fuzz_inputs(10000)

    for i, inp in enumerate(inputs):
        proc_oracle = subprocess.run([oracle_path], input=inp, capture_output=True)
        proc_agent = subprocess.run([agent_path], input=inp, capture_output=True)

        err_msg = (
            f"Mismatch on input {i} (len {len(inp)}).\n"
            f"Input preview: {inp[:100]}\n"
            f"Oracle exit code: {proc_oracle.returncode}, Agent exit code: {proc_agent.returncode}\n"
            f"Oracle stdout: {proc_oracle.stdout[:100]}\n"
            f"Agent stdout: {proc_agent.stdout[:100]}\n"
        )

        assert proc_oracle.returncode == proc_agent.returncode, err_msg
        assert proc_oracle.stdout == proc_agent.stdout, err_msg
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
