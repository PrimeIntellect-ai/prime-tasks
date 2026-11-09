#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import random
import subprocess
import os
import pytest

def generate_fuzz_input():
    regions = ["us-east", "eu-west", "ap-south"]
    suffixes = ["", "ms", "s", "us"]
    prefixes = ["", "<", ">"]

    num_events = random.randint(1000, 10000)
    events = []
    for _ in range(num_events):
        region = random.choice(regions)

        val = random.uniform(0.000001, 1000.0)

        if random.random() < 0.3:
            val_str = f"{val:e}"
        else:
            val_str = f"{val:.6f}"

        prefix = random.choice(prefixes)
        suffix = random.choice(suffixes)

        downtime = f"{prefix}{val_str}{suffix}"
        events.append({"region": region, "downtime": downtime})

    return json.dumps(events)

def test_fuzz_equivalence():
    oracle_path = "/tests/reference_sla_calc"
    agent_cmd = ["python3", "/home/user/fast_sla_calc.py"]

    assert os.path.exists(oracle_path), f"Oracle not found at {oracle_path}"
    assert os.path.exists("/home/user/fast_sla_calc.py"), "Agent script not found"

    random.seed(42)
    N = 200

    for i in range(N):
        input_data = generate_fuzz_input()
        input_bytes = input_data.encode('utf-8')

        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=input_bytes,
                capture_output=True,
                text=True,
                timeout=10,
                check=True
            )
            oracle_output = oracle_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on fuzz iteration {i+1}")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle crashed on fuzz iteration {i+1}:\n{e.stderr}")

        try:
            agent_proc = subprocess.run(
                agent_cmd,
                input=input_bytes,
                capture_output=True,
                text=True,
                timeout=10
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out (possible deadlock) on fuzz iteration {i+1}")

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script crashed on fuzz iteration {i+1}:\n{agent_proc.stderr}")

        agent_output = agent_proc.stdout.strip()

        assert agent_output == oracle_output, (
            f"Output mismatch on fuzz iteration {i+1}.\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output:  {agent_output}\n"
            f"Input preview: {input_data[:200]}..."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
