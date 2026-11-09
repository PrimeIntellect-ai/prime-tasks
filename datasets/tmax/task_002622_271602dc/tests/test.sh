#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import string
import pytest

def test_solution_exists():
    solution_path = "/home/user/solution.py"
    assert os.path.exists(solution_path), f"The solution file {solution_path} does not exist."
    assert os.path.isfile(solution_path), f"The path {solution_path} is not a file."

def test_fuzz_equivalence():
    solution_path = "/home/user/solution.py"
    oracle_path = "/app/path_decoder"

    assert os.path.exists(oracle_path), f"Oracle binary {oracle_path} is missing."

    # Character set: printable ASCII (32-126) + newline (10) + tab (9)
    charset = [chr(i) for i in range(32, 127)] + ['\n', '\t']

    random.seed(42)
    N = 500

    for i in range(N):
        length = random.randint(0, 5000)
        input_str = "".join(random.choice(charset) for _ in range(length))
        input_bytes = input_str.encode('utf-8')

        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_path],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5
        )
        oracle_out = oracle_proc.stdout

        # Run agent solution
        agent_proc = subprocess.run(
            ["python3", solution_path],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5
        )
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            # Truncate output for display if it's too long
            display_input = input_str[:100] + ("..." if len(input_str) > 100 else "")
            display_oracle = oracle_out[:100] + (b"..." if len(oracle_out) > 100 else b"")
            display_agent = agent_out[:100] + (b"..." if len(agent_out) > 100 else b"")

            pytest.fail(
                f"Mismatch on iteration {i+1}.\n"
                f"Input length: {length}\n"
                f"Input (truncated): {repr(display_input)}\n"
                f"Oracle output (truncated): {repr(display_oracle)}\n"
                f"Agent output (truncated): {repr(display_agent)}\n"
                f"Agent stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
