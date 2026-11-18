#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import time

import h5py
import pytest
import requests
import numpy as np
from scipy.interpolate import interp1d
from scipy.optimize import brentq

URL = "http://127.0.0.1:8080/metrics"
AUTH = {"X-Auth-Token": "perf-eng-secret"}
STATE_FILE = "/home/user/initial_states.h5"


def fun(t, state):
    x, y, vx, vy = state
    return np.array([vx, vy, -x - 0.5 * x**3, -y - 0.5 * y**3])


def solve_ivp_adaptive_ref(fun, t_span, y0, tol=1e-6, dt_init=0.01):
    t_start, t_end = t_span
    t = [t_start]
    y = [np.array(y0)]
    dt = dt_init

    t_curr = t_start
    y_curr = np.array(y0)

    while t_curr < t_end:
        if t_curr + dt > t_end:
            dt = t_end - t_curr

        k1 = fun(t_curr, y_curr)
        k2 = fun(t_curr + dt, y_curr + dt * k1)

        y_next = y_curr + dt * 0.5 * (k1 + k2)
        y_euler = y_curr + dt * k1

        error = np.max(np.abs(y_next - y_euler)) + 1e-12

        if error < tol:
            t_curr += dt
            y_curr = y_next
            t.append(t_curr)
            y.append(y_curr)

        dt = dt * (tol / error)**0.2
        dt = np.clip(dt, 1e-6, 0.5)

    return np.array(t), np.array(y)


def compute_reference_values(y0=None):
    if y0 is None:
        y0 = np.array([1.0, 1.0, 0.0, 0.0], dtype=np.float64)
    else:
        y0 = np.asarray(y0, dtype=np.float64)

    np.random.seed(42)
    perturbed_states = y0 + np.random.normal(0, 0.01, (100, 4))

    crossing_times = []
    for state in perturbed_states:
        t_arr, y_arr = solve_ivp_adaptive_ref(fun, (0, 10), state)
        y_vals = y_arr[:, 1]
        vy_vals = y_arr[:, 3]

        for i in range(len(t_arr)-1):
            if y_vals[i] > 0 and y_vals[i+1] <= 0:
                start_idx = max(0, i-1)
                end_idx = min(len(t_arr), i+3)

                t_sub = t_arr[start_idx:end_idx]
                y_sub = y_vals[start_idx:end_idx]

                kind = 'cubic' if len(t_sub) >= 4 else 'linear'
                f_interp = interp1d(t_sub, y_sub, kind=kind)

                try:
                    t_cross = brentq(f_interp, t_arr[i], t_arr[i+1])
                    crossing_times.append(t_cross)
                except ValueError:
                    f_interp_lin = interp1d(t_arr[i:i+2], y_vals[i:i+2], kind='linear')
                    t_cross = brentq(f_interp_lin, t_arr[i], t_arr[i+1])
                    crossing_times.append(t_cross)
                break

    crossing_times = np.array(crossing_times)
    assert len(crossing_times) == 100

    np.random.seed(42)
    boot_means = []
    for _ in range(1000):
        sample = np.random.choice(crossing_times, size=len(crossing_times), replace=True)
        boot_means.append(np.mean(sample))

    t_crossing_mean = np.mean(crossing_times)
    ci_95_lower = np.percentile(boot_means, 2.5)
    ci_95_upper = np.percentile(boot_means, 97.5)

    return t_crossing_mean, ci_95_lower, ci_95_upper


def assert_metrics(data, expected):
    assert "t_crossing_mean" in data, "Response missing 't_crossing_mean'"
    assert "ci_95_lower" in data, "Response missing 'ci_95_lower'"
    assert "ci_95_upper" in data, "Response missing 'ci_95_upper'"

    ref_mean, ref_lower, ref_upper = expected
    tol = 0.05
    assert abs(data["t_crossing_mean"] - ref_mean) < tol, f"t_crossing_mean {data['t_crossing_mean']} is not close to reference {ref_mean}"
    assert abs(data["ci_95_lower"] - ref_lower) < tol, f"ci_95_lower {data['ci_95_lower']} is not close to reference {ref_lower}"
    assert abs(data["ci_95_upper"] - ref_upper) < tol, f"ci_95_upper {data['ci_95_upper']} is not close to reference {ref_upper}"


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if int(local.rsplit(':', 1)[1], 16) == 8080 and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(entry)
        except (FileNotFoundError, PermissionError):
            continue
    raise AssertionError("Could not identify the server listening on port 8080")


def saved_launch(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        args = [x.decode() for x in f.read().split(b"\0") if x]
    with open(f"/proc/{pid}/environ", "rb") as f:
        env_items = [x for x in f.read().split(b"\0") if x]
    env = {}
    for item in env_items:
        key, sep, value = item.partition(b"=")
        if sep:
            env[key.decode()] = value.decode()
    cwd = os.readlink(f"/proc/{pid}/cwd")
    assert args, "Server has an empty command line"
    return args, cwd, env


def stop_pid(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(50):
        if not os.path.exists(f"/proc/{pid}"):
            return
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.2)


def stop_current_listener():
    try:
        stop_pid(listener_pid())
    except AssertionError:
        pass


def start_server(launch):
    args, cwd, env = launch
    subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    last_error = None
    for _ in range(100):
        try:
            response = requests.get(URL, headers=AUTH, timeout=0.5)
            if response.status_code == 200:
                return response
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"Restarted server did not become ready: {last_error}")


def write_state(state):
    with h5py.File(STATE_FILE, "w") as f:
        f.create_dataset("state_0", data=np.asarray(state, dtype=np.float64))


def test_metrics_endpoint():
    resp_no_auth = requests.get(URL)
    assert resp_no_auth.status_code == 401, f"Expected 401 Unauthorized without auth header, got {resp_no_auth.status_code}"

    resp_wrong_auth = requests.get(URL, headers={"X-Auth-Token": "wrong-secret"})
    assert resp_wrong_auth.status_code == 401, f"Expected 401 Unauthorized with wrong auth header, got {resp_wrong_auth.status_code}"

    resp_auth = requests.get(URL, headers=AUTH)
    assert resp_auth.status_code == 200, f"Expected 200 OK with correct auth header, got {resp_auth.status_code}"

    data = resp_auth.json()
    assert_metrics(data, compute_reference_values())


def test_pipeline_uses_initial_state_and_recomputes_results():
    # Generate an unpredictable but well-behaved initial condition whose crossing
    # is substantially different from the image's fixed state.
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    challenge = np.array([
        rng.uniform(0.7, 1.3),
        rng.uniform(0.55, 0.75),
        rng.uniform(-0.15, 0.15),
        rng.uniform(-0.35, -0.20),
    ], dtype=np.float64)
    expected = compute_reference_values(challenge)

    with open(STATE_FILE, "rb") as f:
        original_h5 = f.read()

    pid = listener_pid()
    launch = saved_launch(pid)
    stop_pid(pid)

    try:
        write_state(challenge)
        response = start_server(launch)
        assert response.status_code == 200
        assert_metrics(response.json(), expected)
    finally:
        stop_current_listener()
        with open(STATE_FILE, "wb") as f:
            f.write(original_h5)
        start_server(launch)


def test_scipack_fix():
    with open("/app/scipack-1.0.0/scipack/ode.py", "r") as f:
        content = f.read()
    assert "dt = dt * (tol / error)" in content or "dt = dt * (error / tol)**(-0.2)" in content or "dt *= (tol / error)" in content, "The adaptive step size bug in scipack/ode.py does not appear to be fixed."

    # Execute the vendored solver on a case where the bad formula continually
    # enlarges rejected steps and never makes progress. The corrected solver
    # must finish promptly and produce an accurate, monotone trajectory.
    code = r'''
import sys
import numpy as np
sys.path.insert(0, "/app/scipack-1.0.0")
from scipack.ode import solve_ivp_adaptive

def rhs(t, y):
    return np.asarray(y, dtype=float)

t, y = solve_ivp_adaptive(rhs, (0.0, 0.02), np.array([1.0]), tol=1e-6, dt_init=0.01)
assert len(t) > 2
assert np.all(np.diff(t) > 0)
assert abs(t[-1] - 0.02) < 1e-12
assert np.all(np.isfinite(y))
assert abs(y[-1, 0] - np.exp(0.02)) < 1e-4
'''
    subprocess.run(["python3", "-c", code], check=True, timeout=8)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
