#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_reducer_fuzz_equivalence():
    agent_bin = "/home/user/reducer"
    oracle_bin = "/tests/reference_reducer"

    assert os.path.exists(agent_bin), f"Agent binary not found at {agent_bin}. Did you compile your Go program?"
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable."

    random.seed(42)

    # Run 100 fuzz tests to ensure equivalence
    for i in range(100):
        num_lines = random.randint(1, 100)
        lines = []
        for _ in range(num_lines):
            f1 = random.uniform(-1000.0, 1000.0)
            f2 = random.uniform(-1000.0, 1000.0)
            f3 = random.uniform(-1000.0, 1000.0)
            lines.append(f"{f1},{f2},{f3}")

        # Randomly inject a blank line to test the "ignore blank lines" requirement
        if random.random() < 0.3:
            lines.insert(random.randint(0, len(lines)), "")

        input_data = "\n".join(lines) + "\n"

        oracle_proc = subprocess.run([oracle_bin], input=input_data, text=True, capture_output=True)
        agent_proc = subprocess.run([agent_bin], input=input_data, text=True, capture_output=True)

        assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode}. Stderr: {agent_proc.stderr}"

        oracle_out = oracle_proc.stdout
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            # Truncate output for display if it's too long
            display_input = input_data if len(input_data) < 500 else input_data[:500] + "\n...[truncated]"
            display_expected = oracle_out if len(oracle_out) < 500 else oracle_out[:500] + "\n...[truncated]"
            display_actual = agent_out if len(agent_out) < 500 else agent_out[:500] + "\n...[truncated]"

            pytest.fail(
                f"Mismatch on fuzz test {i+1}:\n\n"
                f"Input:\n{display_input}\n\n"
                f"Expected Output (Oracle):\n{display_expected}\n\n"
                f"Actual Output (Agent):\n{display_actual}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
