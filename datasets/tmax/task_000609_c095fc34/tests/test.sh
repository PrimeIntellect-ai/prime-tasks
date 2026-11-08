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
import glob
import json
import math
import os
import random
import shutil
import signal
import statistics
import subprocess
import time

import cv2
import numpy as np
import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer RES-8821"}
VIDEO = "/app/experiment.mp4"


def request(path, auth=True, timeout=5):
    headers = AUTH_HEADER if auth else None
    try:
        return requests.get(BASE_URL + path, headers=headers, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server: {exc}")


def test_health_no_auth():
    response = request("/health", auth=False)
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized, got {response.status_code}. Response: {response.text}"


def test_health_with_auth():
    response = request("/health")
    assert response.status_code == 200, \
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"


def test_optimal_k():
    response = request("/optimal_k")
    assert response.status_code == 200, \
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "k" in data, f"Expected key 'k' in response, got {data}"
    assert data["k"] == 2, f"Expected optimal k to be 2, got {data['k']}"


def test_predict():
    response = request("/predict")
    assert response.status_code == 200, \
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "prediction" in data, f"Expected key 'prediction' in response, got {data}"
    prediction = float(data["prediction"])
    assert abs(prediction - 127.0) < 1e-5, \
        f"Expected prediction to be 127.0, got {prediction}"


def test_all_endpoints_require_authentication():
    for path in ("/optimal_k", "/predict"):
        response = request(path, auth=False)
        assert response.status_code == 401, \
            f"Expected 401 Unauthorized from {path}, got {response.status_code}"
        response = requests.get(
            BASE_URL + path,
            headers={"Authorization": "Bearer wrong-token"},
            timeout=5,
        )
        assert response.status_code == 401, \
            f"Expected 401 Unauthorized from {path} with an invalid token, got {response.status_code}"


def listener_pid(port=8080):
    wanted = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as fh:
                next(fh)
                for line in fh:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    for proc_dir in glob.glob("/proc/[0-9]*"):
        fd_dir = os.path.join(proc_dir, "fd")
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(os.path.basename(proc_dir))
        except (FileNotFoundError, PermissionError):
            continue
    return None


def wait_for_server(timeout=20):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(BASE_URL + "/health", headers=AUTH_HEADER, timeout=1)
            if response.status_code == 200 and response.json().get("status") == "ok":
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    pytest.fail(f"Restarted submission did not become healthy: {last_error}")


def stop_process(proc):
    if proc is None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=3)
    except Exception:
        try:
            proc.kill()
            proc.wait(timeout=3)
        except Exception:
            pass


def clean_and_analyze(raw):
    assert len(raw) == 40
    cleaned = [None] * 40
    for i, value in enumerate(raw):
        if value > 200:
            assert i >= 5 and all(v is not None for v in cleaned[i-5:i])
            cleaned[i] = float(statistics.median(cleaned[i-5:i]))
        elif value == 0:
            prev_i = i - 1
            while prev_i >= 0 and (raw[prev_i] == 0 or raw[prev_i] > 200):
                prev_i -= 1
            next_i = i + 1
            while next_i < 40 and (raw[next_i] == 0 or raw[next_i] > 200):
                next_i += 1
            assert prev_i >= 0 and next_i < 40 and cleaned[prev_i] is not None
            left = cleaned[prev_i]
            right = float(raw[next_i])
            cleaned[i] = left + (right - left) * ((i - prev_i) / (next_i - prev_i))
        else:
            cleaned[i] = float(value)

    average_mses = {}
    for k in (2, 3, 4, 5, 6):
        split_mses = []
        for start in (10, 20, 30):
            errors = []
            for i in range(start, start + 10):
                prediction = sum(cleaned[i-k:i]) / k
                errors.append((prediction - cleaned[i]) ** 2)
            split_mses.append(sum(errors) / len(errors))
        average_mses[k] = sum(split_mses) / 3.0
    optimal_k = min((2, 3, 4, 5, 6), key=lambda k: average_mses[k])
    prediction = sum(cleaned[-optimal_k:]) / optimal_k
    return optimal_k, prediction


def decoded_brightness(path):
    capture = cv2.VideoCapture(path)
    values = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        values.append(float(np.mean(gray)))
    capture.release()
    assert len(values) == 40, f"Generated test video decoded to {len(values)} frames"
    return values


def make_hidden_video(seed, forbidden_k=None):
    rng = random.Random(seed)
    for attempt in range(100):
        values = [rng.randint(25, 185) for _ in range(40)]
        values[9] = 0
        values[18] = 245
        values[31] = 0

        writer = cv2.VideoWriter(
            VIDEO,
            cv2.VideoWriter_fourcc(*"mp4v"),
            10.0,
            (100, 100),
            isColor=False,
        )
        assert writer.isOpened(), "Could not create hidden test video"
        for value in values:
            writer.write(np.full((100, 100), value, dtype=np.uint8))
        writer.release()

        decoded = decoded_brightness(VIDEO)
        k, prediction = clean_and_analyze(decoded)
        if k != 2 and (forbidden_k is None or k != forbidden_k):
            return k, prediction
    pytest.fail("Could not generate a suitable hidden video instance")


def find_go_source():
    found = []
    for root in ("/app", "/home/user", "/tmp"):
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if not d.startswith("go-build") and d != ".cache"]
            for name in files:
                if not name.endswith(".go"):
                    continue
                path = os.path.join(directory, name)
                try:
                    with open(path, errors="ignore") as fh:
                        text = fh.read()
                    if "package main" in text:
                        found.append(path)
                except OSError:
                    pass
    return found


def test_go_pipeline_recomputes_results_for_hidden_videos():
    sources = find_go_source()
    assert sources, "No Go service source code was found under /app, /home/user, or /tmp"

    pid = listener_pid()
    assert pid is not None, "No process is listening on port 8080"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    with open(f"/proc/{pid}/cmdline", "rb") as fh:
        cmdline = [part.decode(errors="surrogateescape") for part in fh.read().split(b"\0") if part]

    go_info = subprocess.run(
        ["go", "version", "-m", f"/proc/{pid}/exe"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert go_info.returncode == 0 and "go1" in go_info.stdout, \
        f"The process serving port 8080 is not a compiled Go program: {go_info.stdout}"

    executable = "/tmp/submission-go-server"
    shutil.copyfile(f"/proc/{pid}/exe", executable)
    os.chmod(executable, 0o755)
    args = [executable] + cmdline[1:]

    original_video = "/tmp/original-experiment.mp4"
    shutil.copyfile(VIDEO, original_video)
    running = None
    try:
        os.kill(pid, signal.SIGTERM)
        deadline = time.time() + 5
        while listener_pid() is not None and time.time() < deadline:
            time.sleep(0.1)
        if listener_pid() is not None:
            os.kill(pid, signal.SIGKILL)
            time.sleep(0.5)

        first_k = None
        for seed in (8821, 19427):
            stop_process(running)
            running = None
            expected_k, expected_prediction = make_hidden_video(seed, forbidden_k=first_k)
            if first_k is None:
                first_k = expected_k

            running = subprocess.Popen(
                args,
                cwd=cwd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            wait_for_server()

            response = request("/optimal_k")
            assert response.status_code == 200
            data = response.json()
            assert data.get("k") == expected_k, \
                f"For a hidden video, expected optimal k {expected_k}, got {data}"

            response = request("/predict")
            assert response.status_code == 200
            data = response.json()
            assert "prediction" in data
            actual_prediction = float(data["prediction"])
            assert math.isfinite(actual_prediction)
            assert abs(actual_prediction - expected_prediction) < 1e-5, \
                f"For a hidden video, expected prediction {expected_prediction}, got {actual_prediction}"
    finally:
        stop_process(running)
        shutil.copyfile(original_video, VIDEO)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
