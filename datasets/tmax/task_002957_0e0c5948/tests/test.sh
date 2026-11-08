#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import math
import os
import re
import secrets
import subprocess
import sys

LIB_DIR = "/home/user/optimization_lib"
SOLVER_FILE = os.path.join(LIB_DIR, "solver.py")
REGRESSION_FILE = os.path.join(LIB_DIR, "tests", "test_regression.py")


def load_solver():
    name = "audited_solver_" + secrets.token_hex(8)
    spec = importlib.util.spec_from_file_location(name, SOLVER_FILE)
    assert spec is not None and spec.loader is not None, "solver.py is not importable."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_solver_bug_fixed():
    assert os.path.isfile(SOLVER_FILE), f"File {SOLVER_FILE} does not exist."

    with open(SOLVER_FILE, "r") as f:
        content = f.read()

    assert "x = x + fx / dfx" not in content, "The bug 'x = x + fx / dfx' is still present in solver.py."

    fixed_pattern = re.compile(r"x\s*=\s*x\s*-\s*fx\s*/\s*dfx|x\s*-=\s*fx\s*/\s*dfx")
    assert fixed_pattern.search(content), "The update step in solver.py was not correctly fixed to subtraction."


def test_solver_performs_newton_updates_on_runtime_inputs():
    solver = load_solver()
    assert callable(getattr(solver, "newton_root_finder", None))

    rng = secrets.SystemRandom()
    for _ in range(6):
        root_expected = rng.uniform(0.8, 3.5)
        a = rng.uniform(0.7, 4.0)
        x0 = root_expected + rng.uniform(0.25, 1.1)
        tol = 1e-10
        max_iter = 30

        # This nonlinear function has a simple root at root_expected. Its
        # parameters are generated only when verification runs.
        def raw_f(x, r=root_expected, c=a):
            return (x - r) * (x * x + c)

        def raw_df(x, r=root_expected, c=a):
            return 3 * x * x - 2 * r * x + c

        expected_points = []
        x = x0
        expected_result = None
        for i in range(max_iter):
            expected_points.append(x)
            fx = raw_f(x)
            if abs(fx) < tol:
                expected_result = (x, i)
                break
            x = x - fx / raw_df(x)
        assert expected_result is not None

        observed_points = []

        def traced_f(x):
            observed_points.append(x)
            return raw_f(x)

        result = solver.newton_root_finder(traced_f, raw_df, x0, tol=tol, max_iter=max_iter)
        assert isinstance(result, tuple) and len(result) == 2
        actual_root, actual_iters = result
        expected_root, expected_iters = expected_result
        assert actual_iters == expected_iters
        assert math.isclose(actual_root, expected_root, rel_tol=1e-12, abs_tol=1e-12)
        assert len(observed_points) == len(expected_points)
        for actual, expected in zip(observed_points, expected_points):
            assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
                "newton_root_finder did not use the Newton-Raphson update sequence"
            )


def test_regression_test_file_exists():
    assert os.path.isfile(REGRESSION_FILE), f"Regression test file {REGRESSION_FILE} is missing."


def test_regression_test_content():
    assert os.path.isfile(REGRESSION_FILE), f"Regression test file {REGRESSION_FILE} is missing."

    with open(REGRESSION_FILE, "r") as f:
        content = f.read()

    assert "def test_regression_quadratic" in content, "Function 'test_regression_quadratic' missing in test_regression.py."
    assert "9" in content, "The function f(x) = x^2 - 9 does not seem to be defined."
    assert "5.0" in content or "5" in content, "The initial value x0 = 5.0 does not seem to be used."
    assert "10" in content, "The assertion for iterations < 10 is missing."


def run_regression_with_result(result):
    sys.path.insert(0, "/home/user")
    try:
        import optimization_lib.solver as package_solver
        calls = []

        def fake_finder(f, df, x0, *args, **kwargs):
            calls.append((f, df, x0))
            return result

        original = package_solver.newton_root_finder
        package_solver.newton_root_finder = fake_finder
        try:
            name = "audited_regression_" + secrets.token_hex(8)
            spec = importlib.util.spec_from_file_location(name, REGRESSION_FILE)
            assert spec is not None and spec.loader is not None
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            test_function = getattr(module, "test_regression_quadratic", None)
            assert callable(test_function), "test_regression_quadratic is not callable."
            test_function()
        finally:
            package_solver.newton_root_finder = original

        assert len(calls) == 1, "Regression test must call newton_root_finder once."
        f, df, x0 = calls[0]
        assert x0 == 5.0, "Regression test must start at x0 = 5.0."
        for x in (-2.5, 0.0, 4.0):
            assert math.isclose(f(x), x * x - 9, rel_tol=0, abs_tol=1e-12), "Regression test uses the wrong function."
            assert math.isclose(df(x), 2 * x, rel_tol=0, abs_tol=1e-12), "Regression test uses the wrong derivative."
    finally:
        if sys.path and sys.path[0] == "/home/user":
            sys.path.pop(0)


def test_regression_test_has_required_assertions():
    # A compliant result must pass.
    run_regression_with_result((3.0, 9))

    # Values violating each required bound must be rejected by the authored test.
    try:
        run_regression_with_result((3.001, 1))
    except AssertionError:
        pass
    else:
        raise AssertionError("Regression test does not assert that the root is within 1e-4 of 3.0.")

    try:
        run_regression_with_result((3.0, 10))
    except AssertionError:
        pass
    else:
        raise AssertionError("Regression test does not assert that iterations are strictly less than 10.")


def test_pytest_passes():
    target_dir = "/home/user/optimization_lib"
    assert os.path.isdir(target_dir), f"Directory {target_dir} is missing."

    result = subprocess.run(
        ["pytest", target_dir],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"pytest failed. Output:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
