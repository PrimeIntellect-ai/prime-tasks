#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_part1_stable_frame():
    """Verify that the stable frame index was correctly identified and written to the file."""
    output_file = "/home/user/stable_frame.txt"
    assert os.path.exists(output_file), f"Output file missing: {output_file}"

    with open(output_file, 'r') as f:
        content = f.read().strip()

    assert content == "142", f"Expected stable frame index '142', but got '{content}'"

def test_part2_stream_integrator_fuzz():
    """Verify that the stream integrator script exactly matches the oracle output."""
    script_path = "/home/user/stream_integrator.sh"
    oracle_path = "/tests/oracle_integrator"

    assert os.path.exists(script_path), f"Script missing: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"
    assert os.path.exists(oracle_path), f"Oracle missing: {oracle_path}"

    random.seed(42)
    num_tests = 50

    for i in range(num_tests):
        num_lines = random.randint(10, 500)
        input_floats = [random.uniform(-100.0, 100.0) for _ in range(num_lines)]
        input_str = "\n".join(f"{x:.6f}" for x in input_floats) + "\n"

        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_path],
            input=input_str,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run agent script
        agent_proc = subprocess.run(
            ["/bin/bash", script_path],
            input=input_str,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent script failed with return code {agent_proc.returncode}\nStderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        if oracle_out != agent_out:
            # Show a snippet of the input and output to help debugging
            input_snippet = input_str[:100] + ("..." if len(input_str) > 100 else "")
            oracle_snippet = oracle_out[:100] + ("..." if len(oracle_out) > 100 else "")
            agent_snippet = agent_out[:100] + ("..." if len(agent_out) > 100 else "")

            pytest.fail(
                f"Mismatch on random test {i+1}/{num_tests}.\n"
                f"Input snippet:\n{input_snippet}\n\n"
                f"Oracle output snippet:\n{oracle_snippet}\n\n"
                f"Agent output snippet:\n{agent_snippet}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
