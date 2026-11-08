#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import sys

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_processor.py"
    agent_path = "/home/user/analyze_signal"

    assert os.path.exists(oracle_path), f"Oracle program missing at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent program missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent program {agent_path} is not executable"

    random.seed(42)
    n_tests = 500
    seq_length = 128

    for i in range(n_tests):
        # Generate random sequence of 128 floats between -10.0 and 10.0
        seq = [random.uniform(-10.0, 10.0) for _ in range(seq_length)]
        input_str = ",".join(f"{val:.6f}" for val in seq)

        # Run oracle
        oracle_cmd = [sys.executable, oracle_path, input_str]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on iteration {i}. Stderr: {oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = [agent_path, input_str]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent program failed on iteration {i}. Stderr: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        # Compare outputs
        assert oracle_out == agent_out, (
            f"Output mismatch on iteration {i}!\n"
            f"Input: {input_str}\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output: {repr(agent_out)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
