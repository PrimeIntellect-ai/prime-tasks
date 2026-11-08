#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import pytest

def generate_fuzz_input(num_lines=500):
    lines = []
    services = ["SVC-A", "SVC-B", "SVC-C", "SVC-X"]
    for _ in range(num_lines):
        if random.random() < 0.05:
            # Malformed line
            choice = random.choice([0, 1, 2])
            if choice == 0:
                lines.append(f"SVC-A|12345|0.1") # missing pipe
            elif choice == 1:
                lines.append(f"SVC-B|12345|0.1|msg|extra") # extra pipe
            else:
                lines.append(f"random garbage without pipes")
        else:
            svc = random.choice(services)
            raw_ts = random.randint(-1000, 2000000000)
            drift = random.uniform(-1.0, 1.0)
            msg_len = random.randint(10, 50)
            msg = ''.join(random.choices(string.ascii_letters + string.digits, k=msg_len))
            lines.append(f"{svc}|{raw_ts}|{drift:.6f}|{msg}")
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_reconstructor"
    agent_path = "/home/user/log_reconstructor"

    assert os.path.isfile(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent binary missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable"

    random.seed(42)
    iterations = 100
    lines_per_run = 500

    for i in range(iterations):
        input_data = generate_fuzz_input(lines_per_run)

        oracle_proc = subprocess.run([oracle_path], input=input_data, text=True, capture_output=True)
        agent_proc = subprocess.run([agent_path], input=input_data, text=True, capture_output=True)

        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr}"

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent program exited with non-zero status on iteration {i}.\nStderr: {agent_proc.stderr}\nInput:\n{input_data[:500]}...")

        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f"Output mismatch on iteration {i}.\n"
                f"Input (truncated):\n{input_data[:500]}\n"
                f"Expected Oracle Output (truncated):\n{oracle_proc.stdout[:500]}\n"
                f"Agent Output (truncated):\n{agent_proc.stdout[:500]}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
