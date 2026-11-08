#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

ORACLE_PATH = "/app/oracle"
AGENT_BINARY = "/home/user/organizer/classifier"
MAKEFILE_PATH = "/home/user/organizer/Makefile"

def test_makefile_exists():
    assert os.path.isfile(MAKEFILE_PATH), f"Makefile not found at {MAKEFILE_PATH}"

def test_agent_binary_exists_and_executable():
    assert os.path.isfile(AGENT_BINARY), f"Compiled binary not found at {AGENT_BINARY}"
    assert os.access(AGENT_BINARY, os.X_OK), f"Binary at {AGENT_BINARY} is not executable"

def test_fuzz_equivalence():
    random.seed(42)

    for i in range(100):
        size = random.randint(1, 1000000)
        mask = random.randint(1, 1000000)
        id_val = random.randint(1, 1000000)

        args = [str(size), str(mask), str(id_val)]

        oracle_cmd = [ORACLE_PATH] + args
        agent_cmd = [AGENT_BINARY] + args

        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, check=True, timeout=5)
            oracle_out = oracle_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {args}: {e.stderr}")

        try:
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, check=True, timeout=5)
            agent_out = agent_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent binary failed on input {args}. Exit code: {e.returncode}. Stderr: {e.stderr}")

        assert agent_out == oracle_out, f"Mismatch on input {args}. Oracle: {oracle_out}, Agent: {agent_out}"

def test_memory_leaks():
    # Check if valgrind is available
    if subprocess.run(["which", "valgrind"], capture_output=True).returncode != 0:
        pytest.skip("valgrind not installed, skipping memory leak check")

    cmd = ["valgrind", "--leak-check=full", "--error-exitcode=1", AGENT_BINARY, "123", "456", "789"]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        assert res.returncode == 0, f"Memory leak detected by valgrind:\n{res.stderr}"
    except subprocess.TimeoutExpired:
        pytest.fail("Valgrind test timed out")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
