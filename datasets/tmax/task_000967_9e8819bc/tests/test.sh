#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import socket
import subprocess
import math
import pytest
import requests

def get_golden_values():
    """
    Computes the expected convergence values by reading the generated video
    and reference distribution. We run this in a subprocess to access numpy,
    scipy, and cv2 which were used in the setup script.
    """
    script = """
import json
import numpy as np
import cv2
from scipy.stats import wasserstein_distance

with open('/app/ref_dist.json', 'r') as f:
    ref_dist = json.load(f)

cap = cv2.VideoCapture('/app/sequencing_droplets.mp4')
histograms = []
while True:
    ret, frame = cap.read()
    if not ret:
        break
    if len(frame.shape) == 3:
        frame = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    hist, _ = np.histogram(frame, bins=256, range=(0, 256))
    hist = hist / np.sum(hist)
    histograms.append(hist)
cap.release()

W = []
for N in range(1, len(histograms) + 1):
    A_N = np.mean(histograms[:N], axis=0)
    w = wasserstein_distance(np.arange(256), np.arange(256), u_weights=A_N, v_weights=ref_dist)
    W.append(w)

converged_N = None
converged_W = None
for i in range(1, len(W)):
    if abs(W[i] - W[i-1]) < 1e-4:
        converged_N = i + 1
        converged_W = W[i]
        break

print(json.dumps({"converged_N": converged_N, "wasserstein_distance": converged_W}))
"""
    result = subprocess.run(["python3", "-c", script], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"Failed to compute golden values: {result.stderr}")
    return json.loads(result.stdout)

@pytest.fixture(scope="module")
def golden_values():
    return get_golden_values()

def test_http_service(golden_values):
    """Test the HTTP API at 127.0.0.1:8080/convergence."""
    try:
        resp = requests.get("http://127.0.0.1:8080/convergence", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP service at 127.0.0.1:8080: {e}")

    assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code}. Response: {resp.text}"

    try:
        data = resp.json()
    except json.JSONDecodeError:
        pytest.fail(f"HTTP response is not valid JSON: {resp.text}")

    assert "converged_N" in data, "Missing 'converged_N' in HTTP response"
    assert "wasserstein_distance" in data, "Missing 'wasserstein_distance' in HTTP response"

    expected_n = golden_values["converged_N"]
    expected_w = golden_values["wasserstein_distance"]

    assert data["converged_N"] == expected_n, \
        f"Expected converged_N={expected_n}, got {data['converged_N']}"

    assert math.isclose(data["wasserstein_distance"], expected_w, abs_tol=1e-5), \
        f"Expected wasserstein_distance near {expected_w:.6f}, got {data['wasserstein_distance']}"

def test_tcp_service(golden_values):
    """Test the raw TCP service at 127.0.0.1:9090."""
    expected_n = golden_values["converged_N"]
    expected_response = f"PONG {expected_n}\n"

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(("127.0.0.1", 9090))
    except Exception as e:
        pytest.fail(f"Failed to connect to TCP service at 127.0.0.1:9090: {e}")

    try:
        s.sendall(b"PING\n")
        response = s.recv(1024).decode("utf-8")
    except Exception as e:
        s.close()
        pytest.fail(f"Failed to communicate with TCP service: {e}")
    finally:
        s.close()

    assert response == expected_response, \
        f"Expected TCP response {repr(expected_response)}, got {repr(response)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
