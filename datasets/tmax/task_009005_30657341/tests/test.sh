#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import contextlib
import importlib
import io
import os
import subprocess
import sys

PROJECT_DIR = "/home/user/project"
API_PY = os.path.join(PROJECT_DIR, "api.py")
MATH_OPS_PY = os.path.join(PROJECT_DIR, "math_ops.py")
UTILS_PY = os.path.join(PROJECT_DIR, "utils.py")
TEST_API_PY = os.path.join(PROJECT_DIR, "test_api.py")
RESOLUTION_TXT = "/home/user/resolution.txt"


def test_pytest_passes():
    """Verify that the requested test suite still passes."""
    assert os.path.isfile(TEST_API_PY), f"Test file {TEST_API_PY} is missing."
    result = subprocess.run(
        [sys.executable, "-m", "pytest", TEST_API_PY],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"pytest failed. Output:\n{result.stdout}\n{result.stderr}"


def test_utils_py_exists_and_has_logger():
    """Verify that utils.py was created and contains the logger function."""
    assert os.path.isfile(UTILS_PY), f"File {UTILS_PY} does not exist. Did you extract the logger component?"
    with open(UTILS_PY, "r") as f:
        content = f.read()
    assert "def logger" in content, f"{UTILS_PY} does not contain the 'logger' function definition."


def test_logger_removed_from_api_py():
    """Verify that logger is no longer defined in api.py."""
    assert os.path.isfile(API_PY), f"File {API_PY} does not exist."
    with open(API_PY, "r") as f:
        content = f.read()
    assert "def logger" not in content, f"{API_PY} still contains the 'logger' function definition. It should be moved to utils.py."


def test_resolution_txt():
    """Verify that resolution.txt names all files used to fix the bug."""
    assert os.path.isfile(RESOLUTION_TXT), f"File {RESOLUTION_TXT} does not exist."
    with open(RESOLUTION_TXT, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    expected_files = {"api.py", "math_ops.py", "utils.py"}
    actual_files = set(lines)
    missing = expected_files - actual_files
    assert not missing, f"{RESOLUTION_TXT} is missing the following required files: {missing}"


def _tree(path):
    with open(path, "r") as f:
        return ast.parse(f.read(), filename=path)


def _imports_logger_from_utils(tree):
    return any(
        isinstance(node, ast.ImportFrom)
        and node.module == "utils"
        and any(alias.name == "logger" for alias in node.names)
        for node in ast.walk(tree)
    )


def test_static_dependency_graph():
    """Verify both modules use the extracted logger and math_ops no longer imports api."""
    api_tree = _tree(API_PY)
    math_tree = _tree(MATH_OPS_PY)
    utils_tree = _tree(UTILS_PY)

    assert _imports_logger_from_utils(api_tree), "api.py must import logger from utils.py"
    assert _imports_logger_from_utils(math_tree), "math_ops.py must import logger from utils.py"
    assert not any(
        (isinstance(node, ast.ImportFrom) and node.module == "api")
        or (isinstance(node, ast.Import) and any(alias.name == "api" for alias in node.names))
        for node in ast.walk(math_tree)
    ), "math_ops.py still imports api.py, preserving the circular dependency"
    assert any(
        isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "logger"
        for node in ast.walk(utils_tree)
    ), "utils.py must define logger"


def test_modules_import_in_either_order_without_cycle():
    """Exercise fresh imports independently of the agent-modifiable test file."""
    for order in [("api", "math_ops", "utils"), ("math_ops", "api", "utils")]:
        code = f'''\nimport importlib, os, sys\nsys.path.insert(0, {PROJECT_DIR!r})\nos.chdir({PROJECT_DIR!r})\nmods = {{name: importlib.import_module(name) for name in {order!r}}}\napi = importlib.import_module("api")\nmath_ops = importlib.import_module("math_ops")\nutils = importlib.import_module("utils")\nassert api.logger is utils.logger\nassert math_ops.logger is utils.logger\n'''
        result = subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, (
            f"Modules failed to import in order {order}:\n{result.stdout}\n{result.stderr}"
        )


def _load_modules():
    if PROJECT_DIR not in sys.path:
        sys.path.insert(0, PROJECT_DIR)
    for name in ("api", "math_ops", "utils"):
        sys.modules.pop(name, None)
    api = importlib.import_module("api")
    math_ops = importlib.import_module("math_ops")
    utils = importlib.import_module("utils")
    return api, math_ops, utils


def _reference_matrix_multiply(a, b):
    columns = len(b[0])
    shared = len(b)
    return [
        [sum(a[i][k] * b[k][j] for k in range(shared)) for j in range(columns)]
        for i in range(len(a))
    ]


def _reference_nonnegative_power(base, exponent):
    result = 1
    for _ in range(exponent):
        result *= base
    return result


def test_real_algorithm_and_api_behavior():
    """Test the submitted modules directly rather than trusting test_api.py."""
    api, math_ops, utils = _load_modules()

    matrix_cases = [
        ([[1, 2], [3, 4]], [[5, 6], [7, 8]]),
        ([[2, -1, 3]], [[4, 2], [0, 5], [-2, 7]]),
        ([[3], [-4], [6]], [[2, -5, 1]]),
    ]
    for left, right in matrix_cases:
        assert math_ops.matrix_multiply(left, right) == _reference_matrix_multiply(left, right)

    for base, exponent in [(2, 10), (-3, 5), (7, 0), (5, 4)]:
        assert math_ops.fast_exp(base, exponent) == _reference_nonnegative_power(base, exponent)

    assert api.run_api() == _reference_matrix_multiply(
        [[1, 2], [3, 4]], [[5, 6], [7, 8]]
    )
    assert api.fast_exp_api() == _reference_nonnegative_power(2, 10)
    assert api.logger is utils.logger
    assert math_ops.logger is utils.logger

    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        utils.logger("probe")
    assert output.getvalue().strip() == "LOG: probe"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
