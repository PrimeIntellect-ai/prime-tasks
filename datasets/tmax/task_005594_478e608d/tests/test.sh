#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_mc_integrator.py
import ast
import os
import re
import subprocess
import sys
import tempfile

import h5py
import numpy as np
from scipy.integrate import solve_ivp

SCRIPT = "/home/user/mc_integrator.py"
INPUT = "/home/user/input_states.h5"
OUTPUT = "/home/user/output_states.h5"
AVG = "/home/user/avg_x.txt"


def fail(message):
    raise AssertionError(message)


# Verify that the requested artifact exists and invokes a standard adaptive solver.
if not os.path.isfile(SCRIPT):
    fail(f"Missing required Python script: {SCRIPT}")

try:
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)
except Exception as e:
    fail(f"Could not read or parse {SCRIPT}: {e}")

adaptive_names = {
    "solve_ivp", "odeint", "ode", "RK23", "RK45", "DOP853",
    "Radau", "BDF", "LSODA"
}
aliases = {}
for node in ast.walk(tree):
    if isinstance(node, ast.ImportFrom) and node.module and node.module.startswith("scipy.integrate"):
        for item in node.names:
            aliases[item.asname or item.name] = item.name

adaptive_call_found = False
for node in ast.walk(tree):
    if not isinstance(node, ast.Call):
        continue
    if isinstance(node.func, ast.Name):
        called = aliases.get(node.func.id, node.func.id)
    elif isinstance(node.func, ast.Attribute):
        called = node.func.attr
    else:
        continue
    if called in adaptive_names:
        adaptive_call_found = True
        break

if not adaptive_call_found:
    fail("mc_integrator.py does not call a recognized adaptive ODE solver")

# Use the same 1000 supplied states but a verifier-only ordering, so stale or
# hard-coded output cannot pass. This does not alter the numerical difficulty.
try:
    with h5py.File(INPUT, "r") as f:
        original_states = f["states"][:]
except Exception as e:
    fail(f"Failed to read input_states.h5: {e}")

if original_states.shape != (1000, 2):
    fail(f"Input dataset has unexpected shape {original_states.shape}")

rng = np.random.default_rng(int.from_bytes(os.urandom(16), "little"))
states = original_states[rng.permutation(len(original_states))]
with h5py.File(INPUT, "w") as f:
    f.create_dataset("states", data=states, dtype="float64")

for path in (OUTPUT, AVG):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

# Install a verification-only startup hook which records entry into an actual
# SciPy adaptive integrator. It disables itself immediately after the first hit.
hook_dir = tempfile.mkdtemp(prefix="adaptive_hook_")
marker = os.path.join(hook_dir, "used")
with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
    f.write(r'''
import os
import sys

_marker = os.environ.get("MC_ADAPTIVE_MARKER")
_names = {"solve_ivp", "odeint", "ode", "RK23", "RK45", "DOP853", "Radau", "BDF", "LSODA"}

def _profile(frame, event, arg):
    if event != "call":
        return
    filename = frame.f_code.co_filename.replace("\\", "/")
    name = frame.f_code.co_name
    self_obj = frame.f_locals.get("self")
    class_name = type(self_obj).__name__ if self_obj is not None else ""
    if "/scipy/integrate/" in filename and (name in _names or class_name in _names):
        try:
            with open(_marker, "w") as out:
                out.write("used\n")
        finally:
            sys.setprofile(None)

sys.setprofile(_profile)
''')

env = os.environ.copy()
env["MC_ADAPTIVE_MARKER"] = marker
env["PYTHONPATH"] = hook_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
result = subprocess.run(
    [sys.executable, SCRIPT],
    env=env,
    capture_output=True,
    text=True,
    timeout=300,
)
if result.returncode != 0:
    fail(
        "mc_integrator.py failed when executed:\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
if not os.path.isfile(marker):
    fail("Execution did not enter a recognized SciPy adaptive ODE solver")

# Preserve the original output existence assertions, now after a fresh execution.
if not os.path.isfile(OUTPUT):
    fail(f"Missing required output file: {OUTPUT}")
if not os.path.isfile(AVG):
    fail(f"Missing required output file: {AVG}")


def rhs(t, state):
    x, v = state
    return (v, -(x ** 3))

# Use a high-accuracy solution as the reference. Calibrate the acceptance envelope
# against SciPy's documented default RK45 accuracy so both the suggested default
# solver and valid higher-accuracy adaptive solutions are accepted.
reference = np.empty((1000, 2), dtype=np.float64)
default_rk45 = np.empty((1000, 2), dtype=np.float64)
for i, initial in enumerate(states):
    accurate = solve_ivp(
        rhs, (0.0, 5.0), initial, method="DOP853",
        rtol=1e-11, atol=1e-13
    )
    baseline = solve_ivp(rhs, (0.0, 5.0), initial, method="RK45")
    if not accurate.success or not baseline.success:
        fail("Verifier reference integration failed")
    reference[i] = accurate.y[:, -1]
    default_rk45[i] = baseline.y[:, -1]

try:
    with h5py.File(OUTPUT, "r") as f:
        if "final_states" not in f:
            fail("Dataset '/final_states' not found in output_states.h5")
        dataset = f["final_states"]
        out_states = dataset[:]
        out_dtype = dataset.dtype
except Exception as e:
    fail(f"Failed to read output_states.h5: {e}")

if out_states.shape != (1000, 2):
    fail(f"Expected shape (1000, 2), got {out_states.shape}")
if out_dtype != np.dtype("float64"):
    fail(f"Expected dtype float64, got {out_dtype}")
if not np.all(np.isfinite(out_states)):
    fail("The output contains NaN or infinite values")

baseline_error = np.abs(default_rk45 - reference)
allowed_atol = np.maximum(2e-3, 1.25 * baseline_error + 5e-4)
if not np.all(np.isclose(out_states, reference, rtol=1e-5, atol=allowed_atol)):
    fail("The integrated final states do not match an accurate adaptive solution")

try:
    with open(AVG, "r", encoding="utf-8") as f:
        avg_content = f.read().strip()
except Exception as e:
    fail(f"Failed to read avg_x.txt: {e}")

if re.fullmatch(r"[-+]?\d+\.\d{4}", avg_content) is None:
    fail("avg_x.txt must contain a number rounded to exactly 4 decimal places")
expected_avg = f"{np.mean(out_states[:, 0]):.4f}"
if avg_content != expected_avg:
    fail(f"Average x mismatch: expected '{expected_avg}', got '{avg_content}'")

print("SUCCESS")
PY_EOF

if python3 /tmp/verify_mc_integrator.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
