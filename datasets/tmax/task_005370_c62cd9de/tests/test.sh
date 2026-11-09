#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import ast
import importlib.util
import math
import os
import re
import secrets
import subprocess
import sys

import numpy as np

APP_DIR = "/home/user/app"
COMPUTATION_PY = os.path.join(APP_DIR, "computation.py")
ENV_SH = os.path.join(APP_DIR, "env.sh")
TEST_COMPUTATION_PY = os.path.join(APP_DIR, "test_computation.py")
TEST_RESULTS_LOG = os.path.join(APP_DIR, "test_results.log")


def load_computation():
    spec = importlib.util.spec_from_file_location("verified_computation", COMPUTATION_PY)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expected_lse(values):
    values = [float(v) for v in values]
    maximum = max(values)
    return maximum + math.log(math.fsum(math.exp(v - maximum) for v in values))


def check_computation():
    assert os.path.isfile(COMPUTATION_PY), f"File missing: {COMPUTATION_PY}"
    with open(COMPUTATION_PY, "r", encoding="utf-8") as handle:
        content = handle.read()

    # Preserve the original source-level assertion that a maximum shift is present.
    assert "max" in content, "The log-sum-exp trick requires finding the maximum value."

    computation = load_computation()
    assert callable(getattr(computation, "compute_log_sum_exp", None))

    fixed_cases = [
        ([1000.0, 1000.0], 1000.6931471805599),
        ([5000.0, 5001.0], 5001.313261687518),
    ]
    for values, expected in fixed_cases:
        result = float(computation.compute_log_sum_exp(np.array(values, dtype=float)))
        assert np.isfinite(result), f"compute_log_sum_exp overflowed for {values}"
        assert np.isclose(result, expected), f"Incorrect result for {values}: {result}"

    # Unpredictable cases prevent implementations hardcoded to the two examples.
    rng = np.random.default_rng(secrets.randbits(128))
    for _ in range(20):
        length = int(rng.integers(2, 40))
        base = float(rng.uniform(-20000.0, 20000.0))
        values = base + rng.normal(0.0, float(rng.uniform(0.01, 80.0)), size=length)
        expected = expected_lse(values)
        result = float(computation.compute_log_sum_exp(values.copy()))
        assert math.isfinite(result), f"Non-finite result for generated input: {result}"
        assert math.isclose(result, expected, rel_tol=1e-12, abs_tol=1e-9), (
            f"Incorrect generated-case result: expected {expected}, got {result}"
        )


def check_environment():
    assert os.path.isfile(ENV_SH), f"File missing: {ENV_SH}"
    expected_vars = [
        "OMP_NUM_THREADS",
        "OPENBLAS_NUM_THREADS",
        "MKL_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS",
        "NUMEXPR_NUM_THREADS",
    ]

    with open(ENV_SH, "r", encoding="utf-8") as handle:
        content = handle.read()
    # Preserve the original textual assertions.
    for var in expected_vars:
        assert f"{var}=4" in content, f"Expected {var}=4 in {ENV_SH}"

    command = (
        'source "$1"; '
        'printf "__ENV__%s|%s|%s|%s|%s\\n" '
        '"$OMP_NUM_THREADS" "$OPENBLAS_NUM_THREADS" "$MKL_NUM_THREADS" '
        '"$VECLIB_MAXIMUM_THREADS" "$NUMEXPR_NUM_THREADS"'
    )
    proc = subprocess.run(
        ["env", "-i", "PATH=/usr/local/bin:/usr/bin:/bin", "HOME=/tmp",
         "bash", "--noprofile", "--norc", "-c", command, "verify-env", ENV_SH],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert proc.returncode == 0, f"env.sh could not be sourced: {proc.stderr}"
    marker_lines = [line for line in proc.stdout.splitlines() if line.startswith("__ENV__")]
    assert marker_lines, "Could not read active thread settings after sourcing env.sh"
    active_values = marker_lines[-1][len("__ENV__"):].split("|")
    assert active_values == ["4"] * len(expected_vars), (
        f"Active thread settings are not all exactly 4: {dict(zip(expected_vars, active_values))}"
    )


def run_pytest(node=None):
    target = TEST_COMPUTATION_PY if node is None else f"{TEST_COMPUTATION_PY}::{node}"
    return subprocess.run(
        [sys.executable, "-m", "pytest", "-q", target],
        cwd=APP_DIR,
        text=True,
        capture_output=True,
        timeout=60,
    )


def make_naive_version(original):
    tree = ast.parse(original, filename=COMPUTATION_PY)
    found = False
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "compute_log_sum_exp":
            expression = ast.parse("np.log(np.sum(np.exp(x)))", mode="eval").body
            node.body = [ast.Return(value=expression)]
            found = True
            break
    assert found, "compute_log_sum_exp definition is missing"
    ast.fix_missing_locations(tree)
    return ast.unparse(tree) + "\n"


def check_regression_tests():
    assert os.path.isfile(TEST_COMPUTATION_PY), f"File missing: {TEST_COMPUTATION_PY}"
    with open(TEST_COMPUTATION_PY, "r", encoding="utf-8") as handle:
        test_content = handle.read()

    # Preserve the original content assertions.
    assert "test_log_sum_exp" in test_content, "test_log_sum_exp missing"
    assert "test_log_sum_exp_large" in test_content, "test_log_sum_exp_large missing"
    assert "computation" in test_content, "computation module not imported"
    assert "np.isclose" in test_content, "The regression tests must use np.isclose"

    tree = ast.parse(test_content, filename=TEST_COMPUTATION_PY)
    function_names = {
        node.name for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    for name in ("test_log_sum_exp", "test_log_sum_exp_large"):
        assert name in function_names, f"Required pytest function {name} is not defined"

    # Actually execute the submitted tests and require both requested tests to pass.
    for name in ("test_log_sum_exp", "test_log_sum_exp_large"):
        proc = run_pytest(name)
        output = proc.stdout + proc.stderr
        assert proc.returncode == 0, f"{name} does not pass:\n{output}"
        assert re.search(r"\b1 passed\b", output), f"{name} was not executed successfully:\n{output}"

    # Each submitted test must detect the original unstable implementation.
    with open(COMPUTATION_PY, "r", encoding="utf-8") as handle:
        original = handle.read()
    naive = make_naive_version(original)
    try:
        with open(COMPUTATION_PY, "w", encoding="utf-8") as handle:
            handle.write(naive)
        for name in ("test_log_sum_exp", "test_log_sum_exp_large"):
            proc = run_pytest(name)
            output = proc.stdout + proc.stderr
            assert proc.returncode != 0 and re.search(r"\b1 failed\b", output), (
                f"{name} does not catch the original overflow regression:\n{output}"
            )
    finally:
        with open(COMPUTATION_PY, "w", encoding="utf-8") as handle:
            handle.write(original)


def check_results_log():
    assert os.path.isfile(TEST_RESULTS_LOG), (
        f"File missing: {TEST_RESULTS_LOG}. Did you run pytest and redirect the output?"
    )
    with open(TEST_RESULTS_LOG, "r", encoding="utf-8", errors="replace") as handle:
        content = handle.read()
    assert len(content.strip()) > 0, f"{TEST_RESULTS_LOG} is empty."
    matches = re.findall(r"\b(\d+) passed\b", content)
    assert matches and max(map(int, matches)) >= 2, (
        "test_results.log does not show a pytest run with both required tests passing"
    )
    lowered = content.lower()
    assert not re.search(r"\b(?:failed|errors?)\b", lowered), (
        "test_results.log reports test failures or errors"
    )
    log_mtime = os.stat(TEST_RESULTS_LOG).st_mtime_ns
    assert log_mtime >= os.stat(COMPUTATION_PY).st_mtime_ns
    assert log_mtime >= os.stat(TEST_COMPUTATION_PY).st_mtime_ns


check_computation()
check_environment()
check_regression_tests()
check_results_log()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
