#!/bin/bash
set -e
mkdir -p /logs/verifier

rm -f /home/user/bratu_convergence.log /tmp/bratu_root_trace.jsonl
mkdir -p /tmp/bratu_instrument

cat << 'PY_EOF' > /tmp/bratu_instrument/sitecustomize.py
import json
import numpy as np
import scipy.optimize

_original_root = scipy.optimize.root
_trace_path = "/tmp/bratu_root_trace.jsonl"

def checked_root(fun, x0, *positional, **kwargs):
    x0_array = np.asarray(x0, dtype=float)
    assert x0_array.ndim == 1 and x0_array.size > 0, "root must receive a one-dimensional nonempty initial guess"
    assert np.array_equal(x0_array, np.zeros(x0_array.size)), "each root solve must use an all-zero initial guess"

    assert len(positional) <= 2, "unexpected positional arguments to scipy.optimize.root"
    method = kwargs.get("method", positional[1] if len(positional) > 1 else None)
    assert method is None, "scipy.optimize.root must use its default solver"
    root_args = kwargs.get("args", positional[0] if positional else ())
    if root_args is None:
        root_args = ()
    if not isinstance(root_args, tuple):
        root_args = (root_args,)

    n = x0_array.size
    h = 1.0 / (n + 1)
    probes = [np.zeros(n), np.linspace(-0.1, 0.2, n)]
    for probe in probes:
        actual = np.asarray(fun(probe.copy(), *root_args), dtype=float)
        padded = np.concatenate(([0.0], probe, [0.0]))
        expected = (padded[:-2] - 2.0 * padded[1:-1] + padded[2:]) / (h * h) + np.exp(probe)
        assert actual.shape == (n,), "finite-difference residual has the wrong shape"
        assert np.allclose(actual, expected, rtol=1e-10, atol=1e-10), "root was not given the required Bratu finite-difference equations"

    result = _original_root(fun, x0, *positional, **kwargs)
    with open(_trace_path, "a") as trace:
        trace.write(json.dumps({"N": n}) + "\n")
    return result

scipy.optimize.root = checked_root
PY_EOF

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import numpy as np
from scipy.optimize import root

SCRIPT = "/home/user/solve_bratu.py"
LOG = "/home/user/bratu_convergence.log"
TRACE = "/tmp/bratu_root_trace.jsonl"


def independently_compute_expected():
    sequence = []
    previous = None
    n = 3
    while True:
        h = 1.0 / (n + 1)

        def residual(u):
            padded = np.concatenate(([0.0], u, [0.0]))
            return ((padded[:-2] - 2.0 * padded[1:-1] + padded[2:]) / (h * h)
                    + np.exp(u))

        solution = root(residual, np.zeros(n))
        assert solution.success, "independent reference solve failed"
        midpoint = float(solution.x[n // 2])
        sequence.append(n)
        if previous is not None and abs(midpoint - previous) <= 1e-5:
            return sequence, n, midpoint
        previous = midpoint
        n = 2 * n + 1


def test_script_exists():
    assert os.path.isfile(SCRIPT), "The script /home/user/solve_bratu.py does not exist."


def test_run_script_and_check_log():
    # Always execute the submitted artifact; a stale or prewritten log is not accepted.
    for path in (LOG, TRACE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/bratu_instrument" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    result = subprocess.run(
        ["python3", SCRIPT], capture_output=True, text=True, env=env, timeout=120
    )
    assert result.returncode == 0, f"Script failed to run: {result.stderr}"
    assert os.path.isfile(LOG), f"The log file {LOG} was not created."

    with open(LOG, "r") as f:
        content = f.read().strip()

    # Preserve the original exact output assertion.
    expected_content = "N=127, u_mid=0.113954"
    assert content == expected_content, f"Log file content is incorrect. Expected '{expected_content}', but got '{content}'"

    expected_sequence, expected_n, expected_midpoint = independently_compute_expected()
    assert expected_content == f"N={expected_n}, u_mid={expected_midpoint:.6f}"

    assert os.path.isfile(TRACE), "The script did not call scipy.optimize.root"
    with open(TRACE, "r") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    actual_sequence = [entry["N"] for entry in calls]
    assert actual_sequence == expected_sequence, (
        f"Expected one root solve on each refined mesh {expected_sequence}, got {actual_sequence}"
    )
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
