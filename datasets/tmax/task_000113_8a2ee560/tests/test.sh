#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import time

import cv2
import numpy as np
import pytest
import requests

CSV_PATH = "/home/user/trajectory.csv"
VIDEO_PATH = "/app/drop_test.mp4"


def load_trajectory():
    assert os.path.exists(CSV_PATH), f"Expected trajectory file at {CSV_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"Path {CSV_PATH} is not a file."
    assert os.path.getsize(CSV_PATH) > 0, f"Trajectory file {CSV_PATH} is empty."

    with open(CSV_PATH, newline="") as f:
        rows = [row for row in csv.reader(f) if row and any(cell.strip() for cell in row)]

    assert rows, "trajectory.csv contains no rows"
    start = 0
    try:
        float(rows[0][0])
        float(rows[0][1])
    except (ValueError, IndexError):
        assert [cell.strip().lower() for cell in rows[0]] == ["frame_index", "y_pixel"], \
            "CSV header, if present, must be exactly frame_index,y_pixel"
        start = 1

    parsed = []
    for line_number, row in enumerate(rows[start:], start=start + 1):
        assert len(row) == 2, f"CSV row {line_number} must contain exactly two columns"
        try:
            frame_value = float(row[0])
            y_value = float(row[1])
        except ValueError:
            pytest.fail(f"CSV row {line_number} contains a non-numeric value")
        assert math.isfinite(frame_value) and math.isfinite(y_value), \
            f"CSV row {line_number} contains a non-finite value"
        assert frame_value.is_integer(), f"Frame index on row {line_number} must be an integer"
        parsed.append((int(frame_value), y_value))

    assert parsed, "trajectory.csv contains no trajectory data"
    return parsed


def independently_track_video():
    cap = cv2.VideoCapture(VIDEO_PATH)
    assert cap.isOpened(), f"Could not open experiment video {VIDEO_PATH}"
    centers = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        mask = (gray >= 80).astype(np.uint8)
        count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, 8)
        assert count > 1, f"No bright mass found in video frame {len(centers)}"
        component = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        assert stats[component, cv2.CC_STAT_AREA] >= 100, \
            f"Bright object in frame {len(centers)} is too small to be the mass"
        centers.append(float(centroids[component][1]))
    cap.release()
    assert centers, "Experiment video contains no readable frames"
    return centers


def derived_results(trajectory):
    y = np.asarray([row[1] for row in trajectory], dtype=float)
    t = np.arange(len(y), dtype=float) / 30.0

    linear_coeff = np.polyfit(t, y, 1)
    quadratic_coeff = np.polyfit(t, y, 2)
    linear_rss = float(np.sum((y - np.polyval(linear_coeff, t)) ** 2))
    quadratic_rss = float(np.sum((y - np.polyval(quadratic_coeff, t)) ** 2))
    acceleration = float(2.0 * quadratic_coeff[0] * 0.005)

    # Forward finite differences assign one velocity to each frame interval;
    # integrating those interval velocities gives the measured displacement.
    interval_velocity = np.diff(y) * 0.005 * 30.0
    displacement = float(np.sum(interval_velocity / 30.0))
    return acceleration, linear_rss, quadratic_rss, displacement


def test_trajectory_csv_exists():
    """Verify that trajectory.csv contains tracking data matching every video frame."""
    trajectory = load_trajectory()
    expected_y = independently_track_video()

    assert len(trajectory) == len(expected_y), \
        f"Expected one trajectory row per video frame ({len(expected_y)}), got {len(trajectory)}"

    indices = [row[0] for row in trajectory]
    assert indices == list(range(indices[0], indices[0] + len(indices))), \
        "Frame indices must be consecutive and ordered"
    assert indices[0] in (0, 1), "Frame indices must use conventional zero-based or one-based numbering"

    for ordinal, ((_, actual_y), video_y) in enumerate(zip(trajectory, expected_y)):
        assert abs(actual_y - video_y) <= 2.0, \
            f"Tracked y position for video frame {ordinal} is incorrect: got {actual_y}, expected about {video_y:.3f}"


def test_api_response():
    """Verify that the API reports rounded analysis derived from the tracked trajectory."""
    url = "http://127.0.0.1:9090/analysis"

    max_retries = 5
    response = None
    for _ in range(max_retries):
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException:
            time.sleep(1)

    assert response is not None, f"Failed to connect to the service at {url}"
    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    try:
        data = response.json()
    except Exception as e:
        pytest.fail(f"Failed to parse JSON response: {e}")

    expected_keys = {"acceleration_m_s2", "linear_rss", "quadratic_rss", "integrated_displacement_m"}
    assert expected_keys.issubset(data.keys()), \
        f"JSON response is missing required keys. Expected: {expected_keys}, Got: {set(data.keys())}"
    assert set(data.keys()) == expected_keys, \
        f"JSON payload must contain exactly the required keys, got {set(data.keys())}"

    accel = data["acceleration_m_s2"]
    lin_rss = data["linear_rss"]
    quad_rss = data["quadratic_rss"]
    disp = data["integrated_displacement_m"]

    for name, value in data.items():
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{name} must be a number"
        assert math.isfinite(value), f"{name} must be finite"
        assert abs(float(value) - round(float(value), 3)) < 1e-9, f"{name} must be rounded to 3 decimal places"

    # Preserve the original experiment-level assertions.
    assert abs(accel - 9.81) < 0.5, f"Expected acceleration ~9.81 m/s^2, got {accel}"
    assert lin_rss > 1000, f"Expected linear_rss to be very high (>1000), got {lin_rss}"
    assert quad_rss < 50, f"Expected quadratic_rss to be low (<50), got {quad_rss}"
    assert abs(disp - 3.75) < 0.5, f"Expected integrated displacement ~3.75 m, got {disp}"

    expected = derived_results(load_trajectory())
    reported = (float(accel), float(lin_rss), float(quad_rss), float(disp))
    names = ("acceleration_m_s2", "linear_rss", "quadratic_rss", "integrated_displacement_m")
    tolerances = (0.0011, 0.0011, 0.0011, 0.011)
    for name, actual, calculated, tolerance in zip(names, reported, expected, tolerances):
        target = round(calculated, 3)
        assert abs(actual - target) <= tolerance, \
            f"{name} does not match analysis of trajectory.csv: got {actual}, expected {target}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
