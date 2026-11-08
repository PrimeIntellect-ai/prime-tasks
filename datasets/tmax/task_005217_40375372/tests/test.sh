#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import json
import random
import subprocess
import pytest

def test_etl_equivalence():
    """
    Fuzz-equivalence test for the ETL pipeline.
    Generates 50,000 JSONL records and compares the output of the agent's script
    with the oracle script supplied only at verification time.
    """
    agent_script = "/home/user/etl.py"
    oracle_script = "/tests/oracle_etl.py"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    # Generate fuzz input
    random.seed(42)
    num_lines = 50000
    ts_start = 1600000000
    sensors = ["Sensor_A", "Sensor_B", "Sensor_C", "Sensor_D"]
    statuses = ["正常", "⚠️", "Ok", "En línea", "Desconectado"]

    input_lines = []
    for i in range(num_lines):
        ts = ts_start + i
        sensor = random.choice(sensors)
        if random.random() < 0.7:
            temp = round(random.uniform(-20.0, 50.0), 2)
        else:
            temp = None
        status = random.choice(statuses)

        record = {
            "ts": ts,
            "sensor": sensor,
            "temp": temp,
            "status": status
        }
        input_lines.append(json.dumps(record, ensure_ascii=False))

    input_data = "\n".join(input_lines) + "\n"
    input_bytes = input_data.encode("utf-8")

    # Run oracle
    oracle_proc = subprocess.run(
        [sys.executable, oracle_script],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    assert oracle_proc.returncode == 0, f"Oracle failed with error: {oracle_proc.stderr.decode()}"
    oracle_output = oracle_proc.stdout.decode("utf-8").splitlines()

    # Run agent
    agent_proc = subprocess.run(
        [sys.executable, agent_script],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    assert agent_proc.returncode == 0, f"Agent script failed with error: {agent_proc.stderr.decode()}"
    agent_output = agent_proc.stdout.decode("utf-8").splitlines()

    # Compare lengths
    assert len(agent_output) == len(oracle_output), (
        f"Output line count mismatch. Expected {len(oracle_output)}, got {len(agent_output)}."
    )

    # Compare line by line
    for i, (oracle_line, agent_line) in enumerate(zip(oracle_output, agent_output)):
        if oracle_line != agent_line:
            pytest.fail(
                f"Output mismatch at line {i + 1}.\n"
                f"Input: {input_lines[i]}\n"
                f"Expected: {oracle_line}\n"
                f"Got:      {agent_line}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
