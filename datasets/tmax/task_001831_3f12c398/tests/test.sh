#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import string
import subprocess
import pytest
from datetime import datetime, timedelta

AGENT_BIN = "/home/user/fixed-stitcher"
ORACLE_BIN = "/tests/log-stitcher-oracle"

def generate_fuzz_input(n=5000):
    random.seed(42)
    lines = []
    base_time = datetime(2023, 1, 1, 0, 0, 0)
    for _ in range(n):
        dt = base_time + timedelta(
            seconds=random.randint(0, 10000000),
            microseconds=random.randint(0, 999999)
        )

        fmt_choice = random.choice(["rfc3339", "rfc3339nano", "missing_fractional"])
        if fmt_choice == "rfc3339nano":
            ts = dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        else:
            ts = dt.strftime("%Y-%m-%dT%H:%M:%SZ")

        stream = random.choice(["stdout", "stderr"])
        msg = ''.join(random.choices(string.ascii_letters + string.digits + " ", k=random.randint(5, 40)))

        log_entry = {
            "time": ts,
            "stream": stream,
            "log": msg
        }
        lines.append(json.dumps(log_entry))

    return "\n".join(lines) + "\n"

def test_agent_binary_exists():
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary at {ORACLE_BIN} is not executable"

    input_data = generate_fuzz_input(5000)

    try:
        oracle_proc = subprocess.run(
            [ORACLE_BIN],
            input=input_data,
            capture_output=True,
            text=True,
            timeout=15
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Oracle binary timed out.")

    try:
        agent_proc = subprocess.run(
            [AGENT_BIN],
            input=input_data,
            capture_output=True,
            text=True,
            timeout=15
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Agent binary timed out.")

    assert agent_proc.returncode == oracle_proc.returncode, (
        f"Return code mismatch. Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}\n"
        f"Agent stderr: {agent_proc.stderr}"
    )

    if oracle_proc.stdout != agent_proc.stdout:
        oracle_lines = oracle_proc.stdout.splitlines()
        agent_lines = agent_proc.stdout.splitlines()

        diff_msg = "Output mismatch between oracle and agent.\n"
        if len(oracle_lines) != len(agent_lines):
            diff_msg += f"Line count differs: Oracle has {len(oracle_lines)}, Agent has {len(agent_lines)}.\n"

        for i, (oline, aline) in enumerate(zip(oracle_lines, agent_lines)):
            if oline != aline:
                diff_msg += f"First difference at line {i+1}:\nOracle: {oline}\nAgent:  {aline}\n"
                break

        pytest.fail(diff_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
