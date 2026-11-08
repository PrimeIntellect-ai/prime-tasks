#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import tempfile
import pytest

ORACLE_PATH = "/tests/oracle_etl.sh"
AGENT_PATH = "/home/user/etl_transform.sh"

def generate_csv(filepath, rows, id_range, val_range):
    with open(filepath, 'w') as f:
        for _ in range(rows):
            id_val = random.randint(*id_range)
            val1 = random.uniform(*val_range)
            val2 = random.uniform(*val_range)
            f.write(f"{id_val},{val1:.6f},{val2:.6f}\n")

def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    random.seed(42)
    iterations = 30
    rows_per_file = 5000
    id_range = (1, 10000)
    val_range = (-100.0, 100.0)

    for i in range(iterations):
        with tempfile.TemporaryDirectory() as tmpdir:
            alpha = os.path.join(tmpdir, "alpha.csv")
            beta = os.path.join(tmpdir, "beta.csv")
            gamma = os.path.join(tmpdir, "gamma.csv")

            generate_csv(alpha, rows_per_file, id_range, val_range)
            generate_csv(beta, rows_per_file, id_range, val_range)
            generate_csv(gamma, rows_per_file, id_range, val_range)

            oracle_cmd = ["bash", ORACLE_PATH, alpha, beta, gamma]
            agent_cmd = [AGENT_PATH, alpha, beta, gamma]

            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert oracle_res.returncode == 0, f"Oracle failed on iteration {i+1}: {oracle_res.stderr}"
            assert agent_res.returncode == 0, f"Agent script failed on iteration {i+1} with return code {agent_res.returncode}.\nStderr: {agent_res.stderr}"

            oracle_output = oracle_res.stdout.strip()
            agent_output = agent_res.stdout.strip()

            if oracle_output != agent_output:
                pytest.fail(
                    f"Mismatch on iteration {i+1}.\n"
                    f"Oracle output lines: {len(oracle_output.splitlines())}\n"
                    f"Agent output lines: {len(agent_output.splitlines())}\n"
                    f"First 500 chars of expected (Oracle):\n{oracle_output[:500]}\n"
                    f"First 500 chars of actual (Agent):\n{agent_output[:500]}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
