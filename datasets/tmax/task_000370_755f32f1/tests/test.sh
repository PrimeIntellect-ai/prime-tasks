#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import inspect
import math
import os
import subprocess

EXPECTED_DATA = [100000001.0, 100000002.0, 100000003.0, 100000004.0, 100000005.0]


def test_buggy_line_num():
    path = "/home/user/buggy_line_num.txt"
    assert os.path.isfile(path), f"Expected file {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "3456", f"Expected buggy line number to be '3456', but got '{content}'."


def _is_name(node, name):
    return isinstance(node, ast.Name) and node.id == name


def _is_number(node, value):
    return isinstance(node, ast.Constant) and node.value == value


def _is_sum_of_squares(node):
    if not (isinstance(node, ast.Call) and _is_name(node.func, "sum") and len(node.args) == 1):
        return False
    sequence = node.args[0]
    if not isinstance(sequence, (ast.ListComp, ast.GeneratorExp)) or len(sequence.generators) != 1:
        return False
    generator = sequence.generators[0]
    if generator.ifs or generator.is_async or not _is_name(generator.target, "x") or not _is_name(generator.iter, "data"):
        return False
    element = sequence.elt
    return (
        isinstance(element, ast.BinOp)
        and isinstance(element.op, ast.Pow)
        and _is_name(element.left, "x")
        and _is_number(element.right, 2)
    )


def test_mre_py():
    path = "/home/user/mre.py"
    assert os.path.isfile(path), f"Expected MRE script {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original external-file and hardcoded-data checks.
    assert "open(" not in content, "MRE script should not read external files (found 'open(')."
    assert "100000001.0" in content and "100000005.0" in content, "MRE script does not seem to hardcode the buggy data."
    assert "data" in content, "MRE script must define a variable named 'data'."

    tree = ast.parse(content, filename=path)

    # Require a literal list of the exact five floats, assigned to the required name.
    data_assignments = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if any(_is_name(target, "data") for target in targets):
                try:
                    value = ast.literal_eval(node.value)
                except (ValueError, TypeError):
                    continue
                data_assignments.append(value)
    assert any(
        isinstance(value, list)
        and value == EXPECTED_DATA
        and all(type(item) is float for item in value)
        for value in data_assignments
    ), "MRE must assign the exact buggy sequence as a literal list of floats named 'data'."

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            assignments.setdefault(node.targets[0].id, []).append(node.value)

    has_n = any(
        isinstance(expr, ast.Call)
        and _is_name(expr.func, "len")
        and len(expr.args) == 1
        and _is_name(expr.args[0], "data")
        for expr in assignments.get("n", [])
    )
    assert has_n, "MRE is missing the buggy calculation's n = len(data) step."

    has_mean = any(
        isinstance(expr, ast.BinOp)
        and isinstance(expr.op, ast.Div)
        and isinstance(expr.left, ast.Call)
        and _is_name(expr.left.func, "sum")
        and len(expr.left.args) == 1
        and _is_name(expr.left.args[0], "data")
        and _is_name(expr.right, "n")
        for expr in assignments.get("mean", [])
    )
    assert has_mean, "MRE is missing the buggy calculation's mean = sum(data) / n step."

    has_variance = any(
        isinstance(expr, ast.BinOp)
        and isinstance(expr.op, ast.Sub)
        and isinstance(expr.left, ast.BinOp)
        and isinstance(expr.left.op, ast.Div)
        and _is_sum_of_squares(expr.left.left)
        and _is_name(expr.left.right, "n")
        and isinstance(expr.right, ast.BinOp)
        and isinstance(expr.right.op, ast.Pow)
        and _is_name(expr.right.left, "mean")
        and _is_number(expr.right.right, 2)
        for expr in assignments.get("variance", [])
    )
    assert has_variance, "MRE must contain the naive variance calculation from process_data.py."

    has_sqrt_variance = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and _is_name(node.func.value, "math")
        and node.func.attr == "sqrt"
        and len(node.args) == 1
        and _is_name(node.args[0], "variance")
        for node in ast.walk(tree)
    )
    assert has_sqrt_variance, "MRE must pass the naively calculated variance to math.sqrt."

    # Preserve the original execution assertions.
    result = subprocess.run(["python3", path], capture_output=True, text=True, timeout=10)
    assert result.returncode != 0, "MRE script should crash, but it exited successfully."
    assert "ValueError" in result.stderr, "MRE script should raise a ValueError."

    # Execute under observation and verify that the uncaught exception is the one
    # produced by math.sqrt on the negative variance derived for the exact data.
    n = len(EXPECTED_DATA)
    mean = sum(EXPECTED_DATA) / n
    expected_variance = sum([x ** 2 for x in EXPECTED_DATA]) / n - mean ** 2
    assert expected_variance < 0

    real_sqrt = math.sqrt
    calls = []
    generated_errors = []

    def observed_sqrt(value):
        caller = inspect.currentframe().f_back
        runtime_data = caller.f_locals.get("data", caller.f_globals.get("data"))
        calls.append((value, runtime_data))
        try:
            return real_sqrt(value)
        except ValueError as exc:
            generated_errors.append(exc)
            raise

    caught = None
    math.sqrt = observed_sqrt
    try:
        namespace = {"__name__": "__main__", "__file__": path}
        exec(compile(content, path, "exec"), namespace, namespace)
    except BaseException as exc:
        caught = exc
    finally:
        math.sqrt = real_sqrt

    assert calls, "MRE did not execute math.sqrt."
    assert any(
        value == expected_variance
        and isinstance(runtime_data, list)
        and runtime_data == EXPECTED_DATA
        and all(type(item) is float for item in runtime_data)
        for value, runtime_data in calls
    ), "MRE did not call math.sqrt with the naive variance of the exact buggy data."
    assert generated_errors and caught is generated_errors[-1], "The uncaught ValueError must come directly from math.sqrt."
    assert type(caught) is ValueError and str(caught) == "math domain error"


def test_stable_result():
    path = "/home/user/stable_result.txt"
    assert os.path.isfile(path), f"Expected file {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "1.4142", f"Expected stable result to be '1.4142', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
