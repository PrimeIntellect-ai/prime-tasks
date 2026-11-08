#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_datamash_installed():
    datamash_path = "/home/user/local/bin/datamash"
    assert os.path.isfile(datamash_path), f"datamash executable not found at {datamash_path}"
    assert os.access(datamash_path, os.X_OK), f"datamash at {datamash_path} is not executable"

def test_agent_script_exists_and_executable():
    script_path = "/home/user/process_sensor_data.sh"
    assert os.path.isfile(script_path), f"Agent script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Agent script at {script_path} is not executable"

def generate_random_csv(num_lines):
    lines = []
    for _ in range(num_lines):
        ts = random.randint(1670000000000, 1680000000000)
        s1 = round(random.uniform(-50.0, 150.0), 1)
        s2 = round(random.uniform(-50.0, 150.0), 1)
        s3 = round(random.uniform(-50.0, 150.0), 1)
        lines.append(f"{ts},{s1},{s2},{s3}")
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_process.sh"
    agent_path = "/home/user/process_sensor_data.sh"

    assert os.path.isfile(oracle_path), f"Oracle script not found at {oracle_path}"

    random.seed(42)

    # We use N=10 to balance thoroughness and test execution time, with 10k lines each.
    N = 10
    for i in range(N):
        num_lines = random.randint(10000, 20000)
        input_data = generate_random_csv(num_lines)

        # Run oracle
        oracle_proc = subprocess.run(
            ["bash", oracle_path],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr}"

        # Run agent
        agent_proc = subprocess.run(
            [agent_path],
            input=input_data,
            text=True,
            capture_output=True
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed on iteration {i}.\nStderr: {agent_proc.stderr}")

        if oracle_proc.stdout != agent_proc.stdout:
            # Provide a snippet of the mismatch
            oracle_lines = oracle_proc.stdout.splitlines()
            agent_lines = agent_proc.stdout.splitlines()

            diff_msg = f"Mismatch on iteration {i} (input lines: {num_lines}).\n"
            diff_msg += f"Oracle output lines: {len(oracle_lines)}, Agent output lines: {len(agent_lines)}\n"

            for j, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
                if o_line != a_line:
                    diff_msg += f"First mismatch at output line {j + 1}:\n"
                    diff_msg += f"Oracle: {o_line}\n"
                    diff_msg += f"Agent : {a_line}\n"
                    break

            pytest.fail(diff_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
