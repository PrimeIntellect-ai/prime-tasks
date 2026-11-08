#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import subprocess
import textwrap

import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp

SCRIPT = "/home/user/simulate.py"
CSV = "/home/user/simulation.csv"
VENV = "/home/user/venv"
TRACE = "/tmp/simulation_runtime_trace.jsonl"
TRAJECTORIES = "/tmp/simulation_integration_traces"
FRAMES = 300
TARGET_TIME = np.linspace(0, 10, FRAMES, endpoint=False)


def test_required_artifacts_and_venv():
    assert os.path.isfile(SCRIPT), f"Expected simulation script {SCRIPT} does not exist or is not a file."
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be an implemented Python file, not a symlink."
    with open(SCRIPT, "r", encoding="utf-8") as f:
        ast.parse(f.read(), filename=SCRIPT)

    python = os.path.join(VENV, "bin", "python")
    assert os.path.isfile(os.path.join(VENV, "pyvenv.cfg")), f"{VENV} is not a Python virtual environment."
    assert os.path.exists(python) and os.access(python, os.X_OK), "The virtual environment has no executable Python."

    check = textwrap.dedent("""
        import json, os, sys
        import cv2, scipy, numpy, pandas
        modules = [cv2, scipy, numpy, pandas]
        print(json.dumps({
            'prefix': os.path.realpath(sys.prefix),
            'files': [os.path.realpath(m.__file__) for m in modules]
        }))
    """)
    proc = subprocess.run([python, "-c", check], text=True, capture_output=True, timeout=30)
    assert proc.returncode == 0, f"Required packages are not usable in the venv:\n{proc.stderr}"
    info = json.loads(proc.stdout.strip().splitlines()[-1])
    venv_real = os.path.realpath(VENV)
    assert info["prefix"] == venv_real, "venv/bin/python does not run inside /home/user/venv."
    for path in info["files"]:
        assert path.startswith(venv_real + os.sep), f"Package {path} was not installed in the requested virtual environment."


def test_execute_simulation_script():
    os.makedirs(TRAJECTORIES, exist_ok=True)
    for path in glob.glob(os.path.join(TRAJECTORIES, "*.npz")):
        os.remove(path)
    if os.path.exists(TRACE):
        os.remove(TRACE)
    if os.path.lexists(CSV):
        os.remove(CSV)

    hook_dir = "/tmp/verifier_hook"
    os.makedirs(hook_dir, exist_ok=True)
    hook = r'''
import json
import os
import numpy as np

TRACE = "/tmp/simulation_runtime_trace.jsonl"
OUTDIR = "/tmp/simulation_integration_traces"
os.makedirs(OUTDIR, exist_ok=True)
_counter = 0

def emit(event, **kw):
    try:
        with open(TRACE, "a", encoding="utf-8") as f:
            f.write(json.dumps(dict(event=event, **kw)) + "\\n")
    except Exception:
        pass

try:
    import cv2
    _VideoCapture = cv2.VideoCapture
    class LoggedCapture:
        def __init__(self, *args, **kwargs):
            self._cap = _VideoCapture(*args, **kwargs)
            emit("video_open", source=str(args[0]) if args else "")
        def read(self, *args, **kwargs):
            result = self._cap.read(*args, **kwargs)
            if result and result[0]:
                emit("video_read")
            return result
        def __getattr__(self, name):
            return getattr(self._cap, name)
        def __enter__(self):
            return self
        def __exit__(self, *args):
            self._cap.release()
    cv2.VideoCapture = LoggedCapture
except Exception as exc:
    emit("hook_error", component="cv2", detail=str(exc))

try:
    import scipy.optimize as _opt
    for _name in ("least_squares", "minimize", "curve_fit", "differential_evolution", "basinhopping", "dual_annealing"):
        if hasattr(_opt, _name):
            _original = getattr(_opt, _name)
            def _make_wrapper(fn, name):
                def wrapper(*args, **kwargs):
                    emit("optimization", routine=name)
                    return fn(*args, **kwargs)
                return wrapper
            setattr(_opt, _name, _make_wrapper(_original, _name))
except Exception as exc:
    emit("hook_error", component="optimize", detail=str(exc))

try:
    import scipy.integrate as _integ
    _solve_ivp = _integ.solve_ivp
    def solve_ivp_wrapper(*args, **kwargs):
        global _counter
        result = _solve_ivp(*args, **kwargs)
        t_span = kwargs.get("t_span", args[1] if len(args) > 1 else None)
        t_eval = kwargs.get("t_eval", None)
        method = kwargs.get("method", "RK45")
        method_name = method if isinstance(method, str) else getattr(method, "__name__", str(method))
        event = {"method": str(method_name), "t_span": list(map(float, t_span)) if t_span is not None else []}
        emit("adaptive_integration", **event)

        target = np.linspace(0.0, 10.0, 300, endpoint=False)
        values = None
        if t_eval is not None:
            te = np.asarray(t_eval, dtype=float)
            if te.shape == target.shape and np.allclose(te, target, rtol=0, atol=1e-10):
                values = np.asarray(result.y, dtype=float)
        elif getattr(result, "sol", None) is not None and t_span is not None:
            if float(t_span[0]) <= 0.0 and float(t_span[1]) >= target[-1]:
                values = np.asarray(result.sol(target), dtype=float)
        if values is not None and values.ndim == 2 and values.shape[0] >= 2 and values.shape[1] == 300:
            _counter += 1
            np.savez_compressed(os.path.join(OUTDIR, "trajectory_%06d.npz" % _counter), y=values[:2])
            emit("evaluated_integration", method=str(method_name))
        return result
    _integ.solve_ivp = solve_ivp_wrapper
except Exception as exc:
    emit("hook_error", component="integrate", detail=str(exc))
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(hook)

    env = os.environ.copy()
    env["PYTHONPATH"] = hook_dir
    proc = subprocess.run(
        [os.path.join(VENV, "bin", "python"), SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        capture_output=True,
        timeout=180,
    )
    assert proc.returncode == 0, f"simulate.py failed when executed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
    assert os.path.isfile(CSV), "Executing simulate.py did not generate /home/user/simulation.csv."

    events = []
    if os.path.exists(TRACE):
        with open(TRACE, encoding="utf-8") as f:
            for line in f:
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    pass

    opens = [e for e in events if e.get("event") == "video_open"]
    assert any(os.path.realpath(e.get("source", "")) == "/app/pendulum.mp4" for e in opens), "simulate.py did not open the supplied pendulum video."
    reads = sum(e.get("event") == "video_read" for e in events)
    assert reads >= FRAMES, f"simulate.py read only {reads} successful video frames; expected all {FRAMES}."
    assert any(e.get("event") == "optimization" for e in events), "No nonlinear parameter optimization was performed."

    adaptive = [e for e in events if e.get("event") == "adaptive_integration"]
    allowed = {"RK23", "RK45", "DOP853", "Radau", "BDF", "LSODA"}
    assert any(e.get("method") in allowed and len(e.get("t_span", [])) == 2 and e["t_span"][0] <= 0 and e["t_span"][1] >= 10 for e in adaptive), \
        "No adaptive ODE integration covering t=0 through t=10 was performed."
    assert glob.glob(os.path.join(TRAJECTORIES, "*.npz")), "The adaptive solver was not evaluated at the required 30 FPS times."


def test_simulation_csv_exists_and_format():
    csv_path = CSV
    assert os.path.exists(csv_path), f"Expected output file {csv_path} does not exist."
    assert os.path.isfile(csv_path), f"{csv_path} is not a file."

    df = pd.read_csv(csv_path)
    expected_columns = {'time', 'theta', 'theta_dot'}
    assert expected_columns.issubset(df.columns), f"CSV must contain columns {expected_columns}, found {list(df.columns)}"

    frames = 300
    assert len(df) >= frames, f"CSV must contain at least {frames} rows, found {len(df)}."
    assert list(df.columns) == ['time', 'theta', 'theta_dot'], f"CSV must contain exactly the columns time, theta, theta_dot; found {list(df.columns)}"
    assert len(df) == frames, f"CSV must contain exactly {frames} rows, found {len(df)}."

    values = df[['time', 'theta', 'theta_dot']].to_numpy(dtype=float)
    assert np.isfinite(values).all(), "CSV contains missing, infinite, or non-numeric values."
    assert np.allclose(values[:, 0], TARGET_TIME, rtol=0, atol=1e-10), "time values are not precisely the required 30 FPS intervals."

    matched_solver_output = False
    for path in glob.glob(os.path.join(TRAJECTORIES, "*.npz")):
        y = np.load(path)["y"]
        if y.shape == (2, FRAMES) and np.allclose(values[:, 1], y[0], rtol=0, atol=2e-4) and np.allclose(values[:, 2], y[1], rtol=0, atol=2e-4):
            matched_solver_output = True
            break
    assert matched_solver_output, "CSV theta/theta_dot values do not match a trajectory produced by the adaptive solver."


def test_simulation_accuracy():
    csv_path = CSV
    assert os.path.exists(csv_path), "Simulation CSV missing, cannot check accuracy."

    g = 9.81
    L = 2.5
    b = 0.15
    duration = 10
    fps = 30
    frames = fps * duration
    t_eval = np.linspace(0, duration, frames, endpoint=False)

    def pendulum_ode(t, y):
        return [y[1], -(g/L)*np.sin(y[0]) - b*y[1]]

    sol = solve_ivp(pendulum_ode, [0, duration], [1.0, 0.0], t_eval=t_eval,
                    method='RK45', rtol=1e-8, atol=1e-8)
    true_theta = sol.y[0]
    true_omega = sol.y[1]

    df = pd.read_csv(csv_path)
    assert 'theta' in df.columns, "Column 'theta' missing from CSV."
    agent_theta = df['theta'].values[:frames]
    assert len(agent_theta) == frames, f"Expected at least {frames} valid theta values."

    mse = np.mean((true_theta - agent_theta)**2)
    threshold = 0.005
    assert mse <= threshold, f"MSE of theta is {mse:.6f}, which exceeds the threshold of {threshold}."

    omega_mse = np.mean((true_omega - df['theta_dot'].to_numpy(dtype=float))**2)
    assert omega_mse <= 0.005, f"MSE of theta_dot is {omega_mse:.6f}, which exceeds the threshold of 0.005."
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
