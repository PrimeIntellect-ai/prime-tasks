#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import math
import os
import pytest

POINTS_FILE = '/home/user/points.csv'
CLEANED_POINTS_FILE = '/home/user/cleaned_points.csv'
OUTLIER_COUNT_FILE = '/home/user/outlier_count.txt'

def compute_expected_results():
    assert os.path.isfile(POINTS_FILE), f"Missing {POINTS_FILE}"
    points = []
    with open(POINTS_FILE, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            x, y = map(float, line.split(','))
            points.append((x, y))

    n = len(points)
    assert n > 0, "No points found in points.csv"

    mu_x = sum(p[0] for p in points) / n
    mu_y = sum(p[1] for p in points) / n

    distances = [math.hypot(p[0]-mu_x, p[1]-mu_y) for p in points]
    mu_d = sum(distances) / n
    var_d = sum((d - mu_d)**2 for d in distances) / n
    sigma_d = math.sqrt(var_d)

    threshold = mu_d + 2.0 * sigma_d

    expected_cleaned = []
    expected_outliers = 0

    for p, d in zip(points, distances):
        if d > threshold:
            expected_outliers += 1
        else:
            expected_cleaned.append(p)

    return expected_outliers, expected_cleaned

def test_outlier_count():
    expected_outliers, _ = compute_expected_results()

    assert os.path.isfile(OUTLIER_COUNT_FILE), f"Missing {OUTLIER_COUNT_FILE}"

    with open(OUTLIER_COUNT_FILE, 'r') as f:
        content = f.read().strip()

    try:
        actual_outliers = int(content)
    except ValueError:
        pytest.fail(f"Content of {OUTLIER_COUNT_FILE} is not a valid integer: '{content}'")

    assert actual_outliers == expected_outliers, f"Expected {expected_outliers} outliers, got {actual_outliers}"

def test_cleaned_points():
    _, expected_cleaned = compute_expected_results()

    assert os.path.isfile(CLEANED_POINTS_FILE), f"Missing {CLEANED_POINTS_FILE}"

    with open(CLEANED_POINTS_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_cleaned), f"Expected {len(expected_cleaned)} cleaned points, got {len(lines)}"

    for i, (actual_line, expected_p) in enumerate(zip(lines, expected_cleaned)):
        try:
            ax, ay = map(float, actual_line.split(','))
        except ValueError:
            pytest.fail(f"Line {i+1} in {CLEANED_POINTS_FILE} is not properly formatted: '{actual_line}'")

        ex, ey = expected_p
        assert abs(ax - ex) <= 1e-5, f"X coordinate mismatch at line {i+1}: expected {ex:.6f}, got {ax:.6f}"
        assert abs(ay - ey) <= 1e-5, f"Y coordinate mismatch at line {i+1}: expected {ey:.6f}, got {ay:.6f}"
TEST_EOF

passed=1
SOURCE=/home/user/clean_points.c
BINARY=/tmp/verifier_clean_points

if [ ! -f "$SOURCE" ]; then
    echo "Missing $SOURCE"
    passed=0
fi

if [ "$passed" -eq 1 ]; then
    if ! gcc -std=c11 -O2 "$SOURCE" -lm -o "$BINARY"; then
        echo "Failed to compile $SOURCE"
        passed=0
    fi
fi

if [ "$passed" -eq 1 ]; then
    rm -f /home/user/cleaned_points.csv /home/user/outlier_count.txt
    if ! timeout 30s "$BINARY"; then
        echo "Compiled program failed to run successfully"
        passed=0
    fi
fi

if [ "$passed" -eq 1 ]; then
    if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        passed=0
    fi
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
