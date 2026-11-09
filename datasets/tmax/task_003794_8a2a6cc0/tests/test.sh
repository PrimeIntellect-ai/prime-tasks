#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import glob
import math
import os
import time

import cv2
import numpy as np
import pytest
import requests
from scipy.integrate import solve_ivp

BASE_URL = "http://127.0.0.1:8000"
VIDEO = "/app/oscillator.mp4"


def extract_visible_centres():
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), "Could not open oscillator video"
    centres = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        b, g, r = cv2.split(frame)
        mask = (g > 100) & (g > 1.5 * b) & (g > 1.5 * r)
        ys, xs = np.nonzero(mask)
        if len(xs) >= 500 and xs.min() > 2 and xs.max() < frame.shape[1] - 3 and xs.max() - xs.min() >= 30:
            centres.append(float(xs.mean()))
        else:
            centres.append(None)
    cap.release()
    return centres


EXPECTED_CENTRES = extract_visible_centres()


def simulated_mse(c, k, trajectory):
    times = np.arange(len(trajectory), dtype=float) / 30.0

    def ode(t, y):
        return (y[1], -float(c) * y[1] - float(k) * y[0])

    sol = solve_ivp(
        ode,
        (float(times[0]), float(times[-1])),
        (float(trajectory[0]), 0.0),
        t_eval=times,
        method="RK45",
        rtol=1e-10,
        atol=1e-10,
    )
    assert sol.success and np.all(np.isfinite(sol.y)), "Independent integration failed"
    return float(np.mean((sol.y[0] - np.asarray(trajectory, dtype=float)) ** 2))


def listening_pid(port=8000):
    wanted = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            for fd in os.listdir(proc + "/fd"):
                target = os.readlink(proc + "/fd/" + fd)
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(proc.rsplit("/", 1)[1])
        except (OSError, ValueError):
            pass
    return None


def descendant_count(root_pid):
    parents = {}
    for status in glob.glob("/proc/[0-9]*/status"):
        try:
            pid = int(status.split("/")[2])
            ppid = None
            with open(status) as f:
                for line in f:
                    if line.startswith("PPid:"):
                        ppid = int(line.split()[1])
                        break
            if ppid is not None:
                parents[pid] = ppid
        except (OSError, ValueError, IndexError):
            pass
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, ppid in parents.items():
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return len(descendants) - 1


@pytest.fixture(scope="session", autouse=True)
def wait_for_service():
    start_time = time.time()
    while time.time() - start_time < 30:
        try:
            response = requests.get(f"{BASE_URL}/ping", timeout=1)
            if response.status_code == 200:
                return
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)
    pytest.fail("Service did not start on port 8000 within 30 seconds.")


@pytest.fixture(scope="session")
def trajectory():
    response = requests.get(f"{BASE_URL}/trajectory", timeout=10)
    assert response.status_code == 200
    return response.json()["x"]


def test_ping_endpoint():
    response = requests.get(f"{BASE_URL}/ping", timeout=5)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    data = response.json()
    assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"


def test_implementation_contains_required_scientific_work():
    paths = []
    for root in ("/app", "/home/user"):
        for path in glob.glob(root + "/**/*.py", recursive=True):
            if path == "/app/generate_video.py" or "/site-packages/" in path:
                continue
            paths.append(path)
    assert paths, "No submitted Python implementation was found"
    source = "\n".join(open(p, errors="ignore").read() for p in paths)
    lowered = source.lower()
    assert "videocapture" in lowered and "oscillator.mp4" in lowered, "Implementation must read the supplied video"
    assert "solve_ivp" in source, "Implementation must use adaptive solve_ivp integration"
    assert "rk45" in lowered and "rtol" in lowered and "atol" in lowered, "RK45 tolerances were not configured"
    assert any(x in lowered for x in ("multiprocessing", "processpoolexecutor", "concurrent.futures")), "No parallel evaluation implementation found"
    assert "uniform" in lowered, "Monte Carlo parameters are not sampled uniformly"
    assert any(x in lowered for x in ("isfinite", ".success", "converg")), "No integration convergence/divergence check found"


def test_trajectory_endpoint(trajectory):
    assert isinstance(trajectory, list), "'x' must be a list"
    assert len(trajectory) > 0, "Trajectory list is empty"
    assert 140 <= len(trajectory) <= 160, f"Expected around 150 frames, got {len(trajectory)}"
    assert all(isinstance(val, (int, float)) and not isinstance(val, bool) for val in trajectory), "All trajectory values must be numbers"
    assert all(math.isfinite(float(val)) for val in trajectory), "Trajectory contains non-finite values"

    assert len(trajectory) == len(EXPECTED_CENTRES), "Trajectory must contain one value for every decoded video frame"
    errors = [abs(float(trajectory[i]) - centre) for i, centre in enumerate(EXPECTED_CENTRES) if centre is not None]
    assert len(errors) >= 25, "Too few fully visible frames were decoded from the video"
    assert float(np.mean(errors)) <= 1.5, f"Trajectory does not match video circle centres (mean error {np.mean(errors):.3f}px)"
    assert max(errors) <= 4.0, f"Trajectory does not match the video (maximum visible-frame error {max(errors):.3f}px)"


def test_single_sample_fit_is_evaluated(trajectory):
    response = requests.post(f"{BASE_URL}/fit", json={"num_samples": 1}, timeout=20)
    assert response.status_code == 200, response.text
    data = response.json()
    assert all(key in data for key in ("c", "k", "mse"))
    c, k, mse = float(data["c"]), float(data["k"]), float(data["mse"])
    assert 0.1 <= c <= 2.0
    assert 10.0 <= k <= 50.0
    assert math.isfinite(mse) and mse >= 0.0
    expected = simulated_mse(c, k, trajectory)
    assert math.isclose(mse, expected, rel_tol=2e-4, abs_tol=1e-3), f"Reported MSE {mse} does not equal simulated MSE {expected}"


def test_fit_endpoint(trajectory):
    payload = {"num_samples": 5000}
    server_pid = listening_pid()
    assert server_pid is not None, "Could not identify the process listening on port 8000"

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        future = executor.submit(requests.post, f"{BASE_URL}/fit", json=payload, timeout=60)
        max_children = descendant_count(server_pid)
        while not future.done():
            max_children = max(max_children, descendant_count(server_pid))
            time.sleep(0.01)
        response = future.result()

    assert max_children >= 2, "The fit request did not evaluate samples using multiple worker processes"
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "c" in data, "Response JSON must contain 'c'"
    assert "k" in data, "Response JSON must contain 'k'"
    assert "mse" in data, "Response JSON must contain 'mse'"

    c_val = data["c"]
    k_val = data["k"]
    mse_val = data["mse"]
    assert isinstance(c_val, (int, float)) and not isinstance(c_val, bool)
    assert isinstance(k_val, (int, float)) and not isinstance(k_val, bool)
    assert isinstance(mse_val, (int, float)) and not isinstance(mse_val, bool)
    assert all(math.isfinite(float(v)) for v in (c_val, k_val, mse_val))
    assert 0.1 <= c_val <= 2.0 and 10.0 <= k_val <= 50.0 and mse_val >= 0.0

    expected_mse = simulated_mse(c_val, k_val, trajectory)
    assert math.isclose(mse_val, expected_mse, rel_tol=2e-4, abs_tol=1e-3), f"Reported MSE {mse_val} does not equal simulated MSE {expected_mse}"

    assert math.isclose(c_val, 0.5, abs_tol=0.15), f"Fitted 'c' ({c_val}) is not within tolerance of 0.5"
    assert math.isclose(k_val, 25.0, abs_tol=1.5), f"Fitted 'k' ({k_val}) is not within tolerance of 25.0"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
