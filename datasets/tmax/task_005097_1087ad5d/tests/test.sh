#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import re
import subprocess
from pathlib import Path

import pytest

CPP_PATH = Path("/home/user/evaluator.cpp")
RESULT_PATH = Path("/home/user/result.txt")
BINARY_PATH = Path("/tmp/evaluator_submission")


def read_result():
    assert RESULT_PATH.is_file(), f"Failed: result file not found at {RESULT_PATH}"
    content = RESULT_PATH.read_text().strip()
    match = re.search(r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?', content)
    assert match is not None, f"Failed: No numerical value found in {RESULT_PATH}. Content: '{content}'"
    value = float(match.group(0))
    assert math.isfinite(value), f"Failed: non-finite result in {RESULT_PATH}"
    return value


def expected_value(expression):
    tree = ast.parse(expression, mode="eval")

    def evaluate(node):
        if isinstance(node, ast.Expression):
            return evaluate(node.body)
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            return float(node.value)
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            value = evaluate(node.operand)
            return value if isinstance(node.op, ast.UAdd) else -value
        if isinstance(node, ast.BinOp):
            left, right = evaluate(node.left), evaluate(node.right)
            if isinstance(node.op, ast.Add):
                return left + right
            if isinstance(node.op, ast.Sub):
                return left - right
            if isinstance(node.op, ast.Mult):
                return left * right
            if isinstance(node.op, ast.Div):
                return left / right
        raise AssertionError(f"Unsupported verifier expression node: {ast.dump(node)}")

    return evaluate(tree)


def run_submission(stdin_text=None, argv_expression=None):
    if RESULT_PATH.exists():
        RESULT_PATH.unlink()
    command = [str(BINARY_PATH)]
    if argv_expression is not None:
        command.append(argv_expression)
    completed = subprocess.run(
        command,
        input=stdin_text,
        text=True,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    if completed.returncode != 0:
        return None, completed
    if not RESULT_PATH.is_file():
        return None, completed
    try:
        return read_result(), completed
    except (AssertionError, ValueError, OverflowError):
        return None, completed


def test_evaluator_cpp_exists():
    """Test that the C++ program was created."""
    cpp_path = "/home/user/evaluator.cpp"
    assert os.path.isfile(cpp_path), f"Failed: C++ source file not found at {cpp_path}"
    assert os.path.getsize(cpp_path) > 0, f"Failed: C++ source file is empty at {cpp_path}"


def test_result_txt_metric():
    """Test that the result.txt contains the correct evaluated number within the threshold."""
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"Failed: result file not found at {result_path}"

    with open(result_path, "r") as f:
        content = f.read().strip()

    match = re.search(r'-?\d+(\.\d+)?', content)
    assert match is not None, f"Failed: No numerical value found in {result_path}. Content: '{content}'"

    value = float(match.group(0))
    target = 463.25
    error = abs(value - target)

    assert error <= 0.1, f"Failed: output {value} is outside threshold (error = {error}, expected <= 0.1)"


def test_source_contains_custom_ast_and_parser():
    source = CPP_PATH.read_text(errors="replace")
    declared_types = re.findall(r'\b(?:class|struct)\s+[A-Za-z_]\w*', source)
    ast_named_type = re.search(r'\b(?:class|struct)\s+\w*(?:AST|Node|Expr)\w*', source, re.IGNORECASE)
    assert ast_named_type or len(declared_types) >= 2, "Failed: no custom AST data structure was found"
    assert re.search(r'\bparse\w*\s*\(', source, re.IGNORECASE), "Failed: no parser implementation was found"
    assert re.search(r'\b(?:eval|evaluate)\w*\s*\(', source, re.IGNORECASE), "Failed: no AST evaluation implementation was found"
    for operator in "+-*/":
        assert operator in source, f"Failed: evaluator source does not handle the '{operator}' operator"
    assert "(" in source and ")" in source, "Failed: evaluator source does not contain parenthesis handling"


def test_compile_and_execute_fresh_result():
    completed = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-Wall", "-Wextra", str(CPP_PATH), "-o", str(BINARY_PATH)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, f"Failed to compile evaluator.cpp:\n{completed.stderr}"

    canonical = "42.5*(3.1+7.8)"
    value, run = run_submission(stdin_text=canonical + "\n")
    assert run.returncode == 0, f"Compiled evaluator failed to run:\n{run.stderr}"
    assert value is not None, "Failed: running the compiled evaluator did not freshly create a numeric result.txt"
    expected = expected_value(canonical)
    assert abs(value - expected) <= 0.1, f"Failed: freshly executed evaluator produced {value}, expected {expected}"


def test_parser_on_additional_expressions():
    probes = [
        "7+3*4",
        "(18.5-2.5)/4",
        "2.5*(8-3)+1.25",
        "20/4/2+0.75",
    ]
    for expression in probes:
        expected = expected_value(expression)
        attempts = [
            run_submission(stdin_text=expression + "\n"),
            run_submission(argv_expression=expression),
        ]
        values = [value for value, completed in attempts if completed.returncode == 0 and value is not None]
        assert values, f"Failed: evaluator could not evaluate supplied expression '{expression}' via stdin or argv"
        assert any(abs(value - expected) <= 1e-6 * max(1.0, abs(expected)) for value in values), (
            f"Failed: evaluator did not correctly parse '{expression}'; got {values}, expected {expected}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
