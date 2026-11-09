#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import pytest


def test_peak_frame():
    path = "/home/user/peak_frame.txt"
    assert os.path.exists(path), f"Expected file {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "4", f"Expected peak frame to be 4, but got '{content}'."


def test_signal_analyzer_fuzz_equivalence():
    agent_path = "/home/user/signal_analyzer"
    oracle_path = "/tests/oracle_analyzer"

    assert os.path.exists(agent_path), f"Agent program {agent_path} is missing."
    assert os.access(agent_path, os.X_OK), f"Agent program {agent_path} is not executable."
    assert os.path.exists(oracle_path), f"Oracle program {oracle_path} is missing."
    assert os.access(oracle_path, os.X_OK), f"Oracle program {oracle_path} is not executable."

    random.seed(42)

    for i in range(100):
        length = random.randint(10, 100)
        nums = [random.uniform(-100.0, 100.0) for _ in range(length)]
        input_str = ",".join(f"{x:.4f}" for x in nums)

        oracle_proc = subprocess.run(
            [oracle_path],
            input=input_str,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on run {i+1}."
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            [agent_path],
            input=input_str,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent program failed (exit code {agent_proc.returncode}) on run {i+1}.\nInput: {input_str}\nStderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch on run {i+1}.\n"
            f"Input length: {length}\n"
            f"Input preview: {input_str[:100]}...\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
