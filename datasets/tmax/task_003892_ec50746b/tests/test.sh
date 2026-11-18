#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_random_csv_input(num_lines):
    lines = []
    for _ in range(num_lines):
        src = random.randint(1, 999)
        tgt = random.randint(1, 999)
        # 1[5-7][0-9]{8}
        ts_prefix = random.choice(["15", "16", "17"])
        ts_suffix = "".join(str(random.randint(0, 9)) for _ in range(8))
        ts = f"{ts_prefix}{ts_suffix}"
        lines.append(f"{src},{tgt},{ts}")
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    agent_script = "/home/user/process_graph.sh"
    oracle_script = "/tests/process_graph_oracle.sh"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"

    random.seed(42)

    for i in range(100):
        num_lines = random.randint(10, 500)
        csv_input = generate_random_csv_input(num_lines)

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_script],
                input=csv_input,
                text=True,
                capture_output=True,
                check=True
            )
            oracle_output = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i} with input:\n{csv_input}\nError:\n{e.stderr}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                ["bash", agent_script],
                input=csv_input,
                text=True,
                capture_output=True,
                check=True
            )
            agent_output = agent_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on iteration {i} with input:\n{csv_input}\nError:\n{e.stderr}")

        assert agent_output == oracle_output, (
            f"Output mismatch on iteration {i}.\n"
            f"Input:\n{csv_input}\n"
            f"Oracle Output:\n{oracle_output}\n"
            f"Agent Output:\n{agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
