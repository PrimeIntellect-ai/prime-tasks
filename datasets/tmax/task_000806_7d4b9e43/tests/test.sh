#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import re
import shutil
import subprocess

import cv2
import numpy as np
import pytest

HOME = "/home/user"
VIDEO = "/app/experiment.mp4"
SCRIPT = os.path.join(HOME, "run_pipeline.sh")
SOURCE = os.path.join(HOME, "analyze.go")
RESULTS = os.path.join(HOME, "results.json")
FRAMES = os.path.join(HOME, "frames")


def derive_video_data():
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), "Could not open experiment video"
    points = []
    frame_count = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        ys, xs = np.nonzero(gray < 80)
        if len(xs) >= 20:
            points.append((frame_count / 30.0, float(xs.mean()), float(ys.mean())))
        frame_count += 1
    cap.release()
    assert frame_count > 10 and len(points) > 10, "Could not derive projectile motion from video"

    times = np.array([p[0] for p in points])
    xs = np.array([p[1] for p in points])
    ys = np.array([p[2] for p in points])
    time_fit = np.polyfit(times, ys, 2)[::-1]
    gravity = 2.0 * time_fit[2] / 100.0
    frame_fit = np.polyfit(times * 30.0, ys, 2)[::-1]
    xy_fit = np.polyfit(xs, ys, 2)[::-1]
    return frame_count, gravity, [time_fit, time_fit / 100.0,
                                  frame_fit, frame_fit / 100.0, xy_fit]


@pytest.fixture(scope="module", autouse=True)
def run_submitted_pipeline():
    assert os.path.isfile(SCRIPT) and not os.path.islink(SCRIPT), f"Missing regular file: {SCRIPT}"
    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), f"Missing regular file: {SOURCE}"

    script_text = open(SCRIPT, encoding="utf-8").read()
    source_text = open(SOURCE, encoding="utf-8").read()

    assert re.search(r"\bffmpeg\b", script_text), "run_pipeline.sh must use ffmpeg"
    assert re.search(r"(?:go\s+run|go\s+build).*analyze\.go", script_text), \
        "run_pipeline.sh must execute analyze.go"
    assert "experiment.mp4" in script_text and "frames" in script_text, \
        "run_pipeline.sh must extract the supplied video into the frames directory"

    assert "gonum.org/v1/gonum" in source_text, "analyze.go must use Gonum"
    assert re.search(r"mat\.SVD|\bSVD\b", source_text), "analyze.go must perform SVD"
    assert re.search(r"Factorize\s*\(", source_text), "The SVD must be factorized"
    assert re.search(r"gradient", source_text, re.I), "Missing gradient-descent implementation"
    assert re.search(r"1(?:\.0+)?e-0?6|0\.000001", source_text, re.I), \
        "Missing the required 1e-6 convergence threshold"
    assert re.search(r"math\.Abs|Abs\s*\(", source_text), \
        "Convergence must compare the change in loss"

    shutil.rmtree(FRAMES, ignore_errors=True)
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    try:
        completed = subprocess.run(
            ["bash", SCRIPT], cwd=HOME, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
        )
    except subprocess.TimeoutExpired:
        pytest.fail("run_pipeline.sh timed out")
    assert completed.returncode == 0, "run_pipeline.sh failed:\n" + completed.stdout[-4000:]


def test_frame_extraction():
    expected_count, _, _ = derive_video_data()
    files = sorted(glob.glob(os.path.join(FRAMES, "*.png")))
    assert len(files) == expected_count, \
        f"Expected all {expected_count} video frames, found {len(files)} PNGs"
    for path in files:
        image = cv2.imread(path, cv2.IMREAD_UNCHANGED)
        assert image is not None, f"Unreadable PNG frame: {path}"
        assert image.ndim == 2, f"Frame is not stored as grayscale: {path}"


def test_results_json_exists_and_valid():
    results_path = "/home/user/results.json"
    assert os.path.exists(results_path), f"Missing output file: {results_path}"

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    assert "estimated_gravity" in results, "Missing 'estimated_gravity' in results.json"
    assert "trajectory_coefficients" in results, "Missing 'trajectory_coefficients' in results.json"
    assert "optimization_steps_taken" in results, "Missing 'optimization_steps_taken' in results.json"

    try:
        estimated_gravity = float(results["estimated_gravity"])
    except (ValueError, TypeError):
        pytest.fail(f"'estimated_gravity' must be a number, got: {results['estimated_gravity']}")
    assert math.isfinite(estimated_gravity), "'estimated_gravity' must be finite"

    # Preserve the original gravity assertion.
    true_gravity = 9.81
    error = abs(estimated_gravity - true_gravity) / true_gravity
    assert error <= 0.05, f"Estimated gravity {estimated_gravity} is too far from true value {true_gravity} (Error: {error:.4f}, Threshold: 0.05)"

    # Also derive the expected value from the supplied video rather than trusting JSON.
    _, video_gravity, coefficient_candidates = derive_video_data()
    video_error = abs(estimated_gravity - video_gravity) / abs(video_gravity)
    assert video_error <= 0.05, \
        f"Estimated gravity {estimated_gravity} disagrees with motion measured from the video ({video_gravity:.4f})"

    coefficients = results["trajectory_coefficients"]
    assert isinstance(coefficients, list) and len(coefficients) == 3, \
        "'trajectory_coefficients' must be a three-element array [c0, c1, c2]"
    assert all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(float(v))
               for v in coefficients), "Trajectory coefficients must be finite numbers"
    actual = np.asarray(coefficients, dtype=float)

    # Accept the common requested fits: y against seconds, frame index, or x,
    # with pixel or metre units. Coefficients are in [c0,c1,c2] order.
    def agrees(candidate):
        scale = np.maximum(1.0, np.abs(candidate))
        return bool(np.all(np.abs(actual - candidate) / scale <= 0.20))
    assert any(agrees(candidate) for candidate in coefficient_candidates), \
        f"Reported coefficients {coefficients} do not fit the extracted projectile centroids"

    steps = results["optimization_steps_taken"]
    assert isinstance(steps, int) and not isinstance(steps, bool), \
        "'optimization_steps_taken' must be an integer"
    assert 0 < steps < 10000000, "'optimization_steps_taken' must be a positive, plausible count"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
