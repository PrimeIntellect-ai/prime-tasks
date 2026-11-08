#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def generate_fuzz_input():
    id_str = "".join(random.choices("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", k=4))
    year = random.randint(1900, 2099)
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    hour = random.randint(0, 23)
    minute = random.randint(0, 59)
    second = random.randint(0, 59)
    ts = f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}Z"

    num_pairs = random.randint(0, 6)
    pairs = []
    for _ in range(num_pairs):
        key = random.choice(["T", "H", "P", "X", "V"])
        if random.random() < 0.5:
            # Generate mostly in-bounds
            if key == 'T':
                val = round(random.uniform(-50.0, 80.0), 1)
            elif key == 'H':
                val = round(random.uniform(0.0, 100.0), 1)
            elif key == 'P':
                val = round(random.uniform(900.0, 1100.0), 1)
            else:
                val = round(random.uniform(-100.0, 100.0), 1)
            pairs.append(f"{key}={val}")
        else:
            # Generate random out-of-bounds or edge
            sign = random.choice(["", "-"])
            val_int = random.randint(0, 1500)
            val_dec = random.randint(0, 9)
            pairs.append(f"{key}={sign}{val_int}.{val_dec}")

    data_str = ";".join(pairs)
    if random.random() < 0.2 and pairs:
        data_str += ";"

    return f"SENSOR_LOG [ID:{id_str}] [{ts}] DATA: {data_str}"

def test_fuzz_equivalence():
    oracle_path = "/app/legacy_processor"
    agent_script = "/home/user/processor.py"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"

    random.seed(42)
    inputs = [generate_fuzz_input() for _ in range(1000)]

    # Add some specific edge cases
    inputs.extend([
        "SENSOR_LOG [ID:A1B2] [2023-10-25T14:30:00Z] DATA: ",
        "SENSOR_LOG [ID:A1B2] [2023-10-25T14:30:00Z] DATA: T=22.4;H=55.1;P=1012.0;T=23.1",
        "SENSOR_LOG [ID:XYZ1] [2023-01-01T00:00:00Z] DATA: T=25.0;H=120.0;X=99.9",
        "SENSOR_LOG [ID:TEST] [2023-01-01T00:00:00Z] DATA: T=-50.0;H=0.0;P=900.0",
        "SENSOR_LOG [ID:TEST] [2023-01-01T00:00:00Z] DATA: T=80.0;H=100.0;P=1100.0",
        "SENSOR_LOG [ID:TEST] [2023-01-01T00:00:00Z] DATA: T=-50.1;H=-0.1;P=899.9",
        "SENSOR_LOG [ID:TEST] [2023-01-01T00:00:00Z] DATA: T=80.1;H=100.1;P=1100.1",
    ])

    for i, inp in enumerate(inputs):
        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_path],
            input=inp,
            text=True,
            capture_output=True
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=inp,
            text=True,
            capture_output=True
        )
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Output mismatch on input {i}:\n"
            f"Input:  {inp}\n"
            f"Oracle: {oracle_out}\n"
            f"Agent:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
