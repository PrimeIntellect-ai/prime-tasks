#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import json
import random
import uuid
import pytest

def generate_fuzz_input(num_lines=10000, seed=None):
    if seed is not None:
        random.seed(seed)

    lines = []
    seen_ids = []

    for _ in range(num_lines):
        is_valid = random.random() < 0.8
        if is_valid:
            is_duplicate = random.random() < 0.2 and len(seen_ids) > 0
            if is_duplicate:
                record_id = random.choice(seen_ids)
            else:
                record_id = str(uuid.uuid4())
                seen_ids.append(record_id)

            value = random.uniform(-1000.0, 1000.0)
            lines.append(json.dumps({"id": record_id, "value": value}))
        else:
            # Invalid JSON or missing ID
            error_type = random.choice(["bad_json", "missing_id", "bad_value_type"])
            if error_type == "bad_json":
                lines.append('{"id": "foo", "value": 123.45')
            elif error_type == "missing_id":
                lines.append(json.dumps({"value": random.uniform(0, 100)}))
            elif error_type == "bad_value_type":
                lines.append(json.dumps({"id": str(uuid.uuid4()), "value": "not-a-float"}))

    return "\n".join(lines) + "\n"

def test_agent_executable_exists():
    agent_path = "/home/user/cleaner"
    assert os.path.exists(agent_path), f"Agent executable missing at {agent_path}"
    assert os.path.isfile(agent_path), f"{agent_path} is not a file"
    assert os.access(agent_path, os.X_OK), f"{agent_path} is not executable"

@pytest.mark.parametrize("seed", range(5))
def test_fuzz_equivalence(seed):
    oracle_path = "/tests/oracle_cleaner"
    agent_path = "/home/user/cleaner"

    input_data = generate_fuzz_input(num_lines=10000, seed=seed)

    # Run oracle
    oracle_proc = subprocess.run(
        [oracle_path],
        input=input_data,
        text=True,
        capture_output=True
    )

    # Run agent
    agent_proc = subprocess.run(
        [agent_path],
        input=input_data,
        text=True,
        capture_output=True
    )

    assert agent_proc.returncode == oracle_proc.returncode, \
        f"Exit code mismatch. Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"

    assert agent_proc.stderr == oracle_proc.stderr, \
        "Stderr mismatch between agent and oracle."

    assert agent_proc.stdout == oracle_proc.stdout, \
        "Stdout mismatch between agent and oracle."
TEST_EOF

chmod +x /tests/oracle_cleaner
if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
