#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
import tempfile

import cv2
import numpy as np

AGENT_SCRIPT = "/home/user/transform.py"
TRAJECTORY = "/home/user/trajectory.json"
TOKENS = "/home/user/video_tokens.txt"
PLOT = "/home/user/centered_plot.png"
VIDEO = "/app/data/experiment.mp4"


def process(data):
    if not data:
        return [], ""

    smoothed = []
    for i in range(len(data)):
        window = data[max(0, i - 2):i + 1]
        smoothed.append((
            sum(p[0] for p in window) / len(window),
            sum(p[1] for p in window) / len(window),
        ))

    mean_x = sum(p[0] for p in smoothed) / len(smoothed)
    mean_y = sum(p[1] for p in smoothed) / len(smoothed)
    centered = [(x - mean_x, y - mean_y) for x, y in smoothed]

    tokens = []
    for x, y in centered:
        if x >= 0 and y >= 0:
            tokens.append("A")
        elif x < 0 and y >= 0:
            tokens.append("B")
        elif x < 0 and y < 0:
            tokens.append("C")
        else:
            tokens.append("D")
    return centered, "".join(tokens)


def decode_video_trajectory():
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), f"Could not open {VIDEO}"
    points = []
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            b, g, r = cv2.split(frame)
            mask = ((r.astype(np.int16) > 150) &
                    (r.astype(np.int16) - g.astype(np.int16) > 80) &
                    (r.astype(np.int16) - b.astype(np.int16) > 80)).astype(np.uint8)
            moments = cv2.moments(mask, binaryImage=True)
            assert moments["m00"] > 0, f"No red object found in frame {len(points)}"
            points.append([
                moments["m10"] / moments["m00"],
                moments["m01"] / moments["m00"],
            ])
    finally:
        cap.release()
    assert len(points) == 300, f"Expected 300 video frames, decoded {len(points)}"
    return points


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    random.seed(42)
    cases = [[]]
    for _ in range(100):
        length = random.randint(10, 100)
        cases.append([[random.uniform(-500.0, 500.0), random.uniform(-500.0, 500.0)]
                      for _ in range(length)])

    for i, data in enumerate(cases):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f_in:
            json.dump(data, f_in)
            in_path = f_in.name
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f_out:
            out_path = f_out.name
        try:
            result = subprocess.run(
                ["python3", AGENT_SCRIPT, in_path, out_path],
                capture_output=True, text=True, timeout=10
            )
            assert result.returncode == 0, f"Agent script failed on fuzz input {i}:\n{result.stderr}"
            with open(out_path, "r") as f:
                actual = f.read()
            expected = process(data)[1]
            assert actual == expected, (
                f"Mismatch on fuzz input {i}:\nInput: {data}\n"
                f"Expected: {expected}\nActual: {actual}"
            )
        finally:
            for path in (in_path, out_path):
                if os.path.exists(path):
                    os.remove(path)


def test_trajectory_json_matches_video():
    assert os.path.isfile(TRAJECTORY), f"Missing {TRAJECTORY}"
    with open(TRAJECTORY, "r") as f:
        data = json.load(f)

    expected = decode_video_trajectory()
    assert isinstance(data, list), "Trajectory should be a JSON array"
    assert len(data) == len(expected), f"Expected {len(expected)} trajectory points, got {len(data)}"
    for i, (point, target) in enumerate(zip(data, expected)):
        assert isinstance(point, list) and len(point) == 2, f"Point {i} must be a 2-element array"
        assert all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
                   for v in point), f"Point {i} must contain finite numbers"
        assert abs(point[0] - target[0]) <= 0.35 and abs(point[1] - target[1]) <= 0.35, (
            f"Trajectory point {i} does not match the red-object centroid: "
            f"expected approximately {target}, got {point}"
        )


def test_video_tokens():
    assert os.path.isfile(TOKENS), f"Missing {TOKENS}"
    assert os.path.isfile(TRAJECTORY), f"Missing {TRAJECTORY}"
    with open(TRAJECTORY, "r") as f:
        trajectory = json.load(f)
    expected = process(trajectory)[1]
    with open(TOKENS, "r") as f:
        actual = f.read()
    assert actual == expected, "video_tokens.txt does not match the required transform of trajectory.json"


def test_centered_plot():
    assert os.path.isfile(PLOT), f"Missing {PLOT}"
    assert os.path.getsize(PLOT) > 0, "Plot file is empty"
    with open(PLOT, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "Plot file is not a PNG"

    image = cv2.imread(PLOT, cv2.IMREAD_COLOR)
    assert image is not None, "Plot PNG cannot be decoded"
    height, width = image.shape[:2]
    assert width >= 200 and height >= 150, "Plot is too small to be a usable visualization"

    with open(TRAJECTORY, "r") as f:
        trajectory = json.load(f)
    centered, _ = process(trajectory)
    expected = np.asarray(centered, dtype=np.float64)

    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    colored = ((hsv[:, :, 1] >= 55) & (hsv[:, :, 2] >= 45)).astype(np.uint8)
    ys, xs = np.nonzero(colored)
    assert len(xs) >= 150, "Plot has no substantial plotted data"

    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    assert x1 - x0 >= width * 0.25 and y1 - y0 >= height * 0.25, \
        "Plotted data does not span the centered trajectory's two-dimensional range"

    ex_min, ey_min = expected.min(axis=0)
    ex_max, ey_max = expected.max(axis=0)
    px = x0 + (expected[:, 0] - ex_min) * (x1 - x0) / (ex_max - ex_min)
    py = y1 - (expected[:, 1] - ey_min) * (y1 - y0) / (ey_max - ey_min)
    plotted_points = np.column_stack((px, py)).round().astype(np.int32)

    expected_mask = np.zeros((height, width), dtype=np.uint8)
    cv2.polylines(expected_mask, [plotted_points.reshape(-1, 1, 2)], False, 1,
                  thickness=max(1, min(width, height) // 250), lineType=cv2.LINE_AA)
    for x, y in plotted_points:
        cv2.circle(expected_mask, (int(x), int(y)), max(2, min(width, height) // 180), 1, -1)

    radius = max(4, min(width, height) // 80)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * radius + 1, 2 * radius + 1))
    near_expected = cv2.dilate(expected_mask, kernel) > 0
    near_colored = cv2.dilate(colored, kernel) > 0

    point_hits = [near_colored[int(y), int(x)] for x, y in plotted_points
                  if 0 <= x < width and 0 <= y < height]
    coverage = float(np.mean(point_hits))
    precision = float(np.count_nonzero((colored > 0) & near_expected)) / float(np.count_nonzero(colored))
    assert coverage >= 0.75 and precision >= 0.55, (
        "centered_plot.png does not depict the smoothed and centered video trajectory "
        f"(coverage={coverage:.3f}, precision={precision:.3f})"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
