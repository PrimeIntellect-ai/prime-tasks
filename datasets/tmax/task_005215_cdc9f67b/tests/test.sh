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
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import secrets
import subprocess
import time

import cv2
import numpy as np
import pytest
import requests
from scipy.optimize import least_squares

BASE_URL = "http://127.0.0.1:8050"
SOURCE = "/home/user/server.c"
BINARY = "/home/user/server"


def rk4_step(I, r, K, h):
    k1 = r * I * (1 - I / K)
    k2 = r * (I + 0.5 * h * k1) * (1 - (I + 0.5 * h * k1) / K)
    k3 = r * (I + 0.5 * h * k2) * (1 - (I + 0.5 * h * k2) / K)
    k4 = r * (I + h * k3) * (1 - (I + h * k3) / K)
    return I + (h / 6.0) * (k1 + 2 * k2 + 2 * k3 + k4)


def simulate_rk4(r, K, I0, t, h=0.01):
    steps = int(round(t / h))
    I = I0
    for _ in range(steps):
        I = rk4_step(I, r, K, h)
    return I


def extract_and_fit_video():
    cap = cv2.VideoCapture("/app/fluor_seq.mp4")
    assert cap.isOpened(), "Could not open the supplied video"
    means = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) if frame.ndim == 3 else frame
        means.append(float(np.mean(gray)))
    cap.release()
    assert len(means) == 100, f"Expected 100 video frames, found {len(means)}"

    y = np.asarray(means, dtype=float)
    t = np.arange(len(y), dtype=float) / 10.0
    I0 = float(y[0])

    def residual(params):
        r, K = params
        prediction = K / (1.0 + ((K - I0) / I0) * np.exp(-r * t))
        return prediction - y

    result = least_squares(residual, x0=np.array([1.0, 190.0]), bounds=([0.1, 50.0], [5.0, 255.0]),
                           xtol=1e-13, ftol=1e-13, gtol=1e-13, max_nfev=20000)
    assert result.success
    return I0, float(result.x[0]), float(result.x[1])


VIDEO_I0, VIDEO_R, VIDEO_K = extract_and_fit_video()
RANDOM_TIMES = [n / 100.0 for n in secrets.SystemRandom().sample(range(7, 990), 7)]


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submitted_c_server():
    assert os.path.isfile(SOURCE), f"Missing required source file: {SOURCE}"
    assert os.path.isfile(BINARY), f"Missing required compiled server: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Required server is not executable: {BINARY}"

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    lowered = source.lower()

    assert re.search(r"#\s*include\s*[<\"]sys/socket\.h[>\"]", source), "server.c must use POSIX sockets"
    for call in ("socket", "bind", "listen", "accept", "recv"):
        assert re.search(r"\b" + call + r"\s*\(", source), f"server.c does not call {call}()"
    assert "libmicrohttpd" not in lowered, "External HTTP libraries are not allowed"
    assert re.search(r"(?:\b0*\.01(?:0*)?\b|\b1(?:\.0+)?e-0?2\b)", lowered), "No fixed RK4 step h=0.01 found in server.c"
    has_named_stages = all(re.search(r"\bk[1234]\b", lowered) for _ in [0])
    has_rk4_structure = "rk4" in lowered or has_named_stages
    assert has_rk4_structure, "No RK4 implementation is evident in server.c"

    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", BINARY, "-lm"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert compile_result.returncode == 0, f"server.c failed to compile:\n{compile_result.stdout}"

    subprocess.run(["pkill", "-x", "server"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.25)
    log = open("/tmp/submitted_server.log", "w")
    proc = subprocess.Popen([BINARY], stdout=log, stderr=subprocess.STDOUT)

    ready = False
    for _ in range(50):
        if proc.poll() is not None:
            break
        try:
            requests.get(f"{BASE_URL}/fit", timeout=0.2)
            ready = True
            break
        except requests.RequestException:
            time.sleep(0.1)
    assert ready, "Freshly compiled server.c did not start listening on port 8050"

    yield

    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
    log.close()


def assert_http_json_response(response):
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert response.raw.version == 11, "Response is not HTTP/1.1"
    content_type = response.headers.get("Content-Type", "").lower()
    assert content_type.split(";", 1)[0].strip() == "application/json", "Missing Content-Type: application/json"
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")


def get_fit():
    try:
        response = requests.get(f"{BASE_URL}/fit", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /fit endpoint: {e}")
    data = assert_http_json_response(response)
    assert "r" in data, "Missing 'r' in /fit response"
    assert "K" in data, "Missing 'K' in /fit response"
    assert re.search(r'["\']r["\']\s*:\s*-?\d+\.\d{3}(?!\d)', response.text), "r must be rounded to 3 decimal places"
    assert re.search(r'["\']K["\']\s*:\s*-?\d+\.\d{3}(?!\d)', response.text), "K must be rounded to 3 decimal places"
    return float(data["r"]), float(data["K"])


def test_fit_endpoint():
    r_val, K_val = get_fit()

    # Preserve the original acceptance assertions.
    assert abs(r_val - 1.200) <= 0.05, f"Fitted 'r' ({r_val}) is outside acceptable range [1.15, 1.25]"
    assert abs(K_val - 200.000) <= 2.0, f"Fitted 'K' ({K_val}) is outside acceptable range [198.0, 202.0]"

    # Independently derive the expected fit from all frames of the supplied video.
    assert abs(r_val - VIDEO_R) <= 0.05, f"Fitted r={r_val} disagrees with video-derived fit {VIDEO_R}"
    assert abs(K_val - VIDEO_K) <= 2.0, f"Fitted K={K_val} disagrees with video-derived fit {VIDEO_K}"


@pytest.mark.parametrize("t_val", [3.5, 8.2])
def test_original_simulate_points(t_val):
    r_val, K_val = get_fit()
    expected_I = simulate_rk4(r_val, K_val, 15.0, t_val, h=0.01)
    try:
        response = requests.get(f"{BASE_URL}/simulate?t={t_val}", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /simulate?t={t_val}: {e}")
    data = assert_http_json_response(response)
    assert "I" in data, "Missing 'I' in /simulate response"
    I_val = float(data["I"])
    assert abs(I_val - expected_I) <= 0.1, f"Simulated I={I_val} at t={t_val} differs from RK4 result {expected_I}"


@pytest.mark.parametrize("t_val", RANDOM_TIMES)
def test_simulate_at_unpredictable_times(t_val):
    r_val, K_val = get_fit()
    expected_I = simulate_rk4(r_val, K_val, VIDEO_I0, t_val, h=0.01)
    try:
        response = requests.get(f"{BASE_URL}/simulate?t={t_val:.2f}", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /simulate?t={t_val:.2f}: {e}")
    data = assert_http_json_response(response)
    assert "I" in data, "Missing 'I' in /simulate response"
    I_val = float(data["I"])
    assert math.isfinite(I_val), "Simulated intensity is not finite"
    assert abs(I_val - expected_I) <= 0.1, f"Simulated I={I_val} at t={t_val} differs from RK4 result {expected_I}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
