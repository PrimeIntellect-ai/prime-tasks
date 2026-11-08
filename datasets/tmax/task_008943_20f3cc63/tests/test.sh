#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hook
cat <<'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os

TRACE = os.environ.get("ANALYSIS_TRACE")

def record(event, **fields):
    if not TRACE:
        return
    payload = {"event": event, "pid": os.getpid(), **fields}
    try:
        fd = os.open(TRACE, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
        try:
            os.write(fd, (json.dumps(payload) + "\n").encode())
        finally:
            os.close(fd)
    except Exception:
        pass

try:
    import scipy.integrate
    _original_odeint = scipy.integrate.odeint

    def traced_odeint(func, y0, t, *args, **kwargs):
        record("odeint", y0=list(y0), times=list(t))
        return _original_odeint(func, y0, t, *args, **kwargs)

    scipy.integrate.odeint = traced_odeint
except Exception:
    pass

try:
    import multiprocessing.pool
    _Pool = multiprocessing.pool.Pool
    _original_init = _Pool.__init__

    def traced_init(self, *args, **kwargs):
        record("pool_init", processes=kwargs.get("processes", args[0] if args else None))
        return _original_init(self, *args, **kwargs)

    _Pool.__init__ = traced_init

    for _name in ("map", "starmap", "imap", "imap_unordered", "apply", "apply_async", "map_async", "starmap_async"):
        if hasattr(_Pool, _name):
            _original = getattr(_Pool, _name)
            def make_wrapper(name, original):
                def wrapper(self, *args, **kwargs):
                    record("pool_submit", method=name)
                    return original(self, *args, **kwargs)
                return wrapper
            setattr(_Pool, _name, make_wrapper(_name, _original))
except Exception:
    pass
HOOK_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import stat
import subprocess

import numpy as np
import pytest
from scipy.integrate import odeint

HOME = "/home/user"
TRACE = "/tmp/analysis_trace.jsonl"
ORIGINAL_OBS = "day,1,2,3,4,5\ninfected,10,25,50,80,110\n"
COMBINATIONS = [(0.5, 0.1), (0.6, 0.1), (0.5, 0.2), (0.6, 0.2)]


def expected_result(infected):
    times = np.array([1, 2, 3, 4, 5], dtype=float)

    def sir(state, _t, beta, gamma):
        s, i, r = state
        return (-beta * s * i / 1000.0,
                beta * s * i / 1000.0 - gamma * i,
                gamma * i)

    scored = []
    for beta, gamma in COMBINATIONS:
        simulated = odeint(sir, [990, 10, 0], times, args=(beta, gamma))[:, 1]
        sse = float(np.sum((simulated - np.asarray(infected, dtype=float)) ** 2))
        scored.append((sse, beta, gamma))
    sse, beta, gamma = min(scored)
    return {"beta": beta, "gamma": gamma, "sse": round(sse, 2)}


def read_trace():
    if not os.path.exists(TRACE):
        return []
    events = []
    with open(TRACE) as f:
        for line in f:
            if line.strip():
                events.append(json.loads(line))
    return events


def run_command(command):
    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/verifier_hook" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["ANALYSIS_TRACE"] = TRACE
    return subprocess.run(command, cwd=HOME, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=120)


@pytest.fixture(scope="session", autouse=True)
def execute_workflow():
    with open(os.path.join(HOME, "obs_data.txt"), "w") as f:
        f.write(ORIGINAL_OBS)
    for name in ("obs_reshaped.csv", "best_params.json", "profile.log"):
        try:
            os.remove(os.path.join(HOME, name))
        except FileNotFoundError:
            pass
    try:
        os.remove(TRACE)
    except FileNotFoundError:
        pass

    result = run_command([os.path.join(HOME, "run_analysis.sh")])
    assert result.returncode == 0, (
        "run_analysis.sh failed.\nstdout:\n%s\nstderr:\n%s" %
        (result.stdout, result.stderr)
    )


def test_run_analysis_script():
    """Test that run_analysis.sh exists and is executable."""
    script_path = "/home/user/run_analysis.sh"
    assert os.path.exists(script_path), f"File {script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {script_path} is not executable."


def test_sweep_script():
    """Test that sweep.py exists and actually imports the required libraries."""
    script_path = "/home/user/sweep.py"
    assert os.path.exists(script_path), f"File {script_path} is missing."
    with open(script_path) as f:
        tree = ast.parse(f.read(), filename=script_path)
    modules = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            modules.append(node.module)
    assert any(m == "multiprocessing" or m.startswith("multiprocessing.") for m in modules), \
        "sweep.py must use Python's multiprocessing module."
    assert any(m == "scipy" or m.startswith("scipy.") for m in modules), \
        "sweep.py must use scipy.integrate.odeint."


def test_obs_reshaped():
    """Test that obs_reshaped.csv exists and has the correct reshaped content."""
    csv_path = "/home/user/obs_reshaped.csv"
    assert os.path.exists(csv_path), f"File {csv_path} is missing."
    expected_lines = ["day,infected", "1,10", "2,25", "3,50", "4,80", "5,110"]
    with open(csv_path, "r") as f:
        content = f.read().strip().splitlines()
    assert content == expected_lines, f"Content of {csv_path} does not match the expected reshaped format."


def test_profile_log():
    """Test that profile.log was produced by profiling the executed sweep."""
    log_path = "/home/user/profile.log"
    assert os.path.exists(log_path), f"File {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read()
    assert "function calls" in content or "tottime" in content or "ncalls" in content, \
        f"{log_path} does not appear to contain valid cProfile output."
    assert "sweep.py" in content, "profile.log does not show that sweep.py was profiled."


def test_best_params():
    """Test that best_params.json contains the independently calculated result."""
    json_path = "/home/user/best_params.json"
    assert os.path.exists(json_path), f"File {json_path} is missing."
    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} does not contain valid JSON.")
    assert "beta" in data, "Missing 'beta' in best_params.json"
    assert "gamma" in data, "Missing 'gamma' in best_params.json"
    assert "sse" in data, "Missing 'sse' in best_params.json"
    assert data["beta"] == 0.6, f"Expected best beta to be 0.6, got {data['beta']}"
    assert data["gamma"] == 0.2, f"Expected best gamma to be 0.2, got {data['gamma']}"
    assert isinstance(data["sse"], (int, float)), "SSE should be a number"
    assert data["sse"] > 0, "SSE should be a positive number"
    assert data == expected_result([10, 25, 50, 80, 110]), \
        "best_params.json does not contain the independently calculated rounded SSE."


def test_workflow_really_used_odeint_and_parallel_workers():
    events = read_trace()
    assert any(e["event"] == "pool_init" for e in events), "No multiprocessing Pool was created."
    assert any(e["event"] == "pool_submit" for e in events), "No work was submitted to a multiprocessing Pool."
    ode_events = [e for e in events if e["event"] == "odeint"]
    assert len(ode_events) >= 4, "The four parameter combinations were not solved with odeint."
    assert len({e["pid"] for e in ode_events}) >= 2, \
        "ODE simulations did not execute in multiple worker processes."
    for event in ode_events:
        assert event["y0"] == [990, 10, 0], "odeint was called with incorrect initial conditions."
        assert event["times"] == [1, 2, 3, 4, 5], "odeint was called at incorrect evaluation times."


def test_sweep_responds_to_derived_observations():
    paths = [os.path.join(HOME, n) for n in ("obs_reshaped.csv", "best_params.json", "profile.log")]
    saved = {p: open(p, "rb").read() for p in paths}
    alternate = [10, 14, 20, 28, 39]
    try:
        with open(os.path.join(HOME, "obs_reshaped.csv"), "w") as f:
            f.write("day,infected\n" + "\n".join(f"{d},{v}" for d, v in enumerate(alternate, 1)) + "\n")
        try:
            os.remove(TRACE)
        except FileNotFoundError:
            pass
        os.remove(os.path.join(HOME, "best_params.json"))
        result = run_command(["python3", os.path.join(HOME, "sweep.py")])
        assert result.returncode == 0, "sweep.py failed on derived observations:\n" + result.stderr
        with open(os.path.join(HOME, "best_params.json")) as f:
            actual = json.load(f)
        assert actual == expected_result(alternate), \
            "sweep.py did not recompute the parameter sweep for changed observations."
        events = read_trace()
        ode_pids = {e["pid"] for e in events if e["event"] == "odeint"}
        assert len(ode_pids) >= 2, "The changed-data sweep did not run ODE solves in parallel workers."
    finally:
        for path, content in saved.items():
            with open(path, "wb") as f:
                f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
