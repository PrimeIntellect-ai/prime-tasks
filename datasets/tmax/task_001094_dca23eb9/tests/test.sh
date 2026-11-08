#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import math
import os
import random
import subprocess
import pytest


def test_bad_commit_file():
    bad_commit_path = "/home/user/bad_commit.txt"
    repo_path = "/home/user/geo_service"

    assert os.path.isfile(bad_commit_path), f"File {bad_commit_path} does not exist."

    with open(bad_commit_path, "r") as f:
        commit_hash = f.read().strip()

    assert len(commit_hash) == 40, f"Expected a 40-character commit hash, got '{commit_hash}'"

    try:
        result = subprocess.run(
            ["git", "log", "-1", "--format=%s", commit_hash],
            cwd=repo_path,
            capture_output=True,
            text=True,
            check=True
        )
        commit_msg = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to retrieve commit message for hash {commit_hash}. Git error: {e.stderr}")

    assert commit_msg == "Refactor: commit 137", f"Commit hash {commit_hash} corresponds to message '{commit_msg}', expected 'Refactor: commit 137'."


def test_calc_py_fixed():
    calc_path = "/home/user/geo_service/calc.py"
    assert os.path.isfile(calc_path), f"File {calc_path} does not exist."

    # Test with the coordinates from the pcap
    try:
        result = subprocess.run(
            ["python3", calc_path, "40.7128", "-74.006", "51.5074", "-0.1278"],
            capture_output=True,
            text=True,
            check=True
        )
        output = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running calc.py failed: {e.stderr}")

    try:
        distance = float(output)
    except ValueError:
        pytest.fail(f"calc.py output '{output}' is not a valid float.")

    expected_distance = 5570.222179737958
    assert math.isclose(distance, expected_distance, rel_tol=1e-12), \
        f"Calculated distance {distance} does not match expected {expected_distance} with high precision."


def test_calc_py_not_hardcoded():
    calc_path = "/home/user/geo_service/calc.py"

    # Test with different coordinates to ensure it's not hardcoded
    try:
        result = subprocess.run(
            ["python3", calc_path, "0", "0", "0", "0"],
            capture_output=True,
            text=True,
            check=True
        )
        output = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Running calc.py failed: {e.stderr}")

    try:
        distance = float(output)
    except ValueError:
        pytest.fail(f"calc.py output '{output}' is not a valid float.")

    assert math.isclose(distance, 0.0, abs_tol=1e-9), \
        f"Calculated distance for 0,0 to 0,0 should be 0.0, got {distance}. The solution might be hardcoded."


def reference_haversine(lat1, lon1, lat2, lon2):
    radius = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, (lat1, lon1, lat2, lon2))
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    c = 2 * math.asin(math.sqrt(a))
    return radius * c


def test_calc_py_general_precision():
    calc_path = "/home/user/geo_service/calc.py"
    assert os.path.isfile(calc_path), f"File {calc_path} does not exist."

    rng = random.SystemRandom()
    cases = []

    # Broad, unpredictable coordinate pairs exercise the complete formula.
    for _ in range(32):
        cases.append((
            rng.uniform(-85.0, 85.0),
            rng.uniform(-180.0, 180.0),
            rng.uniform(-85.0, 85.0),
            rng.uniform(-180.0, 180.0),
        ))

    # Nearby points specifically expose the precision-destroying rounding regression.
    for _ in range(12):
        lat1 = rng.uniform(-80.0, 80.0)
        lon1 = rng.uniform(-170.0, 170.0)
        lat2 = lat1 + rng.uniform(-0.01, 0.01)
        lon2 = lon1 + rng.uniform(-0.01, 0.01)
        if lat1 == lat2 and lon1 == lon2:
            lat2 += 0.001
        cases.append((lat1, lon1, lat2, lon2))

    for coordinates in cases:
        expected = reference_haversine(*coordinates)
        try:
            result = subprocess.run(
                ["python3", calc_path, *(repr(value) for value in coordinates)],
                capture_output=True,
                text=True,
                check=True,
                timeout=10,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            pytest.fail(f"Running calc.py for {coordinates} failed: {e}")

        output = result.stdout.strip()
        try:
            actual = float(output)
        except ValueError:
            pytest.fail(f"calc.py output '{output}' for {coordinates} is not a valid float.")

        assert math.isfinite(actual), f"calc.py returned a non-finite value for {coordinates}: {actual}"
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-9), \
            f"Calculated distance {actual} for {coordinates} does not match expected {expected}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
