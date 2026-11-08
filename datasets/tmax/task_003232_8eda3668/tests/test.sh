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

AGENT_SCRIPT = "/home/user/plan_evaluator.py"
ORACLE_SCRIPT = "/tests/oracle_evaluator.py"

OPS = ["INDEX_SCAN", "TABLE_SCAN", "HASH_JOIN", "NESTED_LOOP", "GRAPH_TRAVERSAL", "UNKNOWN_OP", "FILTER"]

def generate_plan(depth=0, max_depth=10):
    node = {"operation": random.choice(OPS)}
    if depth < max_depth:
        # Decide randomly whether to have children, left/right, or leaf
        choice = random.choices(["leaf", "left_right", "children"], weights=[0.2, 0.4, 0.4])[0]
        if choice == "left_right":
            if random.choice([True, False]):
                node["left"] = generate_plan(depth + 1, max_depth)
            if random.choice([True, False]):
                node["right"] = generate_plan(depth + 1, max_depth)
        elif choice == "children":
            num_children = random.randint(1, 3)
            node["children"] = [generate_plan(depth + 1, max_depth) for _ in range(num_children)]
    return node

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    random.seed(42)

    for i in range(500):
        plan = generate_plan()
        input_json = json.dumps(plan)

        # Run agent
        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT],
            input=input_json,
            text=True,
            capture_output=True
        )
        # Run oracle
        oracle_proc = subprocess.run(
            ["python3", ORACLE_SCRIPT],
            input=input_json,
            text=True,
            capture_output=True
        )

        agent_out = agent_proc.stdout.strip()
        oracle_out = oracle_proc.stdout.strip()

        assert agent_proc.returncode == 0, f"Agent script failed on input: {input_json}\nError: {agent_proc.stderr}"
        assert oracle_proc.returncode == 0, f"Oracle script failed on input: {input_json}"

        assert agent_out == oracle_out, (
            f"Output mismatch on iteration {i}.\n"
            f"Input JSON: {input_json}\n"
            f"Oracle output: '{oracle_out}'\n"
            f"Agent output: '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
