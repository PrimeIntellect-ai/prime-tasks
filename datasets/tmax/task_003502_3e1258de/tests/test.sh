#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import inspect
import json
import math
import os
import runpy

venv_python = "/home/user/scienv/bin/python"
script_path = "/home/user/stiff_model.py"
results_path = "/home/user/results.json"

# Preserve the original existence and source checks.
assert os.path.isfile(venv_python), f"Virtual environment Python executable not found at {venv_python}."
assert os.path.isfile(script_path), f"The script {script_path} does not exist."
with open(script_path, "r") as f:
    content = f.read()
assert "BDF" in content, "The script does not use the 'BDF' method."
assert "1e-6" in content, "The script does not set rtol=1e-6."
assert "1e-10" in content, "The script does not set atol=1e-10."

import numpy as np
import scipy.integrate

real_solve_ivp = scipy.integrate.solve_ivp
signature = inspect.signature(real_solve_ivp)
valid_solutions = []

def expected_rhs(t, y):
    y1, y2, y3 = y
    return np.array([
        -0.04 * y1 + 1e4 * y2 * y3,
        0.04 * y1 - 1e4 * y2 * y3 - 3e7 * y2**2,
        3e7 * y2**2,
    ], dtype=float)

def checked_solve_ivp(*args, **kwargs):
    bound = signature.bind(*args, **kwargs)
    bound.apply_defaults()

    assert bound.arguments["method"] == "BDF", "solve_ivp was not called with method='BDF'."
    assert math.isclose(float(bound.arguments["rtol"]), 1e-6, rel_tol=0, abs_tol=0), "solve_ivp rtol is not 1e-6."
    assert math.isclose(float(bound.arguments["atol"]), 1e-10, rel_tol=0, abs_tol=0), "solve_ivp atol is not 1e-10."
    assert np.allclose(np.asarray(bound.arguments["t_span"], dtype=float), [0.0, 1e5], rtol=0, atol=0), "The time span was changed."
    assert np.allclose(np.asarray(bound.arguments["y0"], dtype=float), [1.0, 0.0, 0.0], rtol=0, atol=0), "The initial conditions were changed."

    fun = bound.arguments["fun"]
    for t, y in [
        (0.0, np.array([1.0, 0.0, 0.0])),
        (12.5, np.array([0.4, 2.0e-5, 0.59998])),
        (900.0, np.array([0.1, 1.0e-6, 0.899999])),
    ]:
        actual = np.asarray(fun(t, y.copy()), dtype=float)
        expected = expected_rhs(t, y)
        assert actual.shape == (3,) and np.allclose(actual, expected, rtol=1e-12, atol=1e-12), "The Robertson system equations were changed."

    solution = real_solve_ivp(*args, **kwargs)
    valid_solutions.append(solution)
    return solution

# Force this verification run to produce the submitted result rather than trusting
# a pre-created JSON file, and instrument the actual solve_ivp call.
if os.path.exists(results_path):
    os.remove(results_path)
scipy.integrate.solve_ivp = checked_solve_ivp
try:
    runpy.run_path(script_path, run_name="__main__")
finally:
    scipy.integrate.solve_ivp = real_solve_ivp

assert valid_solutions, "The script did not call scipy.integrate.solve_ivp."
assert os.path.isfile(results_path), f"The results file {results_path} does not exist."
with open(results_path, "r") as f:
    data = json.load(f)

assert set(data.keys()) == {"y1_final", "y2_final", "y3_final"}, "results.json must contain exactly y1_final, y2_final, and y3_final."
values = np.array([data["y1_final"], data["y2_final"], data["y3_final"]], dtype=float)
assert np.all(np.isfinite(values)), "Final-state values must be finite numbers."

# Ensure the JSON came from the validated integration call.
assert any(sol.success and np.allclose(values, sol.y[:, -1], rtol=1e-12, atol=1e-14) for sol in valid_solutions), "results.json does not contain the final state produced by the validated solve_ivp call."

# Independently derive the expected state for t=10^5 instead of trusting hardcoded
# values (the old verifier's constants corresponded to approximately t=10^6).
reference = real_solve_ivp(expected_rhs, (0.0, 1e5), [1.0, 0.0, 0.0], method="BDF", rtol=1e-6, atol=1e-10)
assert reference.success, "Verifier reference integration failed."
expected = reference.y[:, -1]
assert math.isclose(values[0], expected[0], rel_tol=1e-3), f"y1_final incorrect: {values[0]}"
assert math.isclose(values[1], expected[1], rel_tol=1e-3), f"y2_final incorrect: {values[1]}"
assert math.isclose(values[2], expected[2], rel_tol=1e-3), f"y3_final incorrect: {values[2]}"
PY_EOF

if timeout 120 /home/user/scienv/bin/python /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
