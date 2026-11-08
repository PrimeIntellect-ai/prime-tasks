#!/bin/bash
set +e
mkdir -p /logs/verifier
rm -f /home/user/fit_result.txt /tmp/curvefit_trace_*.npz /tmp/mpi_rank_*.started

cat > /tmp/sitecustomize.py <<'PY'
import os

rank = os.environ.get("OMPI_COMM_WORLD_RANK")
if rank is not None:
    try:
        with open(f"/tmp/mpi_rank_{rank}.started", "w") as f:
            f.write("started\n")
    except Exception:
        pass

try:
    import numpy as np
    import scipy.optimize as _opt

    _real_curve_fit = _opt.curve_fit

    def _recording_curve_fit(model, xdata, ydata, *args, **kwargs):
        result = _real_curve_fit(model, xdata, ydata, *args, **kwargs)
        current_rank = os.environ.get("OMPI_COMM_WORLD_RANK", "unknown")
        target = f"/tmp/curvefit_trace_{current_rank}.npz"
        temporary = target + ".tmp.npz"
        probe_t = np.array([0.0, 1.0, 100.0])
        probe_y = np.asarray(model(probe_t, 0.02), dtype=float)
        np.savez(
            temporary,
            x=np.asarray(xdata, dtype=float),
            y=np.asarray(ydata, dtype=float),
            popt=np.asarray(result[0], dtype=float),
            probe=probe_y,
        )
        os.replace(temporary, target)
        return result

    _opt.curve_fit = _recording_curve_fit
except Exception:
    pass
PY

cat > /tmp/check_submission.py <<'PY'
import ast
import math
import os
import re
import subprocess
import sys

import numpy as np

venv_python = "/home/user/venv/bin/python"
script_path = "/home/user/mc_evo.py"
result_path = "/home/user/fit_result.txt"

# Preserve the original existence assertions and require executable artifacts.
assert os.path.exists(venv_python), f"Virtual environment python not found at {venv_python}"
assert os.path.isfile(venv_python) and os.access(venv_python, os.X_OK), "venv python is not an executable file"
assert os.path.exists(script_path), f"Script not found at {script_path}"
assert os.path.isfile(script_path) and os.path.getsize(script_path) > 0, "mc_evo.py is not a nonempty regular file"

# Confirm the requested dependencies are installed in the submitted venv.
subprocess.run(
    [venv_python, "-c", "import mpi4py, numpy, scipy; from scipy.optimize import curve_fit"],
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    timeout=60,
)

# Check that the submitted program actually contains the required MPI, RNG,
# gather, and curve_fit machinery rather than only writing a claimed answer.
with open(script_path, "r", encoding="utf-8") as f:
    source = f.read()
tree = ast.parse(source, filename=script_path)
imports = set()
attrs = set()
names_called = set()
has_floor_division = False
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        imports.update(alias.name for alias in node.names)
    elif isinstance(node, ast.ImportFrom):
        imports.add(node.module or "")
        imports.update(alias.name for alias in node.names)
    elif isinstance(node, ast.Attribute):
        attrs.add(node.attr)
    elif isinstance(node, ast.Call):
        if isinstance(node.func, ast.Name):
            names_called.add(node.func.id)
        elif isinstance(node.func, ast.Attribute):
            names_called.add(node.func.attr)
    elif isinstance(node, ast.FloorDiv):
        has_floor_division = True

assert any(x == "mpi4py" or x.startswith("mpi4py.") for x in imports), "script does not import mpi4py"
assert any(x == "numpy" or x.startswith("numpy.") for x in imports), "script does not import numpy"
assert "curve_fit" in imports or "curve_fit" in names_called, "script does not use scipy.optimize.curve_fit"
assert "gather" in names_called, "script does not gather trajectory data with MPI"
assert "random" in attrs or any(n in names_called for n in ("random", "rand", "choice", "binomial", "integers", "randint")), "script has no Monte Carlo random sampling"
assert has_floor_division, "script does not divide trajectory work across MPI ranks with //"

# All four MPI processes must really have started, and fitting must occur only on rank 0.
for rank in range(4):
    assert os.path.isfile(f"/tmp/mpi_rank_{rank}.started"), f"MPI rank {rank} was not started"
assert os.path.isfile("/tmp/curvefit_trace_0.npz"), "rank 0 did not call curve_fit"
for rank in range(1, 4):
    assert not os.path.exists(f"/tmp/curvefit_trace_{rank}.npz"), f"curve_fit was incorrectly called on rank {rank}"

trace = np.load("/tmp/curvefit_trace_0.npz")
x = np.asarray(trace["x"], dtype=float).reshape(-1)
y = np.asarray(trace["y"], dtype=float).reshape(-1)
popt = np.asarray(trace["popt"], dtype=float).reshape(-1)
probe = np.asarray(trace["probe"], dtype=float).reshape(-1)

assert x.shape == (101,) and np.array_equal(x, np.arange(101, dtype=float)), "curve_fit did not receive t=0..100"
assert y.shape == (101,) and np.all(np.isfinite(y)), "curve_fit did not receive 101 finite averaged distances"
assert abs(y[0]) < 1e-12, "initial Hamming distance is not zero"
assert np.all((y >= 0) & (y <= 500)), "invalid Hamming distances"
# An average over exactly 4000 integer-valued trajectory distances has this granularity.
scaled = y * 4000.0
assert np.max(np.abs(scaled - np.rint(scaled))) < 1e-4, "fit data are not averages of exactly 4000 integer distances"

# Independently derive the expectation for the specified recurrent mutation chain.
# Its nontrivial one-step eigenvalue is 1 - 4p/3.
p = 0.01
lam = 1.0 - 4.0 * p / 3.0
expected = 375.0 * (1.0 - lam ** x)
q = expected / 500.0
standard_error = np.sqrt(500.0 * q * (1.0 - q) / 4000.0)
tolerance = 7.0 * standard_error + 0.05
assert np.all(np.abs(y - expected) <= tolerance), "gathered Monte Carlo trajectory averages do not match the specified mutation process"

expected_probe = 375.0 * (1.0 - np.exp(-0.02 * np.array([0.0, 1.0, 100.0])))
assert np.allclose(probe, expected_probe, rtol=1e-10, atol=1e-10), "curve_fit was given the wrong Jukes-Cantor model"
assert popt.size >= 1 and np.isfinite(popt[0]), "curve_fit returned no finite fitted k"

# Preserve the original result assertions, while tying the file to the observed fit.
assert os.path.exists(result_path), f"Result file not found at {result_path}"
with open(result_path, "r", encoding="utf-8") as f:
    content = f.read().strip()
assert re.fullmatch(r"[+-]?(?:\d+)\.\d{4}", content), "fit_result.txt is not formatted to exactly four decimal places"
try:
    k = float(content)
except ValueError:
    raise AssertionError(f"Could not parse '{content}' as a float in {result_path}")
assert 0.0130 <= k <= 0.0136, f"Fitted k={k} is outside the expected range [0.0130, 0.0136]"
assert content == f"{popt[0]:.4f}", "fit_result.txt does not contain the value returned by curve_fit"
PY

PYTHONPATH=/tmp timeout 900s mpiexec --allow-run-as-root --oversubscribe -n 4 /home/user/venv/bin/python /home/user/mc_evo.py >/tmp/mc_evo.stdout 2>/tmp/mc_evo.stderr
run_status=$?

if [ "$run_status" -eq 0 ]; then
    /home/user/venv/bin/python /tmp/check_submission.py >/tmp/verifier_check.stdout 2>/tmp/verifier_check.stderr
    check_status=$?
else
    check_status=1
fi

if [ "$run_status" -eq 0 ] && [ "$check_status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
    cat /tmp/mc_evo.stderr /tmp/verifier_check.stderr 2>/dev/null || true
fi
