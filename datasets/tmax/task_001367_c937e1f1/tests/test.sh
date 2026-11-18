#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import h5py
import numpy as np

SOLVE_SCRIPT = "/home/user/solve.py"
OUTPUT_TXT = "/home/user/optimized_mu.txt"
TARGET_H5 = "/home/user/vdp_target.h5"


def test_solve_script_exists():
    """Test that the solve.py script exists."""
    assert os.path.isfile(SOLVE_SCRIPT), f"The script {SOLVE_SCRIPT} is missing. Did you create it?"


def test_optimized_mu_file_exists():
    """Test that the optimized_mu.txt file exists."""
    assert os.path.isfile(OUTPUT_TXT), f"The output file {OUTPUT_TXT} is missing. Did you run your script and save the output?"


def test_optimized_mu_value():
    """Test that the optimized mu value is correct."""
    with open(OUTPUT_TXT, "r") as f:
        val = f.read().strip()

    expected_val = "500.00"
    assert val == expected_val, f"Incorrect mu value: '{val}'. Expected '{expected_val}'."


def test_script_executes_required_pipeline_on_unseen_data():
    """Execute solve.py and verify its HDF5, ODE, stiff-solver, MSE, and minimize pipeline."""
    work = tempfile.mkdtemp(prefix="vdp_verify_")
    target_backup = os.path.join(work, "vdp_target.h5")
    output_backup = os.path.join(work, "optimized_mu.txt")
    marker = os.path.join(work, "marker.json")
    hook_dir = os.path.join(work, "hook")
    os.mkdir(hook_dir)

    shutil.copy2(TARGET_H5, target_backup)
    had_output = os.path.isfile(OUTPUT_TXT)
    if had_output:
        shutil.copy2(OUTPUT_TXT, output_backup)

    # Pick an answer unavailable to the submitted script before verification.
    hidden_mu = (35000 + secrets.randbelow(30001)) / 100.0
    if abs(hidden_mu - 500.0) < 1.0:
        hidden_mu += 7.13

    with h5py.File(target_backup, "r") as f:
        hidden_t = np.asarray(f["t"][:], dtype=float)

    def model(mu, t):
        return (2.0 + 1.0e-3 * mu * np.sin(0.31 * t)
                + 2.0e-6 * mu * mu * np.cos(0.17 * t))

    hidden_y = model(hidden_mu, hidden_t)
    with h5py.File(TARGET_H5, "w") as f:
        f.create_dataset("t", data=hidden_t)
        f.create_dataset("y", data=hidden_y)

    hook = r'''
import json
import os
from types import SimpleNamespace

import h5py
import numpy as np
import scipy.integrate
import scipy.optimize

_HIDDEN_MU = float(os.environ["VDP_TEST_MU"])
_MARKER = os.environ["VDP_TEST_MARKER"]
_TARGET = "/home/user/vdp_target.h5"


def _model(mu, t):
    t = np.asarray(t, dtype=float)
    return (2.0 + 1.0e-3 * mu * np.sin(0.31 * t)
            + 2.0e-6 * mu * mu * np.cos(0.17 * t))


def _scalar(value, name):
    arr = np.asarray(value, dtype=float).reshape(-1)
    assert arr.size == 1, "%s must contain one mu value" % name
    return float(arr[0])


def checked_solve_ivp(fun, t_span, y0, *pos, **kw):
    method = kw.get("method")
    assert method in ("Radau", "BDF"), "solve_ivp must use Radau or BDF"
    assert np.allclose(np.asarray(y0, dtype=float), [2.0, 0.0]), "wrong initial conditions"

    t_eval = kw.get("t_eval")
    assert t_eval is not None, "solve_ivp must receive the target times as t_eval"
    t_eval = np.asarray(t_eval, dtype=float)
    with h5py.File(_TARGET, "r") as f:
        expected_t = np.asarray(f["t"][:], dtype=float)
    assert np.array_equal(t_eval, expected_t), "simulation is not evaluated at the exact target times"
    assert np.allclose(np.asarray(t_span, dtype=float), [expected_t[0], expected_t[-1]]), "wrong integration interval"

    ode_args = kw.get("args", ())
    if ode_args:
        mu = _scalar(ode_args[0], "ODE mu")
        def call(state):
            return np.asarray(fun(0.0, state, *ode_args), dtype=float).reshape(-1)
    else:
        # For a closure-based RHS, infer mu from dy1 at y0=0,y1=1.
        def call(state):
            return np.asarray(fun(0.0, state), dtype=float).reshape(-1)
        probe = call(np.array([0.0, 1.0]))
        assert probe.size == 2
        mu = float(probe[1])

    probe = call(np.array([1.2, -0.7]))
    expected = np.array([-0.7, mu * (1.0 - 1.2**2) * -0.7 - 1.2])
    assert probe.size == 2 and np.allclose(probe, expected, rtol=1e-9, atol=1e-9), "incorrect Van der Pol ODE"

    y_position = _model(mu, t_eval)
    return SimpleNamespace(t=t_eval, y=np.vstack([y_position, np.zeros_like(y_position)]),
                           success=True, status=0, message="instrumented success")


def checked_minimize(fun, x0, *pos, **kw):
    initial = _scalar(x0, "minimize initial guess")
    assert abs(initial - 250.0) < 1e-12, "minimize must start from mu=250.0"

    with h5py.File(_TARGET, "r") as f:
        t = np.asarray(f["t"][:], dtype=float)
        target = np.asarray(f["y"][:], dtype=float)

    # Exercise the submitted objective at values not known when solve.py was written.
    for probe in (211.37, 377.91, _HIDDEN_MU + 19.43):
        got = _scalar(fun(np.array([probe], dtype=float)), "objective result")
        expected = float(np.mean((_model(probe, t) - target) ** 2))
        assert np.isfinite(got), "objective returned a non-finite value"
        assert np.isclose(got, expected, rtol=1e-7, atol=1e-12), "objective is not the required MSE"

    with open(_MARKER, "w") as f:
        json.dump({"minimize_called": True, "initial": initial}, f)
    return SimpleNamespace(x=np.array([_HIDDEN_MU]), fun=0.0, success=True,
                           status=0, message="instrumented optimum", nit=4, nfev=4)


scipy.integrate.solve_ivp = checked_solve_ivp
scipy.optimize.minimize = checked_minimize
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write(hook)

    try:
        if os.path.exists(OUTPUT_TXT):
            os.remove(OUTPUT_TXT)
        env = os.environ.copy()
        env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
        env["VDP_TEST_MU"] = repr(hidden_mu)
        env["VDP_TEST_MARKER"] = marker
        result = subprocess.run(
            ["python3", SOLVE_SCRIPT], env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
        )
        assert result.returncode == 0, (
            "solve.py failed when executed:\nSTDOUT:\n%s\nSTDERR:\n%s"
            % (result.stdout, result.stderr)
        )
        assert os.path.isfile(marker), "solve.py did not call scipy.optimize.minimize"
        with open(marker, "r") as f:
            record = json.load(f)
        assert record.get("minimize_called") is True

        assert os.path.isfile(OUTPUT_TXT), "executing solve.py did not create optimized_mu.txt"
        with open(OUTPUT_TXT, "r") as f:
            value = f.read().strip()
        expected = f"{hidden_mu:.2f}"
        assert value == expected, (
            "solve.py did not save minimize's optimized mu rounded to exactly two decimals; "
            "got %r, expected %r" % (value, expected)
        )
    finally:
        shutil.copy2(target_backup, TARGET_H5)
        if had_output:
            shutil.copy2(output_backup, OUTPUT_TXT)
        elif os.path.exists(OUTPUT_TXT):
            os.remove(OUTPUT_TXT)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
