#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_extract_metric_equivalence():
    agent_script = "/home/user/extract_metric.py"
    oracle_script = "/tests/extract_metric.py"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script not found at {oracle_script}"

    # Generate fuzz input
    random.seed(42)
    inputs = [str(random.randint(-10, 400)) for _ in range(50)]
    input_str = "\n".join(inputs) + "\n"

    # Run oracle
    oracle_proc = subprocess.run(
        ["python3", oracle_script],
        input=input_str,
        text=True,
        capture_output=True,
        check=False
    )
    assert oracle_proc.returncode == 0, f"Oracle failed to run:\n{oracle_proc.stderr}"
    oracle_output = oracle_proc.stdout.strip()

    # Run agent
    agent_proc = subprocess.run(
        ["python3", agent_script],
        input=input_str,
        text=True,
        capture_output=True,
        check=False
    )
    assert agent_proc.returncode == 0, f"Agent script failed to run:\n{agent_proc.stderr}"
    agent_output = agent_proc.stdout.strip()

    # Compare outputs
    if oracle_output != agent_output:
        pytest.fail(
            "Agent output does not match oracle output.\n"
            f"Input:\n{input_str}\n"
            f"Oracle Output:\n{oracle_output}\n\n"
            f"Agent Output:\n{agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
