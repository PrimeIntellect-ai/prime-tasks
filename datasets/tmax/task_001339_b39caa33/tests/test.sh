#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import uuid
import random
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/tests/oracle_cleaner"
AGENT_SCRIPT = "/home/user/etl_cleaner.py"
NUM_ITERATIONS = 100

def generate_random_jsonl(file_path, num_lines):
    # ~20% duplicates means we generate fewer unique UUIDs
    num_unique_ids = max(1, int(num_lines * 0.8))
    unique_ids = [str(uuid.uuid4()) for _ in range(num_unique_ids)]

    with open(file_path, 'w') as f:
        for _ in range(num_lines):
            tx_id = random.choice(unique_ids)
            timestamp = random.randint(1600000000, 1700000000)
            # Occasional spikes
            if random.random() < 0.1:
                value = random.uniform(0.0, 1000.0)
            else:
                value = random.uniform(0.0, 100.0)

            record = {
                "tx_id": tx_id,
                "timestamp": timestamp,
                "value": value
            }
            f.write(json.dumps(record) + '\n')

def test_etl_cleaner_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(NUM_ITERATIONS):
            num_lines = random.randint(50, 5000)
            input_file = os.path.join(tmpdir, f"input_{i}.jsonl")
            generate_random_jsonl(input_file, num_lines)

            # Run Oracle
            oracle_cmd = [ORACLE_PATH, input_file]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_res.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_res.stderr}"

            # Run Agent
            agent_cmd = ["python3", AGENT_SCRIPT, input_file]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
            assert agent_res.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_res.stderr}"

            oracle_output = oracle_res.stdout.strip()
            agent_output = agent_res.stdout.strip()

            if oracle_output != agent_output:
                # Save the failing input for debugging info
                with open(input_file, 'r') as f:
                    input_data = f.read()

                error_msg = (
                    f"Mismatch on iteration {i} (num_lines={num_lines})\n"
                    f"Oracle output lines: {len(oracle_output.splitlines())}\n"
                    f"Agent output lines: {len(agent_output.splitlines())}\n"
                    f"Input sample (first 5 lines):\n"
                    f"{''.join(input_data.splitlines(True)[:5])}\n"
                    f"Oracle output sample (first 5 lines):\n"
                    f"{''.join(oracle_output.splitlines(True)[:5])}\n"
                    f"Agent output sample (first 5 lines):\n"
                    f"{''.join(agent_output.splitlines(True)[:5])}\n"
                )
                pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
