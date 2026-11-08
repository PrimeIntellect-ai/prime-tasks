#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def generate_expr(depth=0):
    if depth > 4 or (depth > 0 and random.random() < 0.4):
        return str(random.randint(1, 20))

    op = random.choice(['+', '-', '*', 'SEQ'])
    if op == 'SEQ':
        return f"SEQ({generate_expr(depth+1)})"
    else:
        left = generate_expr(depth+1)
        right = generate_expr(depth+1)
        if random.random() < 0.5:
            return f"({left} {op} {right})"
        else:
            return f"{left} {op} {right}"

def test_fuzz_equivalence():
    oracle_path = "/tests/evaluator_oracle"
    agent_script = "/home/user/evaluator.py"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"

    random.seed(42)

    # N=1000 to keep test time reasonable while still providing strong fuzzing
    num_tests = 1000

    for _ in range(num_tests):
        expr = generate_expr()

        # Run oracle, uploaded only at verification time.
        try:
            oracle_res = subprocess.run(
                ["python3", oracle_path, expr],
                capture_output=True,
                text=True,
                timeout=2
            )
            oracle_out = oracle_res.stdout.strip()
        except subprocess.TimeoutExpired:
            continue # Skip if oracle timeouts

        # Run agent
        try:
            agent_res = subprocess.run(
                ["python3", agent_script, expr],
                capture_output=True,
                text=True,
                timeout=2
            )
            agent_out = agent_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: {expr}")

        if oracle_res.returncode == 0:
            assert agent_res.returncode == 0, f"Agent script failed on input '{expr}'.\nOracle output: {oracle_out}\nAgent error: {agent_res.stderr.strip()}"
            assert agent_out == oracle_out, f"Mismatch on input '{expr}'.\nExpected (Oracle): {oracle_out}\nGot (Agent): {agent_out}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
