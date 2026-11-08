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
import re
import signal
import subprocess
import time
import secrets

import cv2
import numpy as np
from scipy.integrate import solve_ivp
import requests
import pytest

SERVER_PATH = '/home/user/server.sh'
VIDEO_PATH = '/app/experiment.mp4'


def compute_expected_value(frame_idx: int, rtol: float) -> str:
    """Computes the expected golden value for a given frame and rtol."""
    assert os.path.exists(VIDEO_PATH), f"Video file {VIDEO_PATH} does not exist"

    cap = cv2.VideoCapture(VIDEO_PATH)
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
    ret, frame = cap.read()
    cap.release()

    assert ret, f"Could not read frame {frame_idx} from video"

    # Convert to grayscale
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    # Crop central 50%
    h, w = gray.shape
    crop = gray[h//4 : 3*h//4, w//4 : 3*w//4]

    # Mean intensity
    V = np.mean(crop)

    # ODE
    def ode(t, x):
        return -0.05 * x + 10 * np.exp(-t)

    res = solve_ivp(ode, [0, 5.0], [V], rtol=rtol, atol=1e-6)
    final_val = res.y[0][-1]

    return f"{final_val:.4f}"


def listener_pids(port: int):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10:
                        local = fields[1]
                        state = fields[3]
                        if state == '0A' and int(local.rsplit(':', 1)[1], 16) == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    if not inodes:
        return pids
    for name in os.listdir('/proc'):
        if not name.isdigit() or name == '1':
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def stop_existing_listener(port: int):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in pids:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.3)


@pytest.fixture(scope='session', autouse=True)
def launch_submitted_server():
    assert os.path.isfile(SERVER_PATH), f"Required Bash server {SERVER_PATH} does not exist"
    with open(SERVER_PATH, 'r', errors='replace') as f:
        first_line = f.readline().strip()
    assert re.match(r'^#!\s*(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)(?:\s|$)', first_line), \
        f"{SERVER_PATH} must be a Bash script with a Bash shebang"

    syntax = subprocess.run(
        ['bash', '-n', SERVER_PATH], capture_output=True, text=True, timeout=5
    )
    assert syntax.returncode == 0, f"Invalid Bash syntax in {SERVER_PATH}: {syntax.stderr}"

    # Do not trust a pre-existing process: restart the service from the artifact
    # the instruction required so a separate fake listener cannot satisfy tests.
    stop_existing_listener(8080)
    proc = subprocess.Popen(
        ['bash', SERVER_PATH],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(1.0)
    yield
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass


def request_feature(frame_idx, rtol_text):
    url = f"http://127.0.0.1:8080/feature?frame={frame_idx}&rtol={rtol_text}"
    deadline = time.time() + 5
    last_error = None
    while time.time() < deadline:
        try:
            return requests.get(url, timeout=2)
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.15)
    pytest.fail(f"Failed to connect to the server: {last_error}")


def test_endpoint_frame_5():
    """Test the endpoint with frame=5 and rtol=1e-4."""
    frame_idx = 5
    rtol = 1e-4
    expected_body = compute_expected_value(frame_idx, rtol)

    response = request_feature(frame_idx, '0.0001')
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    actual_body = response.text.strip()
    assert actual_body == expected_body, f"Expected response body '{expected_body}', got '{actual_body}'"


def test_endpoint_frame_15():
    """Test the endpoint with frame=15 and rtol=1e-2."""
    frame_idx = 15
    rtol = 1e-2
    expected_body = compute_expected_value(frame_idx, rtol)

    response = request_feature(frame_idx, '0.01')
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    actual_body = response.text.strip()
    assert actual_body == expected_body, f"Expected response body '{expected_body}', got '{actual_body}'"


def test_randomized_frames_and_tolerances():
    cap = cv2.VideoCapture(VIDEO_PATH)
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.release()
    assert frame_count > 0, "Test video contains no frames"

    rng = secrets.SystemRandom()
    candidates = [i for i in range(frame_count) if i not in (5, 15)]
    selected = rng.sample(candidates, min(8, len(candidates)))
    assert selected, "No additional video frames available for generalized testing"

    # Generate fresh decimal tolerances over several magnitudes so responses
    # cannot be hardcoded for a fixed list of query strings.
    exponents = [-6, -5, -4, -3, -2]
    for index, frame_idx in enumerate(selected):
        exponent = exponents[index % len(exponents)]
        mantissa = rng.randint(1, 9) + rng.randint(0, 999) / 1000.0
        rtol = mantissa * (10 ** exponent)
        rtol_text = f"{rtol:.8f}"
        expected_body = compute_expected_value(frame_idx, float(rtol_text))

        response = request_feature(frame_idx, rtol_text)
        assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
        actual_body = response.text.strip()
        assert actual_body == expected_body, \
            f"For frame={frame_idx}, rtol={rtol_text}, expected '{expected_body}', got '{actual_body}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
