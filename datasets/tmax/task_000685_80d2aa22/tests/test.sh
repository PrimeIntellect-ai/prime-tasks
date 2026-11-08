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
from datetime import datetime, timedelta

ORACLE_PATH = "/tests/oracle_stream_processor"
AGENT_SCRIPT = "/home/user/stream_processor.py"
NUM_TESTS = 50

def generate_random_timestamp():
    start_date = datetime(2023, 1, 1)
    end_date = datetime(2023, 12, 31, 23, 59, 59)
    delta = end_date - start_date
    random_second = random.randint(0, int(delta.total_seconds()))
    dt = start_date + timedelta(seconds=random_second)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def generate_input_data():
    sensor_ids = ["A1B", "X99", "J22", "K44"]
    num_lines = random.randint(100, 1000)
    lines = []
    for _ in range(num_lines):
        record = {
            "timestamp": generate_random_timestamp(),
            "sensor_id": random.choice(sensor_ids),
            "value": round(random.uniform(-100.0, 100.0), 2),
            "status": "OK"
        }
        lines.append(json.dumps(record))
    return "\n".join(lines) + "\n"

def test_stream_processor_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"

    random.seed(42)

    for i in range(NUM_TESTS):
        input_data = generate_input_data()

        # Run oracle
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on test {i}:\n{oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT],
            input=input_data,
            text=True,
            capture_output=True
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed on test {i} with error:\n{agent_proc.stderr}\nInput data preview:\n{input_data[:200]}")

        agent_out = agent_proc.stdout.strip()

        if oracle_out != agent_out:
            pytest.fail(
                f"Output mismatch on test {i}.\n"
                f"Input preview:\n{input_data[:200]}...\n\n"
                f"Oracle Output (first 500 chars):\n{oracle_out[:500]}\n\n"
                f"Agent Output (first 500 chars):\n{agent_out[:500]}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
