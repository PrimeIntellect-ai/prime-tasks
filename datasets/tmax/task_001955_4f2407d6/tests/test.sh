#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random

import pytest
import requests

URL = "http://127.0.0.1:9090/analyze"
TOKEN = "LOG-ANALYSIS-TOK-55"
REFERENCE_X = [10, 30, 50, 70, 90]
REFERENCE_Y = [20, 25, 50, 25, 20]


def zscore(values):
    values = [float(v) for v in values]
    mean = sum(values) / len(values)
    variance = sum((v - mean) ** 2 for v in values) / (len(values) - 1)
    stddev = math.sqrt(variance)
    assert stddev > 0, "Verifier generated a constant path"
    return [(v - mean) / stddev for v in values]


def expected_distance(x_path, y_path):
    ref_x = zscore(REFERENCE_X)
    ref_y = zscore(REFERENCE_Y)
    input_x = zscore(x_path)
    input_y = zscore(y_path)
    return sum(
        math.hypot(ref_x[i] - input_x[i], ref_y[i] - input_y[i])
        for i in range(5)
    ) / 5


def post_authorized(x_path, y_path):
    payload = {
        "auth": TOKEN,
        "x_path": x_path,
        "y_path": y_path,
    }
    try:
        response = requests.post(URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to API: {exc}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert "distance" in data, "Missing 'distance' in response"
    assert "is_anomaly" in data, "Missing 'is_anomaly' in response"
    assert isinstance(data["distance"], (int, float)) and not isinstance(data["distance"], bool)
    assert math.isfinite(data["distance"])
    assert isinstance(data["is_anomaly"], bool)
    return data


def assert_analysis(x_path, y_path):
    expected = expected_distance(x_path, y_path)
    data = post_authorized(x_path, y_path)
    assert math.isclose(data["distance"], expected, rel_tol=1e-5, abs_tol=1e-5), (
        f"Expected distance {expected}, got {data['distance']} for "
        f"x_path={x_path}, y_path={y_path}"
    )
    assert data["is_anomaly"] is (expected > 0.5), (
        f"Expected is_anomaly={expected > 0.5} for distance {expected}, "
        f"got {data['is_anomaly']}"
    )


def test_extracted_path_file():
    filepath = "/home/user/extracted_path.json"
    assert os.path.exists(filepath), f"File not found: {filepath}"

    with open(filepath, "r") as handle:
        data = json.load(handle)

    assert "x" in data, "Missing 'x' in extracted path"
    assert "y" in data, "Missing 'y' in extracted path"
    assert data["x"] == REFERENCE_X, f"Expected x coordinates {REFERENCE_X}, got {data['x']}"
    assert data["y"] == REFERENCE_Y, f"Expected y coordinates {REFERENCE_Y}, got {data['y']}"


def test_api_unauthorized():
    payload = {
        "auth": "BAD-TOKEN",
        "x_path": [1, 2, 3, 4, 5],
        "y_path": [1, 2, 3, 4, 5],
    }
    try:
        response = requests.post(URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to API: {exc}")
    assert response.status_code == 401, f"Expected HTTP 401 for bad auth, got {response.status_code}"


def test_api_normal_behavior():
    data = post_authorized(REFERENCE_X, REFERENCE_Y)
    assert math.isclose(data["distance"], 0.0, abs_tol=1e-4), (
        f"Distance should be ~0.0, got {data['distance']}"
    )
    assert data["is_anomaly"] is False, "Expected is_anomaly to be False for identical path"


def test_api_anomaly_behavior():
    # Both dimensions have a defined sample standard deviation.
    x_path = [90, 70, 50, 30, 10]
    y_path = [20, 25, 50, 25, 20]
    data = post_authorized(x_path, y_path)
    expected = expected_distance(x_path, y_path)
    assert math.isclose(data["distance"], expected, rel_tol=1e-5, abs_tol=1e-5)
    assert data["distance"] > 0.5, f"Distance should be > 0.5, got {data['distance']}"
    assert data["is_anomaly"] is True, "Expected is_anomaly to be True for different path"


def test_api_varied_derived_inputs():
    # Generate inputs after the agent has finished, and derive every expected answer
    # independently using the specified sample-standard-deviation normalization.
    rng = random.SystemRandom()
    cases = []

    # Positive affine transforms must normalize to the same reference shape.
    for _ in range(3):
        ax = rng.uniform(0.2, 8.0)
        ay = rng.uniform(0.2, 8.0)
        bx = rng.uniform(-500.0, 500.0)
        by = rng.uniform(-500.0, 500.0)
        cases.append((
            [ax * value + bx for value in REFERENCE_X],
            [ay * value + by for value in REFERENCE_Y],
        ))

    # Slightly perturb affine transforms to produce varied nonzero normal distances.
    for _ in range(7):
        ax = rng.uniform(0.3, 6.0)
        ay = rng.uniform(0.3, 6.0)
        bx = rng.uniform(-300.0, 300.0)
        by = rng.uniform(-300.0, 300.0)
        x_path = [ax * value + bx + rng.uniform(-1.5 * ax, 1.5 * ax) for value in REFERENCE_X]
        y_path = [ay * value + by + rng.uniform(-0.6 * ay, 0.6 * ay) for value in REFERENCE_Y]
        assert 0.0 < expected_distance(x_path, y_path) < 0.5
        cases.append((x_path, y_path))

    # Independently random, nonconstant paths provide varied anomaly distances.
    anomaly_cases = []
    while len(anomaly_cases) < 8:
        x_path = [rng.uniform(-1000.0, 1000.0) for _ in range(5)]
        y_path = [rng.uniform(-1000.0, 1000.0) for _ in range(5)]
        if expected_distance(x_path, y_path) > 0.65:
            anomaly_cases.append((x_path, y_path))
    cases.extend(anomaly_cases)

    for x_path, y_path in cases:
        assert_analysis(x_path, y_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
