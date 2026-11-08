#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

AGENT_SCRIPT = "/home/user/clean_etl.sh"
ORACLE_SCRIPT = "/tests/oracle_clean.sh"
NUM_ITERATIONS = 50

def generate_csv_data(num_lines: int) -> str:
    events = ["login", "Logout", "PURCHASE", "TEST_EVENT", "click"]
    users = [f"U{i:02d}" for i in range(1, 51)]

    lines = []
    for _ in range(num_lines):
        ts = random.randint(1000000, 9999999)
        user = random.choice(users)
        event = random.choice(events)
        val = round(random.uniform(0.0, 1000.0), random.randint(0, 4))
        lines.append(f"{ts},{user},{event},{val}")

    return "\n".join(lines) + "\n"

def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable"

def test_fuzz_equivalence():
    random.seed(42)  # Fixed seed for reproducibility

    for i in range(NUM_ITERATIONS):
        # Generate random length between 1000 and 50000 (using a smaller max to prevent test timeouts, but still large enough)
        num_lines = random.randint(1000, 5000)
        input_data = generate_csv_data(num_lines)

        # Run Oracle, which is uploaded only at verification time.
        oracle_proc = subprocess.run(
            ["bash", ORACLE_SCRIPT],
            input=input_data,
            text=True,
            capture_output=True,
            check=False
        )
        assert oracle_proc.returncode == 0, f"Oracle script failed on iteration {i}"
        oracle_output = oracle_proc.stdout

        # Run Agent
        agent_proc = subprocess.run(
            [AGENT_SCRIPT],
            input=input_data,
            text=True,
            capture_output=True,
            check=False
        )

        assert agent_proc.returncode == 0, f"Agent script failed (exit code {agent_proc.returncode}) on iteration {i}.\nStderr: {agent_proc.stderr}"
        agent_output = agent_proc.stdout

        if oracle_output != agent_output:
            # Truncate input data for display if it's too long
            display_input = input_data if len(input_data) < 1000 else input_data[:1000] + "\n...[truncated]"
            pytest.fail(
                f"Mismatch on iteration {i} (input length: {num_lines} lines).\n\n"
                f"--- Input Data (start) ---\n{display_input}\n\n"
                f"--- Expected Output (Oracle) ---\n{oracle_output}\n"
                f"--- Actual Output (Agent) ---\n{agent_output}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
