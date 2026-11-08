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
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess

import cv2
import numpy as np
import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
VIDEO = "/app/fluorescence.mp4"
MODEL_C = "/home/user/model.c"
MODEL = "/home/user/model"


def extract_expected_trajectory():
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), f"Could not open {VIDEO}"
    points = []
    frame = 0
    while True:
        ok, image = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        mask = (gray >= 128).astype(np.uint8)
        count = int(mask.sum())
        assert count > 0, f"No bright organism found in frame {frame}"
        ys, xs = np.nonzero(mask)
        points.append((float(xs.mean()), float(ys.mean())))
        frame += 1
    cap.release()
    assert len(points) == 100, f"Reference video contains {len(points)} frames, expected 100"
    return np.asarray(points, dtype=float)


EXPECTED = extract_expected_trajectory()
T = np.arange(len(EXPECTED), dtype=float)


def linear_fit(values):
    design = np.column_stack((np.ones(len(T)), T))
    coeff, _, _, _ = np.linalg.lstsq(design, values, rcond=None)
    fitted = design @ coeff
    return coeff, float(np.sum((values - fitted) ** 2))


def nonlinear_fit(values):
    best = None
    for omega in np.linspace(0.05, 0.2, 3001):
        design = np.column_stack((np.ones(len(T)), T, np.sin(omega * T)))
        coeff, _, _, _ = np.linalg.lstsq(design, values, rcond=None)
        sse = float(np.sum((values - design @ coeff) ** 2))
        if best is None or sse < best[0]:
            best = (sse, float(omega), coeff)
    return best


X_COEFF, _ = linear_fit(EXPECTED[:, 0])
Y_LINEAR_COEFF, EXPECTED_LINEAR_SSE = linear_fit(EXPECTED[:, 1])
EXPECTED_NONLINEAR_SSE, EXPECTED_OMEGA, Y_NONLINEAR_COEFF = nonlinear_fit(EXPECTED[:, 1])
EXPECTED_PARAMS = {
    "x0": float(X_COEFF[0]),
    "vx": float(X_COEFF[1]),
    "y0": float(Y_NONLINEAR_COEFF[0]),
    "vy": float(Y_NONLINEAR_COEFF[1]),
    "A": float(Y_NONLINEAR_COEFF[2]),
    "omega": EXPECTED_OMEGA,
}


def get_json(path):
    try:
        response = requests.get(f"{BASE_URL}{path}", timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {BASE_URL}{path}: {exc}")
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    try:
        return response.json()
    except (ValueError, json.JSONDecodeError) as exc:
        pytest.fail(f"{path} did not return valid JSON: {exc}")


def finite_number(value, name):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{name} must be numeric"
    assert math.isfinite(float(value)), f"{name} must be finite"
    return float(value)


def model_is_listening():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass
    for pid in (p for p in os.listdir("/proc") if p.isdigit()):
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                    if target.startswith("socket:[") and target[8:-1] in inodes:
                        return os.path.samefile(f"/proc/{pid}/exe", MODEL)
                except OSError:
                    pass
        except OSError:
            pass
    return False


def test_c_program_is_compiled_and_substantive():
    assert os.path.exists(MODEL_C), "C program /home/user/model.c is missing."
    assert os.path.isfile(MODEL), "Compiled program /home/user/model is missing."
    assert os.access(MODEL, os.X_OK), "/home/user/model is not executable."
    with open(MODEL, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "/home/user/model is not a compiled ELF binary"

    source = open(MODEL_C, encoding="utf-8", errors="replace").read()
    assert re.search(r"\b(?:float|double)\s+\w+\s*\[[^\]]+\]\s*\[[^\]]+\]", source), \
        "model.c must represent the trajectory as a two-dimensional numeric array"
    assert re.search(r"\bsin\s*\(", source), "model.c does not evaluate the sinusoidal model"
    assert re.search(r"\bfor\s*\(|\bwhile\s*\(", source), "model.c contains no iterative fitting loop"
    assert re.search(r"sse|sum[^;\n]*squared|squared[^;\n]*error", source, re.I), \
        "model.c does not contain an SSE calculation"
    assert re.search(r"f[_ ]?(stat|statistic)|fstat", source, re.I), \
        "model.c does not contain an F-statistic calculation"

    compiled = "/tmp/model_recompiled"
    result = subprocess.run(
        ["gcc", "-O2", MODEL_C, "-o", compiled, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, f"model.c does not compile: {result.stderr}"

    csv_path = "/tmp/verified_trajectory.csv"
    with open(csv_path, "w") as handle:
        for i, (x, y) in enumerate(EXPECTED):
            handle.write(f"{i},{x:.8f},{y:.8f}\n")
    stdin_data = "".join(f"{x:.8f} {y:.8f}\n" for x, y in EXPECTED)
    ran_successfully = False
    for args, input_data in [([MODEL], None), ([MODEL, csv_path], None), ([MODEL], stdin_data)]:
        try:
            execution = subprocess.run(
                args, input=input_data, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=2
            )
            if execution.returncode == 0:
                ran_successfully = True
                break
        except subprocess.TimeoutExpired:
            if model_is_listening():
                ran_successfully = True
                break
    assert ran_successfully or model_is_listening(), \
        "The compiled /home/user/model could not be successfully executed on trajectory data"


def test_api_trajectory():
    data = get_json("/api/trajectory")
    assert isinstance(data, list), "Expected a JSON array for trajectory"
    assert len(data) == 100, f"Expected 100 frames, got {len(data)}"

    first_frame = data[0]
    assert "frame" in first_frame and first_frame["frame"] == 0, "First frame should have frame=0"
    assert "x" in first_frame and "y" in first_frame, "Trajectory objects must have 'x' and 'y' keys"
    assert math.isclose(first_frame["x"], 100.0, abs_tol=2.0), f"Expected x[0] ~ 100.0, got {first_frame['x']}"
    assert math.isclose(first_frame["y"], 100.0, abs_tol=2.0), f"Expected y[0] ~ 100.0, got {first_frame['y']}"

    for i, item in enumerate(data):
        assert isinstance(item, dict), f"Trajectory item {i} must be an object"
        assert item.get("frame") == i, f"Trajectory item {i} has incorrect frame index"
        x = finite_number(item.get("x"), f"trajectory[{i}].x")
        y = finite_number(item.get("y"), f"trajectory[{i}].y")
        expected_x, expected_y = EXPECTED[i]
        assert math.isclose(x, expected_x, abs_tol=1.25), \
            f"Frame {i} x does not match the video centroid: got {x}, expected {expected_x}"
        assert math.isclose(y, expected_y, abs_tol=1.25), \
            f"Frame {i} y does not match the video centroid: got {y}, expected {expected_y}"


def test_api_parameters():
    data = get_json("/api/parameters")
    assert isinstance(data, dict), "Expected a JSON object for parameters"
    values = {}
    for key in ["vx", "x0", "y0", "vy", "A", "omega"]:
        assert key in data, f"Missing key '{key}' in parameters response"
        values[key] = finite_number(data[key], key)

    assert math.isclose(values["A"], 10.0, abs_tol=1.5), f"Expected A ~ 10.0, got {values['A']}"
    assert math.isclose(values["omega"], 0.1, abs_tol=0.05), f"Expected omega ~ 0.1, got {values['omega']}"
    tolerances = {"vx": 0.10, "x0": 2.0, "y0": 3.0, "vy": 0.08, "A": 1.5, "omega": 0.015}
    for key, tolerance in tolerances.items():
        assert math.isclose(values[key], EXPECTED_PARAMS[key], abs_tol=tolerance), \
            f"Fitted {key} is incorrect: got {values[key]}, expected approximately {EXPECTED_PARAMS[key]}"


def test_api_stats_are_computed_from_the_fit():
    trajectory = get_json("/api/trajectory")
    params = get_json("/api/parameters")
    data = get_json("/api/stats")

    assert "f_statistic" in data, "Missing 'f_statistic' in stats response"
    assert "better_model" in data, "Missing 'better_model' in stats response"
    assert data["better_model"] == "nonlinear", f"Expected better_model to be 'nonlinear', got {data['better_model']}"
    reported_f = finite_number(data["f_statistic"], "f_statistic")

    y = np.asarray([finite_number(row["y"], "trajectory y") for row in trajectory])
    _, linear_sse = linear_fit(y)
    y0 = finite_number(params["y0"], "y0")
    vy = finite_number(params["vy"], "vy")
    amplitude = finite_number(params["A"], "A")
    omega = finite_number(params["omega"], "omega")
    nonlinear_prediction = y0 + vy * T + amplitude * np.sin(omega * T)
    nonlinear_sse = float(np.sum((y - nonlinear_prediction) ** 2))
    assert nonlinear_sse < linear_sse, "Returned nonlinear parameters do not improve on the linear Y model"

    calculated_f = ((linear_sse - nonlinear_sse) / 2.0) / (nonlinear_sse / (len(y) - 4))
    assert calculated_f > 3.0, f"Calculated F-statistic should select nonlinear, got {calculated_f}"
    assert math.isclose(reported_f, calculated_f, rel_tol=0.20, abs_tol=5.0), \
        f"Reported F-statistic {reported_f} is inconsistent with the returned trajectory and parameters ({calculated_f})"
    assert data["better_model"] == ("nonlinear" if reported_f > 3.0 else "linear"), \
        "better_model does not follow the required F > 3.0 rule"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
