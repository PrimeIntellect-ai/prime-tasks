#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import ast
import json
import math
import os
import pstats
import runpy
import signal
import sys
import inspect

import numpy as np
import scipy.integrate

SCRIPT = "/home/user/optimize.py"
MEASUREMENTS = "/home/user/measurements.txt"
PROFILE = "/home/user/profile.out"
OUTPUT = "/home/user/final_state.json"

assert os.path.isfile(SCRIPT), f"Script not found: {SCRIPT}"

with open(SCRIPT, "r", encoding="utf-8") as f:
    source = f.read()
tree = ast.parse(source, filename=SCRIPT)
assert any(isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "dump_stats" for n in ast.walk(tree)), "optimize.py must use dump_stats()"

with open(MEASUREMENTS, "r", encoding="utf-8") as f:
    original_measurements = f.read()

real_solve_ivp = scipy.integrate.solve_ivp
solve_signature = inspect.signature(real_solve_ivp)

def expected_state(y0, y1, mu, t_end):
    equilibrium = (y0 + mu * y1) / (mu + 1.0)
    transient = (y0 - y1) * math.exp(-(mu + 1.0) * t_end)
    return (
        equilibrium + mu * transient / (mu + 1.0),
        equilibrium - transient / (mu + 1.0),
    )

def run_and_check(y0, y1, mu, t_end):
    for path in (PROFILE, OUTPUT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    calls = []

    def verifier_solve_ivp_probe(*args, **kwargs):
        bound = solve_signature.bind(*args, **kwargs)
        bound.apply_defaults()
        calls.append(dict(bound.arguments))
        return real_solve_ivp(*args, **kwargs)

    scipy.integrate.solve_ivp = verifier_solve_ivp_probe
    old_argv = sys.argv
    old_cwd = os.getcwd()
    try:
        sys.argv = [SCRIPT]
        os.chdir("/home/user")
        try:
            runpy.run_path(SCRIPT, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"optimize.py exited with status {exc.code}"
    finally:
        scipy.integrate.solve_ivp = real_solve_ivp
        sys.argv = old_argv
        os.chdir(old_cwd)

    assert calls, "optimize.py did not call scipy.integrate.solve_ivp"
    matching = []
    for call in calls:
        try:
            span = tuple(float(x) for x in call["t_span"])
            initial = np.asarray(call["y0"], dtype=float)
            method = call["method"]
            method_name = method if isinstance(method, str) else getattr(method, "__name__", "")
            rtol = float(call["rtol"])
            atol = float(call["atol"])
            if (len(span) == 2 and abs(span[0]) < 1e-14 and abs(span[1] - t_end) < 1e-12
                    and initial.shape == (2,)
                    and np.allclose(initial, [y0, y1], rtol=0, atol=1e-12)
                    and str(method_name).upper() in {"BDF", "RADAU", "LSODA"}
                    and math.isclose(rtol, 1e-8, rel_tol=0, abs_tol=1e-16)
                    and math.isclose(atol, 1e-10, rel_tol=0, abs_tol=1e-18)):
                matching.append(call)
        except (KeyError, TypeError, ValueError):
            pass
    assert matching, "solve_ivp was not called with the extracted inputs, a stiff method, and the required tolerances"

    call = matching[0]
    fun = call["fun"]
    extra_args = call.get("args") or ()
    probe = np.array([0.73, -0.21])
    derivative = np.asarray(fun(0.123, probe, *extra_args), dtype=float)
    required_derivative = np.array([-mu * probe[0] + mu * probe[1], probe[0] - probe[1]])
    assert derivative.shape == (2,) and np.allclose(derivative, required_derivative, rtol=1e-12, atol=1e-12), "The ODE passed to solve_ivp is incorrect"

    assert os.path.isfile(PROFILE), f"Profile output not found: {PROFILE}"
    try:
        stats = pstats.Stats(PROFILE)
    except Exception as exc:
        raise AssertionError(f"Failed to load profile.out as a valid pstats file: {exc}")
    assert stats.total_calls > 0 or len(stats.stats) > 0, "Profile stats are empty."
    assert any(key[2] == "verifier_solve_ivp_probe" for key in stats.stats), "profile.out does not profile the solve_ivp solving step"

    assert os.path.isfile(OUTPUT), f"Output file not found: {OUTPUT}"
    try:
        with open(OUTPUT, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"Failed to parse final_state.json: {exc}")
    assert "y0" in data, "Key 'y0' missing in final_state.json"
    assert "y1" in data, "Key 'y1' missing in final_state.json"
    assert isinstance(data["y0"], (int, float)) and not isinstance(data["y0"], bool)
    assert isinstance(data["y1"], (int, float)) and not isinstance(data["y1"], bool)

    expected_y0, expected_y1 = expected_state(y0, y1, mu, t_end)
    expected_y0 = round(expected_y0, 5)
    expected_y1 = round(expected_y1, 5)
    assert abs(data["y0"] - expected_y0) < 1e-5, f"Expected y0 to be close to {expected_y0}, got {data['y0']}"
    assert abs(data["y1"] - expected_y1) < 1e-5, f"Expected y1 to be close to {expected_y1}, got {data['y1']}"


def timeout_handler(signum, frame):
    raise TimeoutError("optimize.py timed out")

signal.signal(signal.SIGALRM, timeout_handler)
signal.alarm(90)
try:
    changed = original_measurements
    changed = changed.replace("variable: y0, value: 2.0", "variable: y0, value: 1.25")
    changed = changed.replace("variable: mu, value: 1000.0", "variable: mu, value: 37.0")
    changed = changed.replace("variable: y1, value: 0.0", "variable: y1, value: -0.4")
    changed = changed.replace("variable: t_end, value: 3.0", "variable: t_end, value: 0.07")
    assert changed != original_measurements, "Failed to construct extraction test input"
    with open(MEASUREMENTS, "w", encoding="utf-8") as f:
        f.write(changed)
    run_and_check(1.25, -0.4, 37.0, 0.07)
finally:
    with open(MEASUREMENTS, "w", encoding="utf-8") as f:
        f.write(original_measurements)

# Re-run against the required log so the final artifacts correspond to the task input.
run_and_check(2.0, 0.0, 1000.0, 3.0)
with open(OUTPUT, "r", encoding="utf-8") as f:
    final_data = json.load(f)
expected_val = 0.00200
assert abs(final_data["y0"] - expected_val) < 1e-5, f"Expected y0 to be close to {expected_val}, got {final_data['y0']}"
assert abs(final_data["y1"] - expected_val) < 1e-5, f"Expected y1 to be close to {expected_val}, got {final_data['y1']}"
signal.alarm(0)
PY_EOF

if timeout 120s python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
