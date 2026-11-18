#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_loglocker_fixed_and_installed():
    # Check if loglocker is installed and works
    script = """
import loglocker
with loglocker.Lock("test_lock"):
    print("Locked successfully")
"""
    result = subprocess.run(
        ["python3", "-c", script],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"loglocker failed to acquire lock. Stderr: {result.stderr}"
    assert "Locked successfully" in result.stdout

def generate_random_log_stream(seed):
    random.seed(seed)
    num_lines = random.randint(10, 1000)
    formats = [
        "[INFO] User logged in from {ipv4}",
        "[DEBUG] Connection timeout at {timestamp}",
        "System error code 500",
        "[WARN] Access denied for {ipv4}"
    ]

    lines = []
    for _ in range(num_lines):
        fmt = random.choice(formats)
        ipv4 = f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 255)}"
        timestamp = f"2023-10-27T{random.randint(0,23):02d}:{random.randint(0,59):02d}:{random.randint(0,59):02d}Z"
        line = fmt.replace("{ipv4}", ipv4).replace("{timestamp}", timestamp)
        lines.append(line)

    # Sometimes add trailing newline, sometimes don't
    if random.choice([True, False]):
        return "\n".join(lines) + "\n"
    return "\n".join(lines)

@pytest.mark.parametrize("seed", range(50))
def test_fuzz_equivalence(seed):
    agent_script = "/home/user/incremental_pack.py"
    oracle_script = "/tests/incremental_pack"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script not found at {oracle_script}"

    input_data = generate_random_log_stream(seed)

    # Run oracle, which is uploaded only at verification time
    oracle_proc = subprocess.run(
        ["python3", oracle_script],
        input=input_data.encode('utf-8'),
        capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed: {oracle_proc.stderr}"

    # Run agent
    agent_proc = subprocess.run(
        ["python3", agent_script],
        input=input_data.encode('utf-8'),
        capture_output=True
    )
    assert agent_proc.returncode == 0, f"Agent script failed: {agent_proc.stderr}"

    assert agent_proc.stdout == oracle_proc.stdout, (
        f"Output mismatch for seed {seed}.\n"
        f"Input length: {len(input_data)}\n"
        f"Oracle output length: {len(oracle_proc.stdout)}\n"
        f"Agent output length: {len(agent_proc.stdout)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
