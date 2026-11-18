#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_api.py
import csv
import json
import math
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import requests
from PIL import Image, ImageDraw, ImageFont
from scipy.stats import t

BASE = "http://127.0.0.1:8000"
FEATURES = Path("/app/data/features.csv")
TARGETS = Path("/app/data/targets.csv")
SPECS = Path("/app/data/specs.png")


def expected_model(feature_rows, target_rows, alpha):
    targets_by_id = {int(row[0]): float(row[1]) for row in target_rows}
    ordered = sorted(feature_rows, key=lambda row: int(row[0]))
    X = np.asarray([[1.0, float(r[1]), float(r[2]), float(r[3])] for r in ordered], dtype=float)
    y = np.asarray([targets_by_id[int(r[0])] for r in ordered], dtype=float)
    beta = np.linalg.solve(X.T @ X, X.T @ y)
    residuals = y - X @ beta
    df = len(y) - X.shape[1]
    sigma2 = float(residuals @ residuals) / df
    covariance = sigma2 * np.linalg.inv(X.T @ X)
    se = np.sqrt(np.diag(covariance))
    critical = float(t.ppf(1.0 - alpha / 2.0, df))
    ci = np.column_stack((beta - critical * se, beta + critical * se))
    return beta, ci


def assert_prediction(payload, expected, rel_tol=1e-3, abs_tol=1e-3):
    url = BASE + "/predict"
    response = requests.post(url, json=payload, timeout=5)
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    data = response.json()
    assert "prediction" in data, "Response JSON missing 'prediction' key"
    actual = data["prediction"]
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
    assert math.isfinite(float(actual))
    assert math.isclose(float(actual), float(expected), rel_tol=rel_tol, abs_tol=abs_tol), (
        f"Prediction mismatch. Expected approx {expected}, got {actual}"
    )


def assert_ci(expected_ci):
    url = BASE + "/ci"
    response = requests.get(url, timeout=5)
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    data = response.json()
    expected_keys = ["intercept", "x1", "x2", "x3"]
    for key in expected_keys:
        assert key in data, f"Response JSON missing key '{key}'"
        assert isinstance(data[key], (list, tuple)), f"CI for '{key}' must be an array"
        assert len(data[key]) == 2, f"Expected 2 values for CI of '{key}'"

    for i, key in enumerate(expected_keys):
        lower_expected, upper_expected = expected_ci[i]
        lower_actual, upper_actual = data[key]
        assert isinstance(lower_actual, (int, float)) and not isinstance(lower_actual, bool)
        assert isinstance(upper_actual, (int, float)) and not isinstance(upper_actual, bool)
        assert math.isfinite(float(lower_actual)) and math.isfinite(float(upper_actual))
        assert math.isclose(float(lower_actual), float(lower_expected), rel_tol=1e-2, abs_tol=1e-2), (
            f"CI lower bound mismatch for {key}. Expected approx {lower_expected}, got {lower_actual}"
        )
        assert math.isclose(float(upper_actual), float(upper_expected), rel_tol=1e-2, abs_tol=1e-2), (
            f"CI upper bound mismatch for {key}. Expected approx {upper_expected}, got {upper_actual}"
        )


def listener_pids(port=8000):
    inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted_port and fields[3] == "0A":
                inodes.add(fields[9])

    found = set()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            for fd in (entry / "fd").iterdir():
                try:
                    link = os.readlink(fd)
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    found.add(int(entry.name))
                    break
        except OSError:
            continue
    return found


def process_launch_info(pid):
    raw = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    argv = [part.decode("utf-8", "surrogateescape") for part in raw if part]
    assert argv, "Could not determine the API server command"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    for item in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode("utf-8", "surrogateescape")] = value.decode("utf-8", "surrogateescape")
    return argv, cwd, env


def stop_listeners():
    deadline = time.time() + 8
    while time.time() < deadline:
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            if pid not in (1, os.getpid()):
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        time.sleep(0.25)
    for pid in listener_pids():
        if pid not in (1, os.getpid()):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.5)
    assert not listener_pids(), "Could not stop the original API server for the retraining check"


def wait_for_server(proc):
    deadline = time.time() + 20
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"API server exited during restart with status {proc.returncode}")
        try:
            response = requests.get(BASE + "/ci", timeout=1)
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    raise AssertionError(f"Restarted API server did not become ready: {last_error}")


def write_dynamic_fixture():
    # The feature and target orders deliberately differ, so a positional concat
    # cannot accidentally pass in place of the requested customer_id join.
    feature_rows = [
        [311, -2.4, 1.3, 0.7], [205, 0.2, -1.1, 2.8],
        [487, 3.6, 0.4, -2.0], [129, 1.1, 2.9, 1.5],
        [908, -0.8, 4.2, -1.4], [654, 2.7, -2.5, 0.3],
        [777, 4.1, 1.8, 2.2], [402, -3.2, -0.7, -2.6],
        [516, 1.9, 3.5, -0.9], [833, 0.6, 0.1, 4.0],
        [274, -1.5, 2.1, 3.1], [990, 5.2, -1.6, 1.0],
        [348, 2.3, 5.0, -3.2], [721, -0.1, -3.4, 1.9],
        [615, 3.0, 2.4, 0.0], [188, -2.0, 0.8, -1.1],
    ]
    noise = {
        129: 0.22, 188: -0.31, 205: 0.14, 274: 0.38,
        311: -0.27, 348: 0.09, 402: 0.33, 487: -0.18,
        516: -0.42, 615: 0.29, 654: -0.11, 721: 0.17,
        777: -0.35, 833: 0.26, 908: -0.08, 990: 0.21,
    }
    targets = []
    for cid, x1, x2, x3 in feature_rows:
        y = -1.75 + 2.4 * x1 - 0.85 * x2 + 1.3 * x3 + noise[cid]
        targets.append([cid, y])
    target_order = [8, 1, 14, 5, 11, 3, 15, 0, 9, 6, 2, 13, 7, 12, 4, 10]
    target_rows = [targets[i] for i in target_order]

    with FEATURES.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["customer_id", "x1", "x2", "x3"])
        writer.writerows(feature_rows)
    with TARGETS.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["customer_id", "y"])
        writer.writerows(target_rows)

    image = Image.new("RGB", (640, 180), "white")
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 38)
    except OSError:
        font = ImageFont.load_default()
    draw.text((20, 25), "SIGNIFICANCE LEVEL", fill="black", font=font)
    draw.text((20, 90), "ALPHA=0.10", fill="black", font=font)
    image.save(SPECS)
    return feature_rows, target_rows


def main():
    # Preserve the original fixture assertions.
    initial_features = [
        [1, 1.5, 2.3, 0.5], [2, 2.0, 1.1, -1.2],
        [3, 3.1, 4.5, 1.0], [4, 0.5, 0.8, 0.1],
        [5, 4.2, 3.3, -2.5], [6, 2.2, 2.2, 2.2],
        [7, 1.8, 4.1, 0.0], [8, 5.0, 1.0, 1.0],
        [9, 3.5, 2.9, -0.5], [10, 0.1, 0.2, 0.3],
    ]
    initial_targets = [
        [1, 5.6], [2, 4.2], [3, 11.5], [4, 2.0], [5, 8.1],
        [6, 7.8], [7, 8.0], [8, 9.5], [9, 7.4], [10, 0.5],
    ]
    beta, ci = expected_model(initial_features, initial_targets, 0.05)
    fixed_payload = {"x1": 2.0, "x2": 3.5, "x3": -1.0}
    fixed_expected = beta[0] + beta[1] * 2.0 + beta[2] * 3.5 - beta[3]
    assert_prediction(fixed_payload, fixed_expected)
    assert_ci(ci)

    pids = listener_pids()
    assert pids, "No process is listening on port 8000"
    pid = sorted(pids)[0]
    argv, cwd, env = process_launch_info(pid)

    backups = {path: path.read_bytes() for path in (FEATURES, TARGETS, SPECS)}
    restarted = None
    log = open("/tmp/restarted_api.log", "wb")
    try:
        feature_rows, target_rows = write_dynamic_fixture()
        stop_listeners()
        restarted = subprocess.Popen(
            argv,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        wait_for_server(restarted)

        dynamic_beta, dynamic_ci = expected_model(feature_rows, target_rows, 0.10)
        points = [
            {"x1": -4.25, "x2": 0.75, "x3": 2.5},
            {"x1": 0.0, "x2": 0.0, "x3": 0.0},
            {"x1": 1.125, "x2": -3.75, "x3": -1.5},
            {"x1": 6.4, "x2": 2.2, "x3": 0.35},
            {"x1": -0.9, "x2": 5.6, "x3": -3.3},
            {"x1": 2.75, "x2": -1.25, "x3": 4.4},
        ]
        for point in points:
            expected = (
                dynamic_beta[0]
                + dynamic_beta[1] * point["x1"]
                + dynamic_beta[2] * point["x2"]
                + dynamic_beta[3] * point["x3"]
            )
            assert_prediction(point, expected)
        assert_ci(dynamic_ci)
    finally:
        if restarted is not None and restarted.poll() is None:
            try:
                os.killpg(restarted.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                restarted.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(restarted.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        log.close()
        for path, content in backups.items():
            path.write_bytes(content)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_api.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
