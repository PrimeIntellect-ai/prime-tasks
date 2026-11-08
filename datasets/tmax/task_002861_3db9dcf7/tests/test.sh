#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_fuzz_cases(n=5000, seed=42):
    random.seed(seed)
    cases = []
    operators = ['+', '-', '*', '/']
    modifiers = ['MIN', 'MAX']

    for _ in range(n):
        is_malformed = random.random() < 0.2
        tokens = []
        stack_size = 0

        target_len = random.randint(1, 15)

        if is_malformed:
            # Generate random tokens that might be invalid
            for _ in range(target_len):
                choice = random.choice(['num', 'op', 'mod', 'junk'])
                if choice == 'num':
                    tokens.append(str(random.randint(-500, 500)))
                elif choice == 'op':
                    tokens.append(random.choice(operators))
                elif choice == 'mod':
                    tokens.append(random.choice(modifiers))
                    if random.random() < 0.5:
                        tokens.append(str(random.randint(-500, 500)))
                else:
                    tokens.append(random.choice(['foo', 'bar', '++']))
        else:
            # Generate structurally valid RPN (though division by zero might still occur, which is fine)
            for _ in range(target_len):
                choices = ['num']
                if stack_size >= 2:
                    choices.append('op')
                choices.append('mod')

                choice = random.choice(choices)
                if choice == 'num':
                    tokens.append(str(random.randint(-500, 500)))
                    stack_size += 1
                elif choice == 'op':
                    tokens.append(random.choice(operators))
                    stack_size -= 1
                elif choice == 'mod':
                    tokens.append(random.choice(modifiers))
                    tokens.append(str(random.randint(-500, 500)))

            # Ensure exactly one item remains on the stack
            while stack_size > 1:
                tokens.append(random.choice(operators))
                stack_size -= 1
            while stack_size < 1:
                tokens.insert(0, str(random.randint(-500, 500)))
                stack_size += 1

        cases.append(" ".join(tokens))
    return cases

def run_script(script_path, expr):
    try:
        res = subprocess.run(
            ['python3', script_path, expr],
            capture_output=True,
            text=True,
            timeout=2
        )
        return res.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"

def test_fuzz_equivalence():
    student_script = "/home/user/rpn_eval.py"
    oracle_script = "/tests/oracle_eval.py"

    assert os.path.isfile(student_script), f"Student script not found at {student_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    fuzz_cases = generate_fuzz_cases(n=5000, seed=12345)

    for i, expr in enumerate(fuzz_cases):
        oracle_out = run_script(oracle_script, expr)
        student_out = run_script(student_script, expr)

        assert student_out == oracle_out, (
            f"Mismatch on fuzz case {i+1}:\n"
            f"Input: {expr!r}\n"
            f"Expected (Oracle): {oracle_out!r}\n"
            f"Got (Student): {student_out!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
