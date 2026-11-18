#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import subprocess
import pytest

def generate_random_fuzz_data(n=500):
    """Generate N random JSON-lines inputs according to the truth distribution."""
    random.seed(42)
    levels = ["INFO", "WARNING", "CRITICAL", "ERROR"]

    lines = []
    for _ in range(n):
        log_id = "".join(random.choices("0123456789abcdef", k=8))
        ip = f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"

        msg_len = random.randint(10, 50)
        msg_chars = []
        for _ in range(msg_len):
            choice = random.random()
            if choice < 0.8:
                msg_chars.append(random.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 "))
            else:
                msg_chars.append(chr(random.randint(0x0100, 0x27FF)))

        message = "".join(msg_chars)
        level = random.choice(levels)
        obj = {
            "log_id": log_id,
            "ip": ip,
            "message": message,
            "level": level
        }
        lines.append(json.dumps(obj, ensure_ascii=True))

    return "\n".join(lines) + "\n"

def test_script_exists_and_executable():
    """Check if the agent script exists and is executable."""
    agent_script = "/home/user/process_logs.sh"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable"

def test_fuzz_equivalence():
    """Run both the oracle and agent scripts and assert exact output equivalence."""
    agent_script = "/home/user/process_logs.sh"
    oracle_script = "/tests/oracle_process.sh"

    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}"

    fuzz_input = generate_random_fuzz_data(500)

    oracle_proc = subprocess.run(
        ["bash", oracle_script],
        input=fuzz_input,
        text=True,
        capture_output=True,
        check=False
    )
    assert oracle_proc.returncode == 0, f"Oracle script failed with error:\n{oracle_proc.stderr}"

    agent_proc = subprocess.run(
        [agent_script],
        input=fuzz_input,
        text=True,
        capture_output=True,
        check=False
    )
    assert agent_proc.returncode == 0, f"Agent script failed with error:\n{agent_proc.stderr}"

    oracle_lines = [line for line in oracle_proc.stdout.split("\n") if line]
    agent_lines = [line for line in agent_proc.stdout.split("\n") if line]

    assert len(agent_lines) == len(oracle_lines), (
        f"Output line count mismatch. Expected {len(oracle_lines)} lines, got {len(agent_lines)} lines.\n"
        f"Ensure non-CRITICAL logs are dropped and no extra output is printed."
    )

    for i, (expected, actual) in enumerate(zip(oracle_lines, agent_lines)):
        assert expected == actual, (
            f"Mismatch at output line {i+1}:\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}\n"
            f"Check anonymization, unicode decoding, incident code, and formatting."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
