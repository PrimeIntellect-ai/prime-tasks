#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import json
import random
import string
import subprocess
import pytest

def test_tiny_sql_builder_fixed():
    sys.path.insert(0, "/app")
    try:
        from tiny_sql_builder.builder import Window
    except ImportError as e:
        pytest.fail(f"Failed to import Window from tiny_sql_builder: {e}")
    finally:
        sys.path.pop(0)

    w1 = Window(partition_by="user_id", order_by="timestamp")
    w2 = Window(order_by="timestamp")
    w3 = Window(partition_by="user_id")

    assert str(w1) == "OVER (PARTITION BY user_id ORDER BY timestamp)", f"Window string representation incorrect: {str(w1)}"
    assert str(w2) == "OVER (ORDER BY timestamp)", f"Window string representation incorrect: {str(w2)}"
    assert str(w3) == "OVER (PARTITION BY user_id)", f"Window string representation incorrect: {str(w3)}"

def generate_fuzz_input(num_lines):
    lines = []
    for _ in range(num_lines):
        tx_id = ''.join(random.choices(string.ascii_letters + string.digits, k=10))
        user_id = random.randint(1, 50)
        status = random.choice(["success", "rollback", "deadlock"])
        timestamp = random.randint(1000000, 2000000)
        lines.append(json.dumps({
            "tx_id": tx_id,
            "user_id": user_id,
            "status": status,
            "timestamp": timestamp
        }))
    return "\n".join(lines) + "\n"

def test_aggregate_fuzz_equivalence():
    agent_script = "/home/user/aggregate.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}"

    random.seed(42)

    for i in range(50):
        num_lines = random.randint(10, 1000)
        input_data = generate_fuzz_input(num_lines)

        agent_proc = subprocess.run(
            [sys.executable, agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_proc.stderr}"

        oracle_proc = subprocess.run(
            [sys.executable, oracle_script],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle script failed on iteration {i}:\n{oracle_proc.stderr}"

        try:
            agent_out = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent output is not valid JSON:\n{agent_proc.stdout}")

        try:
            oracle_out = json.loads(oracle_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle output is not valid JSON:\n{oracle_proc.stdout}")

        assert agent_out == oracle_out, (
            f"Output mismatch on iteration {i} (num_lines={num_lines}).\n"
            f"Agent output:\n{json.dumps(agent_out, indent=2)}\n"
            f"Oracle output:\n{json.dumps(oracle_out, indent=2)}\n"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
