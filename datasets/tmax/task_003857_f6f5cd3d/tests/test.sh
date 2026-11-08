#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

ORACLE_PATH = "/tests/oracle_eval"
AGENT_SCRIPT = "/home/user/health_eval.sh"

def test_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script at {AGENT_SCRIPT} is not executable"

def run_script(executable, args):
    cmd = [executable] + args
    if executable.endswith(".sh") or executable == ORACLE_PATH:
        cmd = ["bash", executable] + args
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout.strip()

def test_fuzz_equivalence():
    random.seed(42)
    interfaces = ["eth0", "eth1", "vpn_main", "vpn0", "ens33", "lo", "wg0", "randomstr"]
    statuses = ["UP", "DOWN", "UNKNOWN", "FLAPPING"]

    # Generate 2000 random inputs
    for _ in range(2000):
        arg1 = random.choice(interfaces)
        arg2 = random.choice(statuses)
        arg3 = str(random.randint(0, 200))

        args = [arg1, arg2, arg3]

        oracle_out = run_script(ORACLE_PATH, args)
        agent_out = run_script(AGENT_SCRIPT, args)

        assert oracle_out == agent_out, (
            f"Output mismatch for args {args}.\n"
            f"Oracle: '{oracle_out}'\n"
            f"Agent: '{agent_out}'"
        )

def test_missing_arguments():
    # Test with fewer than 3 arguments
    test_cases = [
        [],
        ["eth0"],
        ["eth0", "UP"]
    ]
    for args in test_cases:
        oracle_out = run_script(ORACLE_PATH, args)
        agent_out = run_script(AGENT_SCRIPT, args)

        assert oracle_out == agent_out, (
            f"Output mismatch for missing args {args}.\n"
            f"Oracle: '{oracle_out}'\n"
            f"Agent: '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
