#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

PROJECT = '/home/user/rpn_calc'
BINARY = os.path.join(PROJECT, 'rpn_calc')


def run_calc(expression):
    return subprocess.run(
        [BINARY, expression],
        capture_output=True,
        text=True,
        timeout=5,
    )


def evaluate_rpn(expression):
    stack = []
    for token in expression.split():
        if token in {'+', '-', '*', '/', '^'}:
            b = stack.pop()
            a = stack.pop()
            if token == '+':
                stack.append(a + b)
            elif token == '-':
                stack.append(a - b)
            elif token == '*':
                stack.append(a * b)
            elif token == '/':
                stack.append(a / b)
            else:
                stack.append(math.pow(a, b))
        else:
            stack.append(float(token))
    assert len(stack) == 1
    return stack[0]


def assert_valid_result(expression, expected=None):
    if expected is None:
        expected = evaluate_rpn(expression)
    result = run_calc(expression)
    assert result.returncode == 0, (
        f'rpn_calc rejected valid expression {expression!r}: {result.stderr!r}'
    )
    output = result.stdout.strip()
    assert re.fullmatch(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?', output), (
        f'rpn_calc produced a non-numeric or extra output for {expression!r}: {result.stdout!r}'
    )
    actual = float(output)
    assert math.isfinite(actual)
    assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=0.0002), (
        f'Wrong result for {expression!r}: expected {expected}, got {actual}'
    )


def assert_error(expression):
    result = run_calc(expression)
    assert result.returncode == 1, (
        f'rpn_calc did not exit with code 1 for invalid expression {expression!r}'
    )
    assert 'Error' in result.stderr, (
        f'rpn_calc did not print Error to stderr for {expression!r}'
    )


def test_sorted_outputs_exists_and_correct():
    output_path = '/home/user/rpn_calc/sorted_outputs.txt'
    assert os.path.isfile(output_path), f'Output file {output_path} is missing.'

    with open(output_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        '25.00',
        '16.00',
        '12.00',
        '7.00',
        '5.00'
    ]

    assert lines == expected_lines, (
        f'Contents of {output_path} do not match the expected sorted outputs.\n'
        f'Expected: {expected_lines}\nGot: {lines}'
    )


def test_makefile_fixed_and_project_rebuilds():
    makefile_path = '/home/user/rpn_calc/Makefile'
    assert os.path.isfile(makefile_path), f'Makefile {makefile_path} is missing.'

    with open(makefile_path, 'r') as f:
        content = f.read()

    assert '-lm' in content, 'Makefile was not updated to link the math library (-lm).'

    clean = subprocess.run(
        ['make', 'clean'], cwd=PROJECT, capture_output=True, text=True, timeout=20
    )
    assert clean.returncode == 0, f'make clean failed:\n{clean.stdout}\n{clean.stderr}'
    assert not os.path.exists(BINARY), 'make clean did not remove the rpn_calc binary.'

    build = subprocess.run(
        ['make'], cwd=PROJECT, capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, f'make failed:\n{build.stdout}\n{build.stderr}'
    assert os.path.isfile(BINARY), 'make did not create rpn_calc.'
    assert os.access(BINARY, os.X_OK), 'The rebuilt rpn_calc is not executable.'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'The rebuilt rpn_calc is not a compiled ELF executable.'


def test_rpn_calc_binary_exists():
    assert os.path.isfile(BINARY), f'Compiled binary {BINARY} is missing.'
    assert os.access(BINARY, os.X_OK), f'Binary {BINARY} is not executable.'


def test_rpn_calc_valid_evaluation():
    # Explicitly cover every operator, operand order, nesting, and the valid
    # boundary where all ten fixed stack slots are occupied.
    expressions = [
        '3 4 +',
        '19 6 -',
        '7 8 *',
        '22 7 /',
        '2 5 ^',
        '5 2 - 4 * 3 +',
        '2 3 2 ^ ^',
        '9 2 / 3 -',
        '1 2 3 4 5 6 7 8 9 10 + + + + + + + + +',
    ]
    for expression in expressions:
        assert_valid_result(expression)

    # Generate fresh valid cases at verification time. Answers are calculated
    # independently rather than copied from a fixed expected-output list.
    rng = random.SystemRandom()
    operators = ['+', '-', '*', '/']
    for _ in range(40):
        count = rng.randint(2, 10)
        values = [rng.randint(1, 20) for _ in range(count)]
        tokens = [str(value) for value in values]
        stack = [float(value) for value in values]
        while len(stack) > 1:
            b = stack.pop()
            a = stack.pop()
            op = rng.choice(operators)
            if op == '/' and abs(b) < 1e-12:
                op = '+'
            tokens.append(op)
            if op == '+':
                stack.append(a + b)
            elif op == '-':
                stack.append(a - b)
            elif op == '*':
                stack.append(a * b)
            else:
                stack.append(a / b)
        assert_valid_result(' '.join(tokens), stack[0])


def test_rpn_calc_memory_safety():
    c_file_path = '/home/user/rpn_calc/rpn_calc.c'
    assert os.path.isfile(c_file_path), f'Source file {c_file_path} is missing.'

    with open(c_file_path, 'r') as f:
        content = f.read()

    assert 'stderr' in content, 'rpn_calc.c does not print to stderr upon error.'

    # Preserve the original overflow and underflow checks.
    overflow_expr = '1 ' * 15 + '+ ' * 14
    assert_error(overflow_expr)
    assert_error('3 +')

    # The fixed stack has ten slots, so the eleventh push must be rejected.
    assert_error(' '.join(['1'] * 11))

    # Exercise underflow both on an empty stack and after earlier valid work,
    # for every binary operator.
    for op in ['+', '-', '*', '/', '^']:
        assert_error(op)
        assert_error(f'8 2 {op} {op}')
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
