#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess

import cv2
import numpy as np
import pytest
import requests

URL = "http://127.0.0.1:8050/api/best_fit"
HEADERS = {"X-Auth-Token": "physics-2024"}
PROJECT = "/home/user/sim_project"


def parse_trajectory(text):
    rows = []
    for line in text.splitlines():
        parts = line.strip().split()
        if len(parts) != 2:
            continue
        try:
            t, x = map(float, parts)
        except ValueError:
            continue
        if math.isfinite(t) and math.isfinite(x):
            rows.append((t, x))
    assert len(rows) >= 100, "Simulator did not produce a sufficiently dense trajectory"
    arr = np.asarray(rows, dtype=float)
    order = np.argsort(arr[:, 0])
    arr = arr[order]
    arr = arr[np.r_[True, np.diff(arr[:, 0]) > 1e-12]]
    assert np.all(np.diff(arr[:, 0]) > 0), "Simulation timestamps must be increasing"
    assert arr[0, 0] <= 0.001 and arr[-1, 0] >= 9.95, "Trajectory must cover approximately 0 through 10 seconds"
    return arr


def run_simulator(executable, c):
    proc = subprocess.run(
        [executable, f"{c:.8f}"], capture_output=True, text=True,
        timeout=5, check=False
    )
    assert proc.returncode == 0, f"Simulator failed for c={c}: {proc.stderr}"
    return parse_trajectory(proc.stdout)


def analytic_x(t, c):
    omega = math.sqrt(9.81 - (c / 2.0) ** 2)
    return np.exp(-c * t / 2.0) * (
        np.cos(omega * t) + (c / (2.0 * omega)) * np.sin(omega * t)
    )


def assert_accurate(executable, c):
    trajectory = run_simulator(executable, c)
    sample_t = np.linspace(0.0, 9.9, 250)
    actual = np.interp(sample_t, trajectory[:, 0], trajectory[:, 1])
    expected = analytic_x(sample_t, c)
    mse = float(np.mean((actual - expected) ** 2))
    assert mse < 3e-3, f"Simulator is inaccurate for c={c}; analytic MSE was {mse}"
    return trajectory


def extract_video_reference():
    cap = cv2.VideoCapture("/app/pendulum_experiment.mp4")
    assert cap.isOpened(), "Could not open the experimental video"
    fps = cap.get(cv2.CAP_PROP_FPS)
    assert abs(fps - 30.0) < 0.1, f"Unexpected video frame rate: {fps}"

    xs = []
    width = None
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        width = frame.shape[1]
        b, g, r = cv2.split(frame)
        mask = ((r.astype(np.int16) > g.astype(np.int16) + 60) &
                (r.astype(np.int16) > b.astype(np.int16) + 60) &
                (r > 120)).astype(np.uint8)
        moments = cv2.moments(mask)
        assert moments["m00"] > 0, "A video frame did not contain a detectable red bob"
        xs.append(moments["m10"] / moments["m00"])
    cap.release()

    assert len(xs) == 300, f"Expected 300 video frames, found {len(xs)}"
    displacement = np.asarray(xs, dtype=float) - width / 2.0
    assert abs(displacement[0]) > 1.0
    displacement /= abs(displacement[0])
    assert abs(displacement[0] - 1.0) < 1e-9
    times = np.arange(len(displacement), dtype=float) / fps
    return times, displacement


def find_precompiled_simulator():
    candidates = []
    for root, _, files in os.walk(PROJECT):
        for name in files:
            path = os.path.join(root, name)
            try:
                if not os.path.isfile(path) or not os.access(path, os.X_OK):
                    continue
                with open(path, "rb") as f:
                    if f.read(4) == b"\x7fELF":
                        candidates.append(path)
            except OSError:
                pass

    assert candidates, "No compiled C++ simulation executable was left in sim_project"
    errors = []
    for candidate in candidates:
        try:
            assert_accurate(candidate, 0.73)
            return candidate
        except Exception as exc:
            errors.append(f"{candidate}: {exc}")
    pytest.fail("No compiled executable behaved as the requested simulator: " + "; ".join(errors))


def check_workflow_scripts():
    python_sources = []
    for base in ("/home/user", "/app"):
        for root, _, files in os.walk(base):
            for name in files:
                if name.endswith(".py"):
                    path = os.path.join(root, name)
                    try:
                        with open(path, "r", encoding="utf-8", errors="ignore") as f:
                            python_sources.append((path, f.read().lower()))
                    except OSError:
                        pass

    extraction = [p for p, s in python_sources if "ffmpeg" in s and ("cv2" in s or "opencv" in s)]
    orchestration = [p for p, s in python_sources
                     if ("subprocess" in s or "os.system" in s or "popen" in s)
                     and ("mse" in s or "mean_squared" in s or "mean((" in s)
                     and ("interpol" in s or "np.interp" in s)]
    assert extraction, "No Python extraction script using ffmpeg and OpenCV was found"
    assert orchestration, "No orchestrator that runs the simulator, interpolates, and computes MSE was found"


@pytest.fixture(scope="session")
def verified_result():
    assert os.path.isfile(os.path.join(PROJECT, "main.cpp")), "main.cpp is missing"
    assert os.path.isfile(os.path.join(PROJECT, "integrator.cpp")), "integrator.cpp is missing"

    check_workflow_scripts()
    find_precompiled_simulator()

    verified_binary = "/tmp/verified_pendulum_sim"
    build = subprocess.run(
        ["g++", "-std=c++17", "-O2", os.path.join(PROJECT, "main.cpp"),
         os.path.join(PROJECT, "integrator.cpp"), "-o", verified_binary],
        capture_output=True, text=True, timeout=30, check=False
    )
    assert build.returncode == 0, f"C++ simulation sources do not compile: {build.stderr}"

    for c in (0.10, 0.30, 0.80):
        assert_accurate(verified_binary, c)

    video_t, reference = extract_video_reference()
    scores = []
    for i in range(101):
        c = i / 100.0
        trajectory = run_simulator(verified_binary, c)
        simulated = np.interp(video_t, trajectory[:, 0], trajectory[:, 1])
        mse = float(np.mean((simulated - reference) ** 2))
        scores.append((mse, c))
    expected_mse, expected_c = min(scores)
    return expected_c, expected_mse, len(reference)


def test_service_running_and_auth():
    """Test that the service is running and enforces authentication."""
    try:
        response_no_auth = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response_no_auth.status_code in [401, 403], \
        f"Expected 401 or 403 when missing auth token, got {response_no_auth.status_code}"


def test_service_correct_response(verified_result):
    """Test that the service returns computed results matching the video and repaired simulator."""
    try:
        response = requests.get(URL, headers=HEADERS, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert "optimal_c" in data, "Missing 'optimal_c' in JSON response"
    assert "mse" in data, "Missing 'mse' in JSON response"
    assert "datapoints_compared" in data, "Missing 'datapoints_compared' in JSON response"

    optimal_c = data["optimal_c"]
    mse = data["mse"]
    datapoints_compared = data["datapoints_compared"]

    assert isinstance(optimal_c, (int, float)), "optimal_c must be a number"
    assert 0.28 <= optimal_c <= 0.32, f"optimal_c {optimal_c} is not within the expected range [0.28, 0.32]"

    assert isinstance(mse, (int, float)), "mse must be a number"
    assert mse < 0.05, f"mse {mse} is too high (expected < 0.05)"

    assert isinstance(datapoints_compared, int), "datapoints_compared must be an integer"
    assert 290 <= datapoints_compared <= 310, f"datapoints_compared {datapoints_compared} is not close to 300"

    expected_c, expected_mse, expected_count = verified_result
    assert math.isfinite(float(optimal_c)) and math.isfinite(float(mse))
    assert abs(float(optimal_c) - expected_c) < 0.005, \
        f"Service reported c={optimal_c}, but video/simulator optimization gives {expected_c:.2f}"
    mse_tolerance = max(1e-7, abs(expected_mse) * 0.20)
    assert abs(float(mse) - expected_mse) <= mse_tolerance, \
        f"Service reported MSE={mse}, but independently computed MSE is {expected_mse}"
    assert datapoints_compared == expected_count, \
        f"Service reported {datapoints_compared} datapoints, but the video contains {expected_count}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
