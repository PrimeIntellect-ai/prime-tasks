#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import subprocess
import sys
import textwrap

import numpy as np
import pytest


def test_bootstrap_results():
    file_path = "/home/user/bootstrap_results.json"
    assert os.path.isfile(file_path), f"Missing required file: {file_path}"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert "lower_bound" in data, f"Missing 'lower_bound' key in {file_path}"
    assert "upper_bound" in data, f"Missing 'upper_bound' key in {file_path}"

    lower = data["lower_bound"]
    upper = data["upper_bound"]

    assert isinstance(lower, (int, float)), f"'lower_bound' must be a number, got {type(lower)}"
    assert isinstance(upper, (int, float)), f"'upper_bound' must be a number, got {type(upper)}"

    # Check bounds against expected values with a tolerance of 0.1
    expected_lower = 49.03
    expected_upper = 50.18

    assert abs(lower - expected_lower) <= 0.1, f"'lower_bound' {lower} is not within 0.1 of expected {expected_lower}"
    assert abs(upper - expected_upper) <= 0.1, f"'upper_bound' {upper} is not within 0.1 of expected {expected_upper}"


def test_bvp_result():
    file_path = "/home/user/bvp_result.txt"
    assert os.path.isfile(file_path), f"Missing required file: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "4.5000", f"Expected content of {file_path} to be '4.5000', got '{content}'"


def _call_name(call):
    node = call.func
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return ".".join(reversed(parts))


def _contains_number(node, value):
    return any(isinstance(n, ast.Constant) and n.value == value for n in ast.walk(node))


def _sampling_calls(node):
    allowed = {"choice", "randint", "integers"}
    return [n for n in ast.walk(node) if isinstance(n, ast.Call) and _call_name(n).split(".")[-1] in allowed]


def _statement_lists(node):
    for _field, value in ast.iter_fields(node):
        if isinstance(value, list) and value and all(isinstance(x, ast.stmt) for x in value):
            yield value
            for statement in value:
                yield from _statement_lists(statement)
        elif isinstance(value, ast.AST):
            yield from _statement_lists(value)


def _validate_bootstrap_source(path):
    with open(path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)

    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call)]
    percentile_calls = [c for c in calls if _call_name(c).split(".")[-1] == "percentile"]
    assert percentile_calls, "Bootstrap script must call numpy.percentile"
    percentile_numbers = {
        n.value
        for call in percentile_calls
        for n in ast.walk(call)
        if isinstance(n, ast.Constant) and isinstance(n.value, (int, float))
    }
    assert 2.5 in percentile_numbers and 97.5 in percentile_numbers, \
        "Bootstrap script must request the 2.5th and 97.5th percentiles"

    found_seed_then_resample = False
    for statements in _statement_lists(tree):
        for index, statement in enumerate(statements[:-1]):
            seed_calls = [
                c for c in ast.walk(statement)
                if isinstance(c, ast.Call)
                and _call_name(c).split(".")[-1] == "seed"
                and c.args
                and isinstance(c.args[0], ast.Constant)
                and c.args[0].value == 42
            ]
            if not seed_calls:
                continue
            next_statement = statements[index + 1]
            if _sampling_calls(next_statement) and _contains_number(next_statement, 10000):
                found_seed_then_resample = True

    assert found_seed_then_resample, \
        "numpy.random.seed(42) must be immediately followed by a 10,000-resample loop or vectorized resampling statement"

    for call in _sampling_calls(tree):
        if _call_name(call).split(".")[-1] == "choice":
            replace_keywords = [kw for kw in call.keywords if kw.arg == "replace"]
            if replace_keywords:
                assert isinstance(replace_keywords[0].value, ast.Constant) and replace_keywords[0].value.value is True, \
                    "numpy choice sampling must use replacement"


def test_bootstrap_script_exists_and_executes_on_changed_data():
    candidates = [
        p for p in glob.glob("/home/user/*.py")
        if os.path.basename(p) != "solve_bvp_pde.py" and os.path.isfile(p)
    ]
    assert candidates, "Missing the Python script for the bootstrap analysis"

    historical = "/home/user/historical_runs.txt"
    output = "/home/user/bootstrap_results.json"
    original_history = open(historical, "rb").read()
    original_output = open(output, "rb").read() if os.path.exists(output) else None
    successful = []

    try:
        with open(historical, "w", encoding="utf-8") as f:
            f.write("7\n" * 23)

        for candidate in candidates:
            if os.path.exists(output):
                os.remove(output)
            try:
                result = subprocess.run(
                    [sys.executable, candidate], cwd="/home/user",
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=30
                )
            except (subprocess.SubprocessError, OSError):
                continue
            if result.returncode != 0 or not os.path.isfile(output):
                continue
            try:
                with open(output, "r", encoding="utf-8") as f:
                    data = json.load(f)
                if set(data) == {"lower_bound", "upper_bound"} and data["lower_bound"] == 7.0 and data["upper_bound"] == 7.0:
                    _validate_bootstrap_source(candidate)
                    successful.append(candidate)
            except (ValueError, OSError, AssertionError):
                continue

        assert successful, \
            "No bootstrap Python script regenerated the required result from changed historical data using the prescribed NumPy procedure"
    finally:
        with open(historical, "wb") as f:
            f.write(original_history)
        if original_output is None:
            if os.path.exists(output):
                os.remove(output)
        else:
            with open(output, "wb") as f:
                f.write(original_output)


def test_bvp_script_executes_with_required_solver_and_mesh(tmp_path):
    script = "/home/user/solve_bvp_pde.py"
    output = "/home/user/bvp_result.txt"
    assert os.path.isfile(script), f"Missing required Python script: {script}"

    trace = tmp_path / "bvp_trace.npz"
    runner = tmp_path / "run_bvp_instrumented.py"
    runner.write_text(textwrap.dedent(f"""
        import runpy
        import numpy as np
        import scipy.integrate as integrate

        real_solve_bvp = integrate.solve_bvp
        record = {{"count": 0, "sol_points": []}}

        class SolutionProxy:
            def __init__(self, wrapped):
                self._wrapped = wrapped
            def __getattr__(self, name):
                return getattr(self._wrapped, name)
            def sol(self, x, *args, **kwargs):
                record["sol_points"].extend(np.asarray(x, dtype=float).reshape(-1).tolist())
                return self._wrapped.sol(x, *args, **kwargs)

        def checked_solve_bvp(fun, bc, x, y, *args, **kwargs):
            record["count"] += 1
            record["x"] = np.asarray(x, dtype=float).copy()
            record["y"] = np.asarray(y, dtype=float).copy()
            probe_x = np.array([0.2, 0.4, 0.5, 0.6, 0.8])
            probe_y = np.array([[1., 2., 3., 4., 5.], [6., 7., 8., 9., 10.]])
            record["fun"] = np.asarray(fun(probe_x, probe_y), dtype=float)
            record["bc"] = np.asarray(bc(np.array([2., 3.]), np.array([5., 7.])), dtype=float)
            return SolutionProxy(real_solve_bvp(fun, bc, x, y, *args, **kwargs))

        integrate.solve_bvp = checked_solve_bvp
        runpy.run_path({script!r}, run_name="__main__")
        np.savez(
            {str(trace)!r}, count=record["count"], x=record["x"], y=record["y"],
            fun=record["fun"], bc=record["bc"],
            sol_points=np.asarray(record["sol_points"], dtype=float)
        )
    """), encoding="utf-8")

    original_output = open(output, "rb").read() if os.path.exists(output) else None
    try:
        if os.path.exists(output):
            os.remove(output)
        result = subprocess.run(
            [sys.executable, str(runner)], cwd="/home/user",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
        )
        assert result.returncode == 0, f"BVP script failed when executed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(output), "BVP script did not create /home/user/bvp_result.txt"
        assert open(output, "r", encoding="utf-8").read().strip() == "4.5000"
        assert trace.is_file(), "BVP script never completed its solve_bvp call"

        with np.load(trace) as data:
            assert int(data["count"]) == 1, "BVP script must call scipy.integrate.solve_bvp once"
            expected_x = np.concatenate([
                np.linspace(0.0, 0.4, 11),
                np.linspace(0.4, 0.6, 51)[1:],
                np.linspace(0.6, 1.0, 11)[1:],
            ])
            assert data["x"].shape == (71,)
            assert np.allclose(data["x"], expected_x, rtol=0, atol=1e-12), \
                "Initial solve_bvp mesh is not the required 71-point decomposed mesh"
            assert data["y"].shape == (2, 71)
            assert np.array_equal(data["y"], np.zeros((2, 71))), \
                "Initial guesses for u and u' must both be zero"
            expected_fun = np.array([
                [6., 7., 8., 9., 10.],
                [0., -100., -100., -100., 0.],
            ])
            assert np.allclose(data["fun"], expected_fun), "The differential equation or localized heat source is incorrect"
            assert np.allclose(data["bc"], [2., 5.]), "Boundary conditions must enforce u(0)=0 and u(1)=0"
            assert np.any(np.isclose(data["sol_points"], 0.5)), \
                "The computed solution object's sol method was not evaluated at x=0.5"
    finally:
        if original_output is None:
            if os.path.exists(output):
                os.remove(output)
        else:
            with open(output, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
