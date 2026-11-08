#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import secrets
import subprocess

import pytest
import requests


def get_oracle_result(y1, y2, y3, t_end):
    cmd = ["/app/chemical_oracle", str(y1), str(y2), str(y3), str(t_end)]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    output = result.stdout.strip()
    parts = output.split()
    if len(parts) != 3:
        raise ValueError(f"Oracle returned unexpected output: {output}")
    return [float(x) for x in parts]


# Retain the original cases and add unpredictable cases spanning multiple time
# scales and initial states so fixed response tables cannot satisfy the tests.
CASES = [
    (1.0, 0.0, 0.0, 0.4),
    (1.0, 0.0, 0.0, 40.0),
    (1.0, 0.0, 0.0, 400.0),
    (0.5, 0.1, 0.4, 10.0),
]

rng = secrets.SystemRandom()
for low_t, high_t in [
    (0.01, 0.1),
    (0.1, 0.5),
    (0.5, 2.0),
    (2.0, 5.0),
    (5.0, 10.0),
    (10.0, 20.0),
    (20.0, 40.0),
    (0.05, 30.0),
]:
    y1 = rng.uniform(0.05, 1.25)
    y2 = rng.uniform(0.0, 1e-6)
    y3 = rng.uniform(0.0, 1.0)
    t_end = rng.uniform(low_t, high_t)
    CASES.append((y1, y2, y3, t_end))


@pytest.mark.parametrize("y1, y2, y3, t_end", CASES)
def test_simulate_endpoint(y1, y2, y3, t_end):
    expected_y = get_oracle_result(y1, y2, y3, t_end)

    url = "http://127.0.0.1:8080/simulate"
    payload = {
        "y0": [y1, y2, y3],
        "t_end": t_end,
    }

    try:
        response = requests.post(url, json=payload, timeout=5.0)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go service at {url}: {e}")

    assert response.status_code == 200, \
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "y_final" in data, f"Missing 'y_final' in response: {data}"

    actual_y = data["y_final"]
    assert isinstance(actual_y, list) and len(actual_y) == 3, \
        f"Expected 'y_final' to be a list of 3 floats, got: {actual_y}"

    for i, (act, exp) in enumerate(zip(actual_y, expected_y)):
        assert math.isclose(act, exp, rel_tol=1e-4, abs_tol=1e-9), \
            f"Mismatch at index {i} for input y0={payload['y0']}, t_end={t_end}. Expected {exp}, got {act}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
