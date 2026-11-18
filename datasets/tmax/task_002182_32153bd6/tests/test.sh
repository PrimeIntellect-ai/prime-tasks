#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess


def generate_inputs(n=1000, seed=42):
    random.seed(seed)
    inputs = []
    ops = ['+', '-', '*', '@']
    while len(inputs) < n:
        num_terms = random.randint(2, 10)
        expr = str(random.randint(1, 100))
        for _ in range(num_terms - 1):
            op = random.choice(ops)
            num = str(random.randint(1, 100))
            sp1 = " " * random.randint(0, 1)
            sp2 = " " * random.randint(0, 1)
            expr += f"{sp1}{op}{sp2}{num}"
        if 3 <= len(expr) <= 50:
            inputs.append(expr)
    return inputs


def int64(value):
    value &= (1 << 64) - 1
    if value >= (1 << 63):
        value -= 1 << 64
    return value


def expected_result(expr):
    tokens = re.findall(r'\d+|[+\-*@]', expr)

    i = 0
    while i < len(tokens):
        if tokens[i] in ('*', '@'):
            op = tokens[i]
            left = int(tokens[i - 1])
            right = int(tokens[i + 1])
            if op == '*':
                result = int64(left * right)
            else:
                result = int64(int64(left * left) + right)
            tokens = tokens[:i - 1] + [str(result)] + tokens[i + 2:]
            i -= 1
        else:
            i += 1

    i = 0
    while i < len(tokens):
        if tokens[i] in ('+', '-'):
            op = tokens[i]
            left = int(tokens[i - 1])
            right = int(tokens[i + 1])
            if op == '+':
                result = int64(left + right)
            else:
                result = int64(left - right)
            tokens = tokens[:i - 1] + [str(result)] + tokens[i + 2:]
            i -= 1
        else:
            i += 1

    return str(int(tokens[0]))


def test_fuzz_equivalence():
    agent_bin = "/app/math_engine/build/eval_tool"

    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}. Did the build succeed?"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable at {agent_bin}."

    inputs = generate_inputs(1000)

    for expr in inputs:
        expected = expected_result(expr)
        agent_res = subprocess.run([agent_bin, expr], capture_output=True, text=True)
        assert agent_res.returncode == 0, (
            f"Agent program failed (exit code {agent_res.returncode}) on input: '{expr}'\n"
            f"Stderr: {agent_res.stderr}"
        )

        agent_out = agent_res.stdout.strip()
        assert agent_out == expected, (
            f"Mismatch on input: '{expr}'\n"
            f"Expected output: '{expected}'\n"
            f"Actual output: '{agent_out}'\n"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
