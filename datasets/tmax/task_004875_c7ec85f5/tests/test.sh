#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import subprocess
import pytest

AGENT_PROGRAM = "/home/user/segment_sizer"
ORACLE_PROGRAM = "/tests/reference_oracle_segment_sizer"
NUM_ITERATIONS = 50

def generate_fuzz_input():
    num_objects = random.randint(1, 100)
    payload = []
    for _ in range(num_objects):
        start = random.randint(0, 290)
        end = random.randint(start, 299)
        payload.append({"start_frame": start, "end_frame": end})
    return json.dumps(payload)

def test_agent_program_exists_and_executable():
    assert os.path.isfile(AGENT_PROGRAM), f"Agent program missing at {AGENT_PROGRAM}"
    assert os.access(AGENT_PROGRAM, os.X_OK), f"Agent program at {AGENT_PROGRAM} is not executable"

def test_fuzz_equivalence():
    random.seed(42)

    for i in range(NUM_ITERATIONS):
        input_data = generate_fuzz_input()

        # Run oracle, uploaded only at verification time.
        oracle_proc = subprocess.run(
            ["python3", ORACLE_PROGRAM],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i} with input {input_data}\nStderr: {oracle_proc.stderr}"

        # Run agent
        agent_proc = subprocess.run(
            [AGENT_PROGRAM],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent failed on iteration {i} with input {input_data}\nStderr: {agent_proc.stderr}"

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch on iteration {i}!\n"
            f"Input: {input_data}\n"
            f"Oracle Output:\n{oracle_proc.stdout}\n"
            f"Agent Output:\n{agent_proc.stdout}\n"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
