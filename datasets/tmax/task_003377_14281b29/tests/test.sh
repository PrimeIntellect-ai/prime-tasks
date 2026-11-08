#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import tempfile
import pytest
import requests
import numpy as np
import cv2

def compute_expected_nmf(video_path):
    # Extract frames using ffmpeg to match standard ffmpeg extraction
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run([
            "ffmpeg", "-i", video_path,
            os.path.join(tmpdir, "%04d.png")
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        frame_files = sorted([f for f in os.listdir(tmpdir) if f.endswith(".png")])

        rows = []
        for f in frame_files:
            img = cv2.imread(os.path.join(tmpdir, f), cv2.IMREAD_GRAYSCALE)
            rows.append(img[49, :])

    V = np.array(rows, dtype=np.float64) / 255.0
    num_frames, width = V.shape

    W = np.full((num_frames, 2), 0.5, dtype=np.float64)
    H = np.full((2, width), 0.5, dtype=np.float64)

    for _ in range(100):
        H = H * (W.T @ V) / (W.T @ W @ H + 1e-9)
        W = W * (V @ H.T) / (W @ H @ H.T + 1e-9)

    return W, H

def test_health_endpoint():
    try:
        resp = requests.get("http://127.0.0.1:9090/health", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /health endpoint: {e}")

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"
    assert resp.json() == {"status": "ok"}, f"Unexpected health response: {resp.text}"

def test_w_endpoint():
    try:
        resp = requests.get("http://127.0.0.1:9090/W", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /W endpoint: {e}")

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"

    try:
        W_actual = np.array(resp.json(), dtype=np.float64)
    except Exception as e:
        pytest.fail(f"Failed to parse /W response as JSON array: {e}")

    W_expected, _ = compute_expected_nmf("/app/reaction_spectroscopy.mp4")

    assert W_actual.shape == W_expected.shape, f"Expected W shape {W_expected.shape}, got {W_actual.shape}"
    assert np.allclose(W_actual, W_expected, atol=1e-5), "W matrix values do not match expected NMF output"

def test_h_endpoint():
    try:
        resp = requests.get("http://127.0.0.1:9090/H", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /H endpoint: {e}")

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"

    try:
        H_actual = np.array(resp.json(), dtype=np.float64)
    except Exception as e:
        pytest.fail(f"Failed to parse /H response as JSON array: {e}")

    _, H_expected = compute_expected_nmf("/app/reaction_spectroscopy.mp4")

    assert H_actual.shape == H_expected.shape, f"Expected H shape {H_expected.shape}, got {H_actual.shape}"
    assert np.allclose(H_actual, H_expected, atol=1e-5), "H matrix values do not match expected NMF output"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
