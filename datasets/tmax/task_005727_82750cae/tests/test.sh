#!/bin/bash
set -u
mkdir -p /logs/verifier

PROJECT=/home/user/expr_project
rm -f "$PROJECT/expr_app"
if ! (cd "$PROJECT" && timeout 120 ./build.sh) > /tmp/expr_build.log 2>&1; then
    cat /tmp/expr_build.log
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

PROJECT = '/home/user/expr_project'
APP = os.path.join(PROJECT, 'expr_app')


def run_app(expression):
    result = subprocess.run(
        [APP, expression], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, (
        f"expr_app exited with {result.returncode} for {expression!r}: "
        f"stderr={result.stderr!r}"
    )
    return result.stdout.strip()


def test_result_log():
    log_path = '/home/user/result.log'
    assert os.path.isfile(log_path), f"File {log_path} does not exist. The task requires saving the result to this file."

    with open(log_path, 'r') as f:
        content = f.read().strip()

    assert content == '21', f"Expected /home/user/result.log to contain exactly '21', but got '{content}'."


def test_expr_app_exists_and_executable():
    assert os.path.isfile(APP), f"Executable {APP} does not exist. Ensure the build script compiles to this location."
    assert os.access(APP, os.X_OK), f"File {APP} is not executable."
    with open(APP, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'expr_app must be a compiled executable, not a fabricated script.'

    metadata = subprocess.run(
        ['go', 'version', '-m', APP], capture_output=True, text=True, timeout=10
    )
    assert metadata.returncode == 0 and 'go1.' in metadata.stdout, (
        'expr_app must be the Go application produced by the project build.'
    )


def test_sources_are_organized_and_bounds_check_is_present():
    main_path = os.path.join(PROJECT, 'main.go')
    c_path = os.path.join(PROJECT, 'eval.c')
    h_path = os.path.join(PROJECT, 'eval.h')
    for path in (main_path, c_path, h_path):
        assert os.path.isfile(path), f'Required cgo source file is not organized at {path}'

    with open(main_path) as f:
        main_source = f.read()
    assert 'import "C"' in main_source
    assert '#include "eval.h"' in main_source
    assert re.search(r'\bC\.eval_rpn\s*\(', main_source)

    with open(c_path) as f:
        c_source = f.read()
    # Ignore comments so a comment describing the intended fix cannot satisfy inspection.
    c_code = re.sub(r'/\*.*?\*/', '', c_source, flags=re.S)
    c_code = re.sub(r'//[^\n]*', '', c_code)
    assert re.search(r'\bint\s+stack\s*\[\s*4\s*\]', c_code), 'eval_rpn must retain its four-element stack.'
    check = re.search(
        r'if\s*\(\s*sp\s*>=\s*4\s*\)\s*(?:\{\s*)?return\s+-999\s*;',
        c_code,
    )
    assert check, 'eval.c must return -999 when a push is attempted with sp >= 4.'
    numeric_push = re.search(r'stack\s*\[\s*sp\s*\+\+\s*\]\s*=\s*val\s*;', c_code)
    assert numeric_push and check.start() < numeric_push.start(), (
        'The bounds check must occur before the numeric stack push.'
    )


def test_bounds_checking_via_expr_app():
    # Preserve the original required overflow check.
    output = run_app('1 2 3 4 5 + + + +')
    assert output == '-999', (
        f"Expected bounds check to return '-999' when stack size exceeds 4, but got '{output}'. "
        'Ensure eval.c returns -999 if sp >= 4 during a push.'
    )

    # Exercise additional unpredictable overflow inputs.
    rng = secrets.SystemRandom()
    for _ in range(12):
        values = [str(rng.randrange(0, 10000)) for _ in range(5)]
        expression = ' '.join(values + ['+', '+', '+', '+'])
        assert run_app(expression) == '-999', f'Overflow was not rejected for {expression!r}'


def test_valid_expression_evaluation():
    # Preserve the original prompt-expression assertion.
    output = run_app('10 5 2 * + 8 4 / - 3 +')
    assert output == '21', f"Expected valid expression to evaluate to '21', but got '{output}'."


def trunc_div(a, b):
    quotient = abs(a) // abs(b)
    return -quotient if (a < 0) != (b < 0) else quotient


def test_general_rpn_evaluator_behavior():
    rng = secrets.SystemRandom()
    for _ in range(40):
        total_pushes = rng.randrange(2, 8)
        pushes = 0
        stack = []
        tokens = []

        while pushes < total_pushes or len(stack) > 1:
            can_push = pushes < total_pushes and len(stack) < 4
            if can_push and (len(stack) < 2 or rng.randrange(2) == 0):
                value = rng.randrange(0, 10)
                tokens.append(str(value))
                stack.append(value)
                pushes += 1
                continue

            if len(stack) < 2:
                value = rng.randrange(0, 10)
                tokens.append(str(value))
                stack.append(value)
                pushes += 1
                continue

            b = stack.pop()
            a = stack.pop()
            operators = ['+', '-']
            if abs(a * b) < 100000000:
                operators.append('*')
            if b != 0:
                operators.append('/')
            op = rng.choice(operators)
            if op == '+':
                value = a + b
            elif op == '-':
                value = a - b
            elif op == '*':
                value = a * b
            else:
                value = trunc_div(a, b)
            tokens.append(op)
            stack.append(value)

        expression = ' '.join(tokens)
        expected = str(stack[0])
        assert run_app(expression) == expected, (
            f'Incorrect evaluation for generated RPN expression {expression!r}; expected {expected}.'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
