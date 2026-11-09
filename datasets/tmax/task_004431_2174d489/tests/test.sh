#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import socket
import subprocess
import time

import cv2
import numpy as np
import pytest
import requests

VIDEO = "/app/experiment.mp4"
SOURCE = "/home/user/sim_source"
TRAJECTORY = "/home/user/fitted_trajectory.json"
URL = "http://127.0.0.1:8080/simulate"
AUTH = {"Authorization": "Bearer sim-token-42"}


def video_fit():
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), f"Could not open {VIDEO}"
    ts, xs, ys = [], [], []
    frame_no = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        peak = float(gray.max())
        if peak > 100:
            mask = gray >= max(100.0, peak * 0.75)
            yy, xx = np.nonzero(mask)
            weights = gray[yy, xx].astype(float)
            ts.append(frame_no)
            xs.append(float(np.average(xx, weights=weights)))
            ys.append(float(np.average(yy, weights=weights)))
        frame_no += 1
    cap.release()
    assert len(ts) >= 10, "Too few visible particle positions were extracted"
    t = np.asarray(ts, dtype=float)
    x = np.asarray(xs, dtype=float)
    y = np.asarray(ys, dtype=float)
    return t, x, y, np.polyfit(t, x, 2), np.polyfit(t, y, 2)


def numeric_sequences(value, path=()):
    found = []
    if isinstance(value, list):
        if 2 <= len(value) <= 12 and all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(float(v)) for v in value):
            found.append((path, np.asarray(value, dtype=float)))
        for i, item in enumerate(value):
            found.extend(numeric_sequences(item, path + (str(i),)))
    elif isinstance(value, dict):
        # Also support coefficient dictionaries keyed by polynomial power.
        try:
            powers = sorted((int(k), float(v)) for k, v in value.items())
        except (TypeError, ValueError):
            powers = []
        if len(powers) >= 2 and [p for p, _ in powers] == list(range(powers[-1][0] + 1)):
            found.append((path, np.asarray([v for _, v in powers], dtype=float)))
        for key, item in value.items():
            found.extend(numeric_sequences(item, path + (str(key),)))
    return found


def best_rmse(coeffs, t, observed):
    errors = []
    for c in (coeffs, coeffs[::-1]):
        predicted = np.polyval(c, t)
        if np.all(np.isfinite(predicted)):
            errors.append(float(np.sqrt(np.mean((predicted - observed) ** 2))))
    return min(errors) if errors else float("inf")


def listener_executable():
    inode = None
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            local, state = fields[1], fields[3]
            if local.upper() == "0100007F:1F90" and state == "0A":
                inode = fields[9]
                break
    assert inode is not None, "No process is listening specifically on 127.0.0.1:8080"

    wanted = f"socket:[{inode}]"
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") == wanted:
                        return f"/proc/{pid}/exe"
                except OSError:
                    pass
        except OSError:
            pass
    pytest.fail("Could not identify the process owning the HTTP listener")


def request_at(t):
    response = requests.get(URL, params={"t": str(t)}, headers=AUTH, timeout=5)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except (ValueError, json.JSONDecodeError):
        pytest.fail(f"Server did not return valid JSON. Response: {response.text}")
    assert "x" in data, "Response JSON missing 'x' key."
    assert "y" in data, "Response JSON missing 'y' key."
    try:
        x, y = float(data["x"]), float(data["y"])
    except (TypeError, ValueError):
        pytest.fail("Response x and y must be numeric")
    assert math.isfinite(x) and math.isfinite(y), "Response coordinates must be finite"
    return x, y


def test_fitted_trajectory_json():
    assert os.path.isfile(TRAJECTORY), f"Missing fitted trajectory file: {TRAJECTORY}"
    with open(TRAJECTORY, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {TRAJECTORY} is not valid JSON.")
    assert isinstance(data, (dict, list)), "JSON should be a dictionary or a list."

    t, observed_x, observed_y, _, _ = video_fit()
    sequences = numeric_sequences(data)
    assert len(sequences) >= 2, "JSON must contain numeric polynomial coefficient sequences for x and y"

    x_labelled = [(p, c) for p, c in sequences if "x" in ".".join(p).lower()]
    y_labelled = [(p, c) for p, c in sequences if "y" in ".".join(p).lower()]
    x_choices = x_labelled or sequences
    y_choices = y_labelled or sequences
    valid_pair = False
    for xp, xc in x_choices:
        for yp, yc in y_choices:
            if xp == yp:
                continue
            if best_rmse(xc, t, observed_x) <= 1.5 and best_rmse(yc, t, observed_y) <= 1.5:
                valid_pair = True
                break
        if valid_pair:
            break
    assert valid_pair, "Stored coefficients do not fit the particle coordinates extracted from the video"


def test_cpp_build_and_integrator_fix():
    result = subprocess.run(["make", "-B"], cwd=SOURCE, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    assert result.returncode == 0, f"Provided Makefile failed to compile:\n{result.stdout}"
    sim = os.path.join(SOURCE, "sim")
    assert os.path.isfile(sim) and os.access(sim, os.X_OK), "Makefile did not produce executable sim"
    with open(sim, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled simulation must be a native executable"

    probe = "/tmp/integrator_probe.cpp"
    with open(probe, "w") as f:
        f.write(r'''#include <cmath>
#include <iostream>
double compute_dt(double, double, double);
int main() {
    double high = compute_dt(1.0, 4.0, 1.0);
    double low  = compute_dt(1.0, 0.25, 1.0);
    if (!std::isfinite(high) || !std::isfinite(low) || high <= 0 || low <= 0) return 2;
    if (!(high < 1.0 && low > 1.0)) return 3;
    return 0;
}
''')
    compile_probe = subprocess.run(["g++", "-std=c++11", probe, os.path.join(SOURCE, "integrator.cpp"), "-o", "/tmp/integrator_probe"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    assert compile_probe.returncode == 0, f"Could not compile integrator probe:\n{compile_probe.stdout}"
    run_probe = subprocess.run(["/tmp/integrator_probe"], timeout=5)
    assert run_probe.returncode == 0, "Step-size adaptation must reduce dt for excessive error and increase it for error below tolerance"


def test_server_is_native_cpp_process():
    exe = listener_executable()
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The process serving port 8080 is not a native C++ executable"


def test_simulation_server_success_and_dynamic_behavior():
    t, _, _, x_coeff, y_coeff = video_fit()

    # Preserve the original fixed assertion.
    x15, y15 = request_at(15)
    assert math.isclose(x15, 40.0, abs_tol=1.0), f"Expected x ~ 40.0, got {x15}"
    assert math.isclose(y15, 27.5, abs_tol=1.0), f"Expected y ~ 27.5, got {y15}"

    # Exercise an unpredictable subset of the visible trajectory, with expected
    # answers independently derived from the supplied video.
    candidates = [int(v) for v in t if int(v) != 15]
    chosen = random.SystemRandom().sample(candidates, min(8, len(candidates)))
    for step in chosen:
        actual_x, actual_y = request_at(step)
        expected_x = float(np.polyval(x_coeff, step))
        expected_y = float(np.polyval(y_coeff, step))
        assert math.isclose(actual_x, expected_x, abs_tol=1.5), f"At t={step}, expected x ~ {expected_x}, got {actual_x}"
        assert math.isclose(actual_y, expected_y, abs_tol=1.5), f"At t={step}, expected y ~ {expected_y}, got {actual_y}"


def test_simulation_server_auth():
    url = URL + "?t=15"
    try:
        response = requests.get(url, timeout=5)
        assert response.status_code in (401, 403), f"Expected 401 or 403 for missing auth, got {response.status_code}"
    except requests.exceptions.RequestException:
        pass

    try:
        response = requests.get(url, headers={"Authorization": "Bearer wrong-token"}, timeout=5)
        assert response.status_code in (401, 403), f"Expected 401 or 403 for invalid auth, got {response.status_code}"
    except requests.exceptions.RequestException:
        pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
