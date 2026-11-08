#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import secrets

import cv2
import numpy as np
import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
FPS = 30.0


def extract_signal():
    cap = cv2.VideoCapture("/app/vibration.mp4")
    assert cap.isOpened(), "Could not open vibration.mp4"
    values = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        ys, xs = np.nonzero(gray > 200)
        assert len(xs) > 0, "A frame contained no pixels above threshold 200"
        values.append(float(np.mean(xs)))
    cap.release()
    assert len(values) >= 30
    return np.asarray(values, dtype=float)


def ssa_reconstruct(signal, centered=False):
    mean = float(np.mean(signal)) if centered else 0.0
    work = signal - mean
    length = 30
    columns = len(work) - length + 1
    trajectory = np.column_stack([work[i:i + length] for i in range(columns)])
    u, singular, vt = np.linalg.svd(trajectory, full_matrices=False)
    reconstructed_matrix = (u[:, :2] * singular[:2]) @ vt[:2, :]

    reconstructed = np.zeros(len(work), dtype=float)
    counts = np.zeros(len(work), dtype=float)
    for row in range(length):
        reconstructed[row:row + columns] += reconstructed_matrix[row, :]
        counts[row:row + columns] += 1.0
    return reconstructed / counts + mean


def dominant_frequency(signal):
    magnitudes = np.abs(np.fft.rfft(signal))
    frequencies = np.fft.rfftfreq(len(signal), d=1.0 / FPS)
    return float(frequencies[1 + np.argmax(magnitudes[1:])])


def bootstrap_ci(signal, seed):
    rng = np.random.default_rng(seed)
    n = len(signal)
    block_size = 15
    block_count = int(math.ceil(n / block_size))
    results = np.empty(500, dtype=float)
    for iteration in range(500):
        starts = rng.integers(0, n - block_size + 1, size=block_count)
        sample = np.concatenate([signal[s:s + block_size] for s in starts])[:n]
        results[iteration] = dominant_frequency(sample)
    lower, upper = np.percentile(results, [2.5, 97.5])
    return float(lower), float(upper)


X = extract_signal()
REFERENCE = np.loadtxt("/app/reference_signal.csv", delimiter=",").reshape(-1)
FILTERED_CANDIDATES = [ssa_reconstruct(X, centered=False), ssa_reconstruct(X, centered=True)]
EXPECTED_FREQUENCIES = [dominant_frequency(candidate) for candidate in FILTERED_CANDIDATES]
EXPECTED_MSES = [float(np.mean((candidate[:min(len(candidate), len(REFERENCE))] - REFERENCE[:min(len(candidate), len(REFERENCE))]) ** 2)) for candidate in FILTERED_CANDIDATES]
EXPECTED_CIS = [bootstrap_ci(candidate, 882) for candidate in FILTERED_CANDIDATES]
EXPECTED_VELOCITY = np.gradient(X, 1.0 / FPS, edge_order=2)


def get(path, **kwargs):
    try:
        return requests.get(BASE_URL + path, timeout=5, **kwargs)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {BASE_URL + path}: {exc}")


def finite_number(value, name):
    assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{name} must be a number"
    assert math.isfinite(float(value)), f"{name} must be finite"
    return float(value)


def test_api_frequency_and_bootstrap():
    response = get("/api/frequency")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    data = response.json()
    assert "frequency" in data, "Response missing 'frequency' key"
    assert "ci_lower" in data, "Response missing 'ci_lower' key"
    assert "ci_upper" in data, "Response missing 'ci_upper' key"

    frequency = finite_number(data["frequency"], "Frequency")
    lower = finite_number(data["ci_lower"], "ci_lower")
    upper = finite_number(data["ci_upper"], "ci_upper")

    # Preserve the original assertions while also comparing with values derived
    # directly from the supplied video.
    assert 3.0 <= frequency <= 4.0, f"Expected frequency around 3.5 Hz, got {frequency}"
    assert lower <= upper, "ci_lower must be <= ci_upper"
    assert any(abs(frequency - expected) <= 0.051 for expected in EXPECTED_FREQUENCIES), (
        f"Frequency {frequency} does not match the FFT of the extracted and SSA-filtered signal"
    )
    assert upper - lower >= 0.09, "Bootstrap confidence interval is implausibly degenerate"
    assert any(abs(lower - expected_lower) <= 0.5 and abs(upper - expected_upper) <= 0.5
               for expected_lower, expected_upper in EXPECTED_CIS), (
        f"CI [{lower}, {upper}] is inconsistent with a 500-iteration moving-block bootstrap"
    )


def test_api_velocity_for_multiple_unpredictable_frames():
    # Frame 10 preserves the original check; unpredictable additional frames
    # prevent a fixed-value endpoint from passing.
    indices = {10}
    while len(indices) < 9:
        indices.add(1 + secrets.randbelow(len(X) - 2))

    for frame_idx in sorted(indices):
        response = get(f"/api/velocity?frame={frame_idx}")
        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
        data = response.json()
        assert "velocity" in data, "Response missing 'velocity' key"
        velocity = finite_number(data["velocity"], "Velocity")
        expected = float(EXPECTED_VELOCITY[frame_idx])
        assert math.isclose(velocity, expected, rel_tol=1e-4, abs_tol=0.15), (
            f"Velocity at frame {frame_idx} was {velocity}; expected {expected} from the extracted signal"
        )


def test_api_reference_diff_unauthorized():
    response = get("/api/reference_diff")
    assert response.status_code == 401, f"Expected status code 401 for missing token, got {response.status_code}"
    response = get("/api/reference_diff", headers={"Authorization": "Bearer wrong-token"})
    assert response.status_code == 401, f"Expected status code 401 for invalid token, got {response.status_code}"


def test_api_reference_diff_authorized():
    response = get("/api/reference_diff", headers={"Authorization": "Bearer data-sci-token-882"})
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    data = response.json()
    assert "mse" in data, "Response missing 'mse' key"
    mse = finite_number(data["mse"], "MSE")
    assert mse >= 0, "MSE cannot be negative"
    assert any(math.isclose(mse, expected, rel_tol=0.03, abs_tol=0.1) for expected in EXPECTED_MSES), (
        f"MSE {mse} does not match the supplied reference signal and SSA reconstruction"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
