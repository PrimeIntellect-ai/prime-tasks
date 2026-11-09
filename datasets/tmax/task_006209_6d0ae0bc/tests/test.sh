#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import re
import subprocess
import sys
import pstats

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp
from scipy.interpolate import interp1d

HOME = "/home/user"


def load_integrator():
    path = f"{HOME}/integrator.py"
    assert os.path.isfile(path), f"File {path} does not exist."
    spec = importlib.util.spec_from_file_location("integrator", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["integrator"] = module
    try:
        spec.loader.exec_module(module)
    except Exception as exc:
        assert False, f"Failed to import {path}: {exc}"
    return module


def expected_observations():
    def vdp(t, y):
        mu = 1.5
        return [y[1], mu * (1 - y[0] ** 2) * y[1] - y[0]]

    np.random.seed(42)
    sol = solve_ivp(vdp, [0, 20], [2.0, 0.0], method="RK45",
                    rtol=1e-8, atol=1e-8, dense_output=True)
    t_obs = np.sort(np.random.uniform(0.1, 19.9, 50))
    y_obs = sol.sol(t_obs)
    return pd.DataFrame({
        "t": t_obs,
        "y0": y_obs[0] + np.random.normal(0, 0.01, len(t_obs)),
        "y1": y_obs[1] + np.random.normal(0, 0.01, len(t_obs)),
    })


def assert_observations_unchanged():
    path = f"{HOME}/obs_data.csv"
    assert os.path.isfile(path), f"File {path} does not exist."
    actual = pd.read_csv(path)
    expected = expected_observations()
    assert list(actual.columns) == ["t", "y0", "y1"]
    assert actual.shape == expected.shape
    assert np.allclose(actual.to_numpy(), expected.to_numpy(), rtol=0, atol=1e-10), \
        "obs_data.csv was modified."
    return actual


def test_integrator_fixed():
    integrator = load_integrator()
    assert hasattr(integrator, "adaptive_integrate"), "adaptive_integrate function missing."
    assert hasattr(integrator, "vdp_deriv"), "vdp_deriv function missing."

    # The supplied derivative function and parameters must not be changed.
    for t, y in [(0.0, [2.0, 0.0]), (1.2, [-1.1, 0.7]), (9.0, [0.2, -2.0])]:
        y = np.asarray(y, dtype=float)
        expected = np.array([y[1], 1.5 * (1 - y[0] ** 2) * y[1] - y[0]])
        assert np.allclose(integrator.vdp_deriv(t, y), expected, rtol=0, atol=1e-12)

    try:
        times, states = integrator.adaptive_integrate(
            integrator.vdp_deriv, 0.0, [2.0, 0.0], 20.0, tol=1e-5
        )
    except RuntimeError as exc:
        assert False, f"adaptive_integrate raised RuntimeError: {exc}."
    except Exception as exc:
        assert False, f"adaptive_integrate raised an unexpected error: {exc}"

    times = np.asarray(times)
    states = np.asarray(states)
    assert len(times) < 1000, f"Integration took too many steps ({len(times)}). Expected less than 1000."
    assert times[-1] >= 20.0, f"Integration did not reach t_end. Final time: {times[-1]}"
    assert times.ndim == 1 and states.shape == (len(times), 2)
    assert len(times) > 20, "Solver returned implausibly few numerical states."
    assert np.all(np.isfinite(times)) and np.all(np.isfinite(states))
    assert times[0] == 0.0 and np.allclose(states[0], [2.0, 0.0])
    assert abs(times[-1] - 20.0) < 1e-12
    assert np.all(np.diff(times) > 0), "Returned times must be strictly increasing."
    assert np.max(np.diff(times)) <= 1.0 + 1e-12, "Step size exceeded the 1.0 upper bound."

    # Compare every returned state with an independently computed high-accuracy solution.
    reference = solve_ivp(
        lambda t, y: [y[1], 1.5 * (1 - y[0] ** 2) * y[1] - y[0]],
        [0, 20], [2.0, 0.0], rtol=1e-11, atol=1e-12, dense_output=True
    )
    expected_states = reference.sol(times).T
    assert np.max(np.abs(states - expected_states)) < 0.01, \
        "Returned states do not numerically solve the requested Van der Pol problem."

    # Verify the actual h_new expression and the required clamp without depending on formatting.
    source = open(f"{HOME}/integrator.py", encoding="utf-8").read()
    tree = ast.parse(source)
    fn = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and
               n.name == "adaptive_integrate"), None)
    assert fn is not None
    h_new_assignments = [n for n in ast.walk(fn) if isinstance(n, ast.Assign) and
                         any(isinstance(t, ast.Name) and t.id == "h_new" for t in n.targets)]
    assert h_new_assignments, "adaptive_integrate does not compute h_new."
    expr = ast.Expression(h_new_assignments[-1].value)
    ast.fix_missing_locations(expr)
    for h, tol, error in [(0.4, 2e-5, 5e-4), (0.03, 1e-5, 2e-6)]:
        value = eval(compile(expr, "<h_new>", "eval"), {"np": np},
                     {"h": h, "tol": tol, "error": error})
        expected = h * (tol / error) ** 0.2 * 0.9
        assert np.isclose(value, expected, rtol=1e-12, atol=0), \
            "h_new does not use h * (tol / error)**0.2 * 0.9."

    clamp_found = False
    for node in ast.walk(fn):
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "h" for t in node.targets):
            names = {n.id for n in ast.walk(node.value) if isinstance(n, ast.Name)}
            constants = [float(n.value) for n in ast.walk(node.value)
                         if isinstance(n, ast.Constant) and isinstance(n.value, (int, float))]
            if "h_new" in names and any(np.isclose(x, 1e-5) for x in constants) and \
                    any(np.isclose(x, 1.0) for x in constants):
                clamp_found = True
    assert clamp_found, "The updated step size is not bounded between 1e-5 and 1.0."


def test_compare_script_and_mae():
    compare_path = f"{HOME}/compare.py"
    assert os.path.isfile(compare_path), f"Script {compare_path} does not exist."
    assert_observations_unchanged()

    source = open(compare_path, encoding="utf-8").read()
    tree = ast.parse(source)
    interpolation_calls = []
    call_names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            name = node.func.id if isinstance(node.func, ast.Name) else (
                node.func.attr if isinstance(node.func, ast.Attribute) else "")
            call_names.append(name)
            if name == "interp1d":
                interpolation_calls.append(node)
    assert interpolation_calls, "compare.py does not use scipy.interpolate.interp1d."
    assert any(any(k.arg == "kind" and isinstance(k.value, ast.Constant) and
                       k.value.value == "cubic" for k in call.keywords)
               for call in interpolation_calls), "interp1d must use cubic interpolation."
    assert "adaptive_integrate" in call_names, "compare.py does not run adaptive_integrate."
    assert "plot" in call_names and "scatter" in call_names, \
        "compare.py must create both the solver line and observational scatter plot."

    mae_log_path = f"{HOME}/mae.log"
    plot_path = f"{HOME}/plot.png"
    for path in (mae_log_path, plot_path):
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run([sys.executable, compare_path], cwd=HOME,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=120,
                            env={**os.environ, "MPLBACKEND": "Agg"})
    assert result.returncode == 0, f"compare.py failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert_observations_unchanged()

    assert os.path.isfile(mae_log_path), f"Log file {mae_log_path} does not exist."
    content = open(mae_log_path, encoding="utf-8").read().strip()
    try:
        mae_value = float(content)
    except ValueError:
        assert False, f"Contents of {mae_log_path} could not be parsed as a float. Found: {content}"
    assert np.isfinite(mae_value)
    assert mae_value < 0.05, f"MAE value {mae_value} is too high. Expected < 0.05."

    integrator = load_integrator()
    times, states = integrator.adaptive_integrate(
        integrator.vdp_deriv, 0.0, [2.0, 0.0], 20.0, tol=1e-5)
    obs = pd.read_csv(f"{HOME}/obs_data.csv")
    interpolated = interp1d(times, states, axis=0, kind="cubic")(obs["t"].to_numpy())
    expected_mae = np.mean(np.abs(interpolated - obs[["y0", "y1"]].to_numpy()))
    assert np.isclose(mae_value, expected_mae, rtol=1e-6, atol=1e-10), \
        f"mae.log is self-reported: found {mae_value}, independently computed {expected_mae}."


def test_plot_generated():
    plot_path = f"{HOME}/plot.png"
    assert os.path.isfile(plot_path), f"Plot file {plot_path} does not exist."
    with open(plot_path, "rb") as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f"File {plot_path} is not a valid PNG image."
    image = mpimg.imread(plot_path)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100
    assert np.all(np.isfinite(image)) and float(np.std(image)) > 0.01, \
        "plot.png does not contain a nontrivial rendered plot."


def test_profile_generated():
    profile_script_path = f"{HOME}/profile_run.py"
    assert os.path.isfile(profile_script_path), f"Script {profile_script_path} does not exist."
    source = open(profile_script_path, encoding="utf-8").read()
    tree = ast.parse(source)
    names = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name)}
    attrs = {n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute)}
    assert "cProfile" in names or "cProfile" in attrs, "profile_run.py does not use cProfile."
    assert "adaptive_integrate" in names or "adaptive_integrate" in attrs, \
        "profile_run.py does not run adaptive_integrate."

    profile_path = f"{HOME}/profile.prof"
    if os.path.exists(profile_path):
        os.remove(profile_path)
    result = subprocess.run([sys.executable, profile_script_path], cwd=HOME,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=120)
    assert result.returncode == 0, f"profile_run.py failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert os.path.isfile(profile_path), f"Profile output {profile_path} does not exist."
    try:
        stats = pstats.Stats(profile_path)
        assert stats.total_calls > 0, "Profile exists but appears to have recorded no calls."
    except Exception as exc:
        assert False, f"Failed to load {profile_path} as a valid cProfile output: {exc}"
    function_names = {key[2] for key in stats.stats}
    assert "adaptive_integrate" in function_names and "rk4_step" in function_names, \
        "Profile does not contain execution of the requested integrator."


def test_regression_test_script():
    test_script_path = f"{HOME}/test_integrator.py"
    assert os.path.isfile(test_script_path), f"Test script {test_script_path} does not exist."
    source = open(test_script_path, encoding="utf-8").read()
    tree = ast.parse(source)
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call)]
    call_names = [n.func.id if isinstance(n.func, ast.Name) else
                  (n.func.attr if isinstance(n.func, ast.Attribute) else "") for n in calls]
    assert "adaptive_integrate" in call_names and "vdp_deriv" in source, \
        "Regression test does not exercise adaptive_integrate on vdp_deriv."
    checks_limit = any(
        (isinstance(n, ast.Assert) and any(isinstance(x, ast.Constant) and x.value == 1000
                                          for x in ast.walk(n))) or
        (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and
         n.func.attr == "assertLess" and any(isinstance(x, ast.Constant) and x.value == 1000
                                             for x in ast.walk(n)))
        for n in ast.walk(tree)
    )
    assert checks_limit, "Regression test does not assert that the step count is less than 1000."

    result = subprocess.run([sys.executable, "-m", "unittest", test_script_path],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            timeout=120, cwd=HOME)
    assert result.returncode == 0, (
        f"unittest failed for {test_script_path}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    output = result.stdout + result.stderr
    match = re.search(r"Ran\s+(\d+)\s+tests?", output)
    assert match and int(match.group(1)) >= 1, "The unittest script contains no executed tests."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
