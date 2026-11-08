#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import shutil
import subprocess
import time

import cv2
import numpy as np
import pytest

BINARY = "/home/user/pipeline/analyzer"
RESULTS = "/home/user/results.json"
VIDEO = "/app/simulation.mp4"


def run_analyzer():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)

    start = time.monotonic()
    try:
        proc = subprocess.run(
            [BINARY], capture_output=True, text=True, timeout=5.0
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Analyzer exceeded the 5.0s runtime threshold")
    duration = time.monotonic() - start

    assert proc.returncode == 0, f"Analyzer failed to run. Stderr: {proc.stderr}"
    assert duration < 5.0, f"Runtime {duration:.2f}s exceeded 5.0s threshold."
    assert os.path.isfile(RESULTS), f"Results file not generated at {RESULTS}"

    try:
        with open(RESULTS, "r") as f:
            data = json.load(f)
    except Exception as exc:
        pytest.fail(f"Could not read or parse {RESULTS}: {exc}")

    required = {
        "max_effective_resistance",
        "kl_divergence_0_vs_299",
        "runtime_seconds",
    }
    assert required.issubset(data), f"Missing output keys: {required - set(data)}"
    for key in required:
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f"{key} must be numeric"
        assert math.isfinite(float(value)), f"{key} must be finite"
    assert 0 <= float(data["runtime_seconds"]) < 5.0, \
        "Reported runtime_seconds must be in the required range"
    return data


def pairwise_distances(points):
    points = np.asarray(points, dtype=np.float64)
    delta = points[:, None, :] - points[None, :, :]
    distances = np.sqrt(np.sum(delta * delta, axis=2))
    return distances[np.triu_indices(len(points), 1)]


def expected_kl(frame0, frame299):
    h0, _ = np.histogram(pairwise_distances(frame0), bins=20, range=(0.0, 200.0))
    h1, _ = np.histogram(pairwise_distances(frame299), bins=20, range=(0.0, 200.0))
    p = h0.astype(np.float64) / h0.sum()
    q = h1.astype(np.float64) / h1.sum()
    p[p == 0] = 1e-9
    q[q == 0] = 1e-9
    p /= p.sum()
    q /= q.sum()
    return float(np.sum(p * np.log(p / q)))


def average_effective_resistance(points):
    points = np.asarray(points, dtype=np.float64)
    delta = points[:, None, :] - points[None, :, :]
    distance = np.sqrt(np.sum(delta * delta, axis=2))
    adjacency = ((distance < 30.0) & (distance > 0.0)).astype(np.float64)
    laplacian = np.diag(adjacency.sum(axis=1)) - adjacency
    eigenvalues = np.linalg.eigvalsh(laplacian)
    positive = eigenvalues[eigenvalues > 1e-9]
    assert len(positive) == len(points) - 1, "Verifier probe graph is not connected"
    # The mean of R_ij over all unordered node pairs is 2*trace(L^+)/ (n-1).
    return float(2.0 * np.sum(1.0 / positive) / (len(points) - 1))


def make_probe_video(path):
    # A fresh, unpredictable valid 50-node video prevents a constant-output
    # program from passing. Spacing is selected away from the 30-pixel edge
    # threshold so codec/centroid rounding cannot alter the expected graph.
    spacing0 = secrets.choice([20, 23, 25])
    spacing1 = secrets.choice([15, 16, 17, 18])
    xoff = secrets.randbelow(8)
    yoff = secrets.randbelow(8)

    frame0 = []
    frame299 = []
    for i in range(50):
        row, col = divmod(i, 8)
        frame0.append((35 + col * spacing0, 35 + row * spacing0))
        frame299.append((45 + xoff + col * spacing1, 55 + yoff + row * spacing1))

    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), 30, (400, 400))
    assert writer.isOpened(), "Could not create verifier probe video"
    for frame_index in range(300):
        points = frame0 if frame_index < 299 else frame299
        image = np.full((400, 400, 3), 255, dtype=np.uint8)
        for x, y in points:
            cv2.circle(image, (int(x), int(y)), 5, (0, 0, 0), -1)
        writer.write(image)
    writer.release()

    expected_max = max(
        average_effective_resistance(frame0),
        average_effective_resistance(frame299),
    )
    return expected_max, expected_kl(frame0, frame299)


def test_analyzer_binary_exists():
    assert os.path.isfile(BINARY), f"Compiled binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "analyzer must be a compiled ELF binary"


def test_analyzer_execution_and_metrics():
    # Preserve all original checks against the supplied simulation.
    original = run_analyzer()
    original_kl = float(original["kl_divergence_0_vs_299"])
    error = abs(original_kl - 0.4125)
    assert error <= 0.05, \
        f"KL error {error:.4f} > 0.05 threshold (agent: {original_kl}, truth: 0.4125)"
    assert float(original["max_effective_resistance"]) > 0.0, \
        "max_effective_resistance must be a positive computed metric"

    backup = "/tmp/original_simulation.mp4"
    probe = "/tmp/verifier_probe.mp4"
    shutil.copy2(VIDEO, backup)
    try:
        expected_resistance, expected_probe_kl = make_probe_video(probe)
        shutil.copy2(probe, VIDEO)
        probe_result = run_analyzer()

        actual_resistance = float(probe_result["max_effective_resistance"])
        resistance_tolerance = max(0.02, abs(expected_resistance) * 0.04)
        assert abs(actual_resistance - expected_resistance) <= resistance_tolerance, (
            "Incorrect maximum average effective resistance on verifier probe: "
            f"got {actual_resistance}, expected {expected_resistance} "
            f"(tolerance {resistance_tolerance})"
        )

        actual_kl = float(probe_result["kl_divergence_0_vs_299"])
        assert abs(actual_kl - expected_probe_kl) <= 0.05, (
            "Incorrect KL divergence on verifier probe: "
            f"got {actual_kl}, expected {expected_probe_kl}"
        )
    finally:
        shutil.copy2(backup, VIDEO)
        for path in (backup, probe):
            if os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
