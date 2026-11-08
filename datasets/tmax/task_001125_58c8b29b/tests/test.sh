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
import os
import random
import shutil
import signal
import subprocess
import time

import cv2
import numpy as np
import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
HEADERS = {"Authorization": "Bearer ml-data-token-992"}


def test_unauthorized_access():
    try:
        response = requests.get(f"{BASE_URL}/api/v1/graph-distance", timeout=5)
        assert response.status_code in [401, 403], f"Expected 401 or 403 for unauthorized access, got {response.status_code}"
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running on 127.0.0.1:9090")


def test_graph_distance():
    try:
        response = requests.get(f"{BASE_URL}/api/v1/graph-distance", headers=HEADERS, timeout=5)
        assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
        data = response.json()
        assert "distance" in data, "Key 'distance' not found in response"
        assert data["distance"] == 2, f"Expected distance 2, got {data['distance']}"
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running on 127.0.0.1:9090")


def test_frequencies():
    try:
        response = requests.get(f"{BASE_URL}/api/v1/frequencies", headers=HEADERS, timeout=5)
        assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
        data = response.json()
        for key in ["A", "B", "C"]:
            assert key in data, f"Key '{key}' not found in response"
        assert abs(data["A"] - 2.0) < 0.1, f"Expected frequency A ~ 2.0, got {data['A']}"
        assert abs(data["B"] - 3.0) < 0.1, f"Expected frequency B ~ 3.0, got {data['B']}"
        assert abs(data["C"] - 1.0) < 0.1, f"Expected frequency C ~ 1.0, got {data['C']}"
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running on 127.0.0.1:9090")


def test_parameter():
    try:
        response = requests.get(f"{BASE_URL}/api/v1/parameter", headers=HEADERS, timeout=5)
        assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
        data = response.json()
        assert "theta" in data, "Key 'theta' not found in response"
        assert 0.95 <= data["theta"] <= 1.05, f"Expected theta between 0.95 and 1.05, got {data['theta']}"
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running on 127.0.0.1:9090")


def listener_pid():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == 9090 and state == "0A":
                        socket_inodes.add(fields[9])
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
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    return int(entry)
        except (FileNotFoundError, PermissionError):
            continue
    raise AssertionError("Could not identify the service listening on port 9090")


def capture_and_restart_service():
    pid = listener_pid()
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode() for part in f.read().split(b"\0") if part]
    assert argv, "Service has an empty command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    exe = os.readlink(f"/proc/{pid}/exe")
    if exe.endswith(" (deleted)") or not os.path.exists(exe):
        copied_exe = "/tmp/submitted-service-executable"
        shutil.copyfile(f"/proc/{pid}/exe", copied_exe)
        os.chmod(copied_exe, 0o755)
        exe = copied_exe

    env = os.environ.copy()
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            for item in f.read().split(b"\0"):
                if b"=" in item:
                    key, value = item.split(b"=", 1)
                    env[key.decode(errors="ignore")] = value.decode(errors="ignore")
    except OSError:
        pass

    os.kill(pid, signal.SIGTERM)
    for _ in range(30):
        if not os.path.exists(f"/proc/{pid}"):
            break
        time.sleep(0.1)
    if os.path.exists(f"/proc/{pid}"):
        os.kill(pid, signal.SIGKILL)

    subprocess.Popen(
        argv,
        executable=exe,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 20
    while time.time() < deadline:
        try:
            response = requests.get(f"{BASE_URL}/api/v1/graph-distance", headers=HEADERS, timeout=1)
            if response.status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(0.25)
    pytest.fail("Submitted service did not restart after the input fixtures changed")


def test_pipeline_on_unseen_fixture():
    rng = random.SystemRandom()
    variants = [
        ({"A": ["C", "D"], "B": ["C", "E"], "C": ["A", "B", "D"], "D": ["A", "C"], "E": ["B"]}, 1),
        ({"A": ["B", "D"], "B": ["A"], "C": ["E"], "D": ["A", "E"], "E": ["D", "C"]}, 3),
    ]
    graph, expected_distance = rng.choice(variants)
    degrees = {node: len(neighbors) for node, neighbors in graph.items()}

    base_theta = rng.choice([0.6, 1.4])
    offsets = [rng.choice([-0.2, -0.1, 0.1, 0.2]) for _ in range(3)]
    frequencies = {
        node: round(base_theta * degrees[node] + offset, 1)
        for node, offset in zip(["A", "B", "C"], offsets)
    }

    with open("/app/graph.json", "w") as f:
        json.dump(graph, f)

    fps = 30
    frames = 300
    boxes = {"A": (50, 50, 20, 20), "B": (150, 50, 20, 20), "C": (100, 150, 20, 20)}
    temp_video = "/app/experiment-randomized.mp4"
    writer = cv2.VideoWriter(temp_video, cv2.VideoWriter_fourcc(*"mp4v"), fps, (300, 300), isColor=False)
    assert writer.isOpened(), "Could not create randomized verification video"
    for i in range(frames):
        t = i / fps
        image = np.zeros((300, 300), dtype=np.uint8)
        for node, (x, y, width, height) in boxes.items():
            intensity = int(102.5 * np.sin(2 * np.pi * frequencies[node] * t) + 152.5)
            image[y:y + height, x:x + width] = intensity
        writer.write(image)
    writer.release()
    os.replace(temp_video, "/app/experiment.mp4")

    capture_and_restart_service()

    unauthorized = requests.get(f"{BASE_URL}/api/v1/frequencies", timeout=5)
    assert unauthorized.status_code in [401, 403]

    distance_response = requests.get(f"{BASE_URL}/api/v1/graph-distance", headers=HEADERS, timeout=5)
    assert distance_response.status_code == 200
    assert distance_response.json()["distance"] == expected_distance

    frequency_response = requests.get(f"{BASE_URL}/api/v1/frequencies", headers=HEADERS, timeout=5)
    assert frequency_response.status_code == 200
    measured = frequency_response.json()
    for node in ["A", "B", "C"]:
        assert node in measured
        assert abs(float(measured[node]) - frequencies[node]) < 0.11, (
            f"Expected randomized frequency {node} ~ {frequencies[node]}, got {measured[node]}"
        )

    numerator = sum(degrees[node] * frequencies[node] for node in ["A", "B", "C"])
    denominator = sum(degrees[node] ** 2 for node in ["A", "B", "C"])
    expected_theta = numerator / denominator

    parameter_response = requests.get(f"{BASE_URL}/api/v1/parameter", headers=HEADERS, timeout=5)
    assert parameter_response.status_code == 200
    parameter_data = parameter_response.json()
    assert "theta" in parameter_data
    assert abs(float(parameter_data["theta"]) - expected_theta) < 0.18, (
        f"Expected posterior mean near {expected_theta:.2f}, got {parameter_data['theta']}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
