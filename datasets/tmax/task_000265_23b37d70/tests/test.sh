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
import os
import random
import re
from pathlib import Path

import cv2
import numpy as np
import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer perf-token-2024"}
SEARCH_ROOTS = [Path("/app"), Path("/home/user"), Path("/root"), Path("/tmp")]


def expected_model_from_video():
    cap = cv2.VideoCapture("/app/trajectory.mp4")
    points = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        y, x = np.unravel_index(np.argmax(gray), gray.shape)
        points.append((int(x), int(y)))
    cap.release()
    assert len(points) == 20, f"Expected 20 video frames, decoded {len(points)}"
    xs = np.array([p[0] for p in points], dtype=float)
    ys = np.array([p[1] for p in points], dtype=float)
    return np.polyfit(xs, ys, 2)


MODEL = expected_model_from_video()
rng = random.SystemRandom()
RANDOM_XS = rng.sample([x for x in range(-40, 81) if x not in (25, 30)], 10)


def expected_y(x):
    value = MODEL[0] * x * x + MODEL[1] * x + MODEL[2]
    return int(np.floor(value + 0.5))


def source_and_executable_artifacts():
    sources = []
    executables = []
    seen = set()
    for root in SEARCH_ROOTS:
        if not root.exists():
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if d not in {".cache", ".git", "__pycache__"}]
            for name in files:
                path = Path(directory) / name
                try:
                    resolved = str(path.resolve())
                    if resolved in seen or path.stat().st_size > 5_000_000:
                        continue
                    seen.add(resolved)
                    if path.suffix.lower() == ".c":
                        sources.append(path)
                    if os.access(path, os.X_OK):
                        with path.open("rb") as f:
                            if f.read(4) == b"\x7fELF":
                                executables.append(path.resolve())
                except (OSError, PermissionError):
                    pass
    return sources, executables


def listener_process():
    socket_inodes = set()
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            if len(fields) >= 10 and fields[1] == "0100007F:1F90" and fields[3] == "0A":
                socket_inodes.add(fields[9])
    assert socket_inodes, "No service is listening exactly on 127.0.0.1:8080"

    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = Path("/proc") / pid / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    return int(pid), Path(os.readlink(Path("/proc") / pid / "exe")).resolve()
        except (OSError, PermissionError):
            continue
    pytest.fail("Could not identify the process owning 127.0.0.1:8080")


def test_c_mcmc_artifact_and_running_service():
    sources, executables = source_and_executable_artifacts()
    assert sources, "No C source file was found"
    assert executables, "No compiled executable artifact was found"

    combined = "\n".join(
        p.read_text(errors="ignore") for p in sources if p.stat().st_size <= 2_000_000
    )
    lowered = combined.lower()
    numeric_literals = [int(v) for v in re.findall(r"(?<![\w.])(\d+)(?:[uUlL]+)?", combined)]
    assert numeric_literals and max(numeric_literals) >= 100000, \
        "C source does not contain evidence of a run of at least 100,000 iterations"
    assert re.search(r"\b(for|while)\s*\(", combined), "C source has no sampling loop"
    assert re.search(r"metropolis|accept", lowered), "C source lacks Metropolis-Hastings acceptance logic"
    assert re.search(r"rand|random|uniform|rng|xorshift", lowered), "C sampler lacks a random proposal/acceptance generator"
    assert re.search(r"\bexp\s*\(|\blog\s*\(", lowered), "C sampler lacks likelihood/acceptance probability computation"
    assert re.search(r"burn|warm|0\.1|/\s*10|10000", lowered), "C source lacks evidence of the required 10% burn-in"
    assert re.search(r"mean|average|sum", lowered), "C source lacks posterior-mean accumulation"

    _, listener_exe = listener_process()
    executable_set = {str(p) for p in executables}
    if listener_exe.name != "socat":
        assert str(listener_exe) in executable_set, \
            f"Listener is not the submitted compiled executable or socat: {listener_exe}"
    else:
        assert any(str(p).startswith(("/app/", "/home/user/", "/root/", "/tmp/")) for p in executables), \
            "socat is listening, but no submitted compiled C executable was found"


def test_unauthorized_request():
    try:
        response = requests.get(f"{BASE_URL}/predict?x=10", timeout=2)
        assert response.status_code != 200, \
            f"Expected non-200 status code for unauthorized request, got {response.status_code}"
    except requests.exceptions.ConnectionError:
        pass


def test_authorized_request_x25():
    try:
        response = requests.get(f"{BASE_URL}/predict?x=25", headers=AUTH_HEADER, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the service at 127.0.0.1:8080")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    body = response.text.strip()
    assert body == "1180", f"Expected prediction '1180' for x=25, got '{body}'"


def test_authorized_request_x30():
    try:
        response = requests.get(f"{BASE_URL}/predict?x=30", headers=AUTH_HEADER, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the service at 127.0.0.1:8080")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    body = response.text.strip()
    assert body == "1715", f"Expected prediction '1715' for x=30, got '{body}'"


@pytest.mark.parametrize("x", RANDOM_XS)
def test_randomized_authorized_predictions(x):
    try:
        response = requests.get(f"{BASE_URL}/predict?x={x}", headers=AUTH_HEADER, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the service at 127.0.0.1:8080")
    assert response.status_code == 200, f"Expected 200 OK for x={x}, got {response.status_code}"
    body = response.text.strip()
    assert re.fullmatch(r"-?\d+", body), f"Prediction for x={x} is not an integer: {body!r}"
    assert int(body) == expected_y(x), \
        f"Incorrect prediction for randomized x={x}: expected {expected_y(x)}, got {body}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
