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

ORACLE_PATH = "/app/legacy_processor"
AGENT_PATH = "/home/user/processor.py"
NUM_RUNS = 100

def generate_fuzz_input(seed):
    rng = random.Random(seed)
    num_lines = rng.randint(1, 500)
    lines = []
    for _ in range(num_lines):
        record_id = rng.randint(1, 1000000000)
        num_intervals = rng.randint(0, 20)
        intervals = []
        for _ in range(num_intervals):
            start = rng.randint(0, 1000)
            end = rng.randint(start, 1000)
            intervals.append([start, end])
        lines.append(json.dumps({"id": record_id, "intervals": intervals}))
    return "\n".join(lines) + "\n"

def run_process(cmd, input_data):
    try:
        result = subprocess.run(
            cmd,
            input=input_data,
            text=True,
            capture_output=True,
            timeout=5
        )
        return result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        return None, "Timeout expired", -1

def parse_and_sort_output(output_str):
    if not output_str.strip():
        return []
    lines = output_str.strip().split("\n")
    parsed = []
    for line in lines:
        if not line.strip():
            continue
        try:
            parsed.append(json.loads(line))
        except json.JSONDecodeError:
            parsed.append({"error": "invalid_json", "raw": line})

    # Sort by id if available, else by string representation
    parsed.sort(key=lambda x: x.get("id", str(x)))
    return parsed

@pytest.mark.parametrize("seed", range(NUM_RUNS))
def test_fuzz_equivalence(seed):
    input_data = generate_fuzz_input(seed)

    oracle_stdout, oracle_stderr, oracle_rc = run_process([ORACLE_PATH], input_data)
    assert oracle_rc == 0, f"Oracle failed with rc={oracle_rc}, stderr: {oracle_stderr}"

    agent_stdout, agent_stderr, agent_rc = run_process(["python3", AGENT_PATH], input_data)
    assert agent_rc != -1, "Agent timed out (possible deadlock)"
    assert agent_rc == 0, f"Agent failed with rc={agent_rc}, stderr: {agent_stderr}"

    oracle_sorted = parse_and_sort_output(oracle_stdout)
    agent_sorted = parse_and_sort_output(agent_stdout)

    assert agent_sorted == oracle_sorted, (
        f"Output mismatch on seed {seed}.\n"
        f"Input lines: {len(input_data.strip().split())}\n"
        f"Oracle output: {oracle_sorted}\n"
        f"Agent output: {agent_sorted}\n"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
