#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_agent_binary_exists():
    agent_path = "/home/user/bin/feature_extractor"
    assert os.path.isfile(agent_path), f"Agent binary not found exactly at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable"

def test_training_features_exists():
    out_path = "/home/user/training_features.csv"
    assert os.path.isfile(out_path), f"Final output missing at {out_path}"
    with open(out_path, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, f"Final output at {out_path} is empty"

def test_fuzz_equivalence():
    oracle_path = "/tests/feature_extractor_oracle"
    agent_path = "/home/user/bin/feature_extractor"

    assert os.path.isfile(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent binary missing at {agent_path}"

    random.seed(42)
    iterations = 20

    for i in range(iterations):
        num_lines = random.randint(50, 1000)
        input_lines = []
        for _ in range(num_lines):
            col1 = random.uniform(0.0, 255.0)
            col2 = random.uniform(10.0, 150.0)
            input_lines.append(f"{col1:.6f},{col2:.6f}")

        input_data = "\n".join(input_lines) + "\n"

        oracle_proc = subprocess.run([oracle_path], input=input_data, text=True, capture_output=True)
        agent_proc = subprocess.run([agent_path], input=input_data, text=True, capture_output=True)

        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i} with error: {oracle_proc.stderr}"
        assert agent_proc.returncode == 0, f"Agent program failed on iteration {i} with error: {agent_proc.stderr}"

        oracle_out = oracle_proc.stdout
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            input_sample = "\n".join(input_lines[:5])
            oracle_sample = "\n".join(oracle_out.splitlines()[:5])
            agent_sample = "\n".join(agent_out.splitlines()[:5])

            error_msg = (
                f"Mismatch on fuzz iteration {i}.\n\n"
                f"Input data sample (first 5 lines):\n{input_sample}\n...\n\n"
                f"Oracle output sample (first 5 lines):\n{oracle_sample}\n...\n\n"
                f"Agent output sample (first 5 lines):\n{agent_sample}\n...\n"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
