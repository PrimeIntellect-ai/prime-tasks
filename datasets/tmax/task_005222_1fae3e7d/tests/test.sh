#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import secrets
import random

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
ENDPOINT = f"{BASE_URL}/api/v1/translations/process"
AUTH_HEADER = {"Authorization": "Bearer LOCALIZATION_ENGINEER_TOKEN_99"}
RNG = random.SystemRandom()


def post(payload, headers=AUTH_HEADER):
    try:
        return requests.post(ENDPOINT, json=payload, headers=headers, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:8080")


def assert_rolling_value(segment, expected):
    assert "rollingConfidence" in segment, "rollingConfidence is missing"
    actual = segment["rollingConfidence"]
    assert isinstance(actual, (int, float)) and not isinstance(actual, bool)
    assert math.isfinite(actual)
    assert math.isclose(actual, expected, rel_tol=1e-6, abs_tol=1e-6), \
        f"Expected rollingConfidence {expected}, got {actual}"


def test_unauthorized_access():
    response = post([], headers={})
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"

    response = post([], headers={"Authorization": "Bearer WRONG_TOKEN"})
    assert response.status_code == 401, f"Expected 401 for an incorrect token, got {response.status_code}"


def test_empty_payload():
    response = post([])
    assert response.status_code == 200, response.text
    assert response.json() == [], "An empty input array must produce an empty output array"


def test_randomized_processing_and_rolling_statistics():
    count = RNG.randint(5, 9)
    cursor = RNG.uniform(0.1, 0.5)
    payload = []
    for _ in range(count):
        duration = RNG.uniform(0.25, 0.55)
        confidence = RNG.uniform(0.15, 0.98)
        payload.append({
            "startTime": cursor,
            "endTime": cursor + duration,
            "text": "rolling-" + secrets.token_hex(12),
            "confidence": confidence,
        })
        cursor += duration

    response = post(payload)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}: {response.text}"
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == len(payload), "Contiguous input must not gain or lose segments"

    for i, (original, result) in enumerate(zip(payload, data)):
        assert result.get("text") == original["text"]
        assert math.isclose(result.get("startTime"), original["startTime"], abs_tol=1e-6)
        assert math.isclose(result.get("endTime"), original["endTime"], abs_tol=1e-6)
        assert math.isclose(result.get("confidence"), original["confidence"], abs_tol=1e-6)
        window = payload[max(0, i - 2):i + 1]
        expected = sum(s["confidence"] for s in window) / len(window)
        assert_rolling_value(result, expected)


def test_randomized_gap_imputation_without_extra_segments():
    count = RNG.randint(4, 6)
    gap_after = RNG.randrange(1, count - 1)
    gap_size = RNG.uniform(2.2, 4.4)
    cursor = RNG.uniform(0.1, 0.4)
    payload = []
    expected_gap = None

    for i in range(count):
        duration = RNG.uniform(0.3, 0.6)
        segment = {
            "startTime": cursor,
            "endTime": cursor + duration,
            "text": "gap-" + secrets.token_hex(12),
            "confidence": RNG.uniform(0.2, 0.95),
        }
        payload.append(segment)
        cursor = segment["endTime"]
        if i == gap_after:
            expected_gap = (cursor, cursor + gap_size)
            cursor += gap_size

    response = post(payload)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}: {response.text}"
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == len(payload) + 1, "Exactly one placeholder must be inserted for one qualifying gap"

    for original in payload:
        matches = [s for s in data if s.get("text") == original["text"]]
        assert len(matches) == 1, "Every original segment must appear exactly once"
        result = matches[0]
        assert math.isclose(result.get("startTime"), original["startTime"], abs_tol=1e-6)
        assert math.isclose(result.get("endTime"), original["endTime"], abs_tol=1e-6)

    gap_start, gap_end = expected_gap
    imputed = [s for s in data
               if math.isclose(s.get("startTime", -1), gap_start, abs_tol=0.05)
               and math.isclose(s.get("endTime", -1), gap_end, abs_tol=0.05)]
    assert len(imputed) == 1, f"Expected one placeholder spanning {gap_start} to {gap_end}"

    for segment in data:
        assert "rollingConfidence" in segment, "Every returned segment needs rollingConfidence"
        value = segment["rollingConfidence"]
        assert isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
        assert segment["endTime"] - segment["startTime"] <= 7.0 + 1e-6


def test_scene_boundary_adjusts_preceding_segment():
    text = "boundary-before-" + secrets.token_hex(12)
    start = RNG.uniform(9.5, 11.5)
    end = RNG.uniform(12.6, 12.9)
    payload = [{"startTime": start, "endTime": end, "text": text, "confidence": RNG.uniform(0.3, 0.95)}]

    response = post(payload)
    assert response.status_code == 200, response.text
    data = response.json()
    assert isinstance(data, list) and len(data) == 1
    overlap_seg = next((s for s in data if s.get("text") == text), None)
    assert overlap_seg is not None, "Overlap segment missing from response"
    assert overlap_seg["endTime"] <= 12.5 + 0.02, \
        f"Expected endTime to be adjusted to the black-frame boundary, got {overlap_seg['endTime']}"
    assert "rollingConfidence" in overlap_seg


def test_scene_boundary_adjusts_following_segment():
    text = "boundary-after-" + secrets.token_hex(12)
    start = RNG.uniform(12.6, 12.9)
    payload = [{"startTime": start, "endTime": 14.2, "text": text, "confidence": RNG.uniform(0.3, 0.95)}]

    response = post(payload)
    assert response.status_code == 200, response.text
    data = response.json()
    assert isinstance(data, list) and len(data) == 1
    segment = next((s for s in data if s.get("text") == text), None)
    assert segment is not None, "Following segment missing from response"
    assert segment["startTime"] >= 12.98, \
        f"Expected startTime to be moved past the black interval, got {segment['startTime']}"


def test_duration_constraint_keeps_the_segment():
    text = "long-" + secrets.token_hex(12)
    start = RNG.uniform(15.0, 18.0)
    duration = RNG.uniform(7.5, 11.0)
    payload = [{"startTime": start, "endTime": start + duration, "text": text, "confidence": RNG.uniform(0.3, 0.95)}]

    response = post(payload)
    assert response.status_code == 200, response.text
    data = response.json()
    assert isinstance(data, list) and len(data) == 1
    long_seg = next((s for s in data if s.get("text") == text), None)
    assert long_seg is not None, "Long segment must be retained and adjusted, not omitted"
    adjusted_duration = long_seg["endTime"] - long_seg["startTime"]
    assert adjusted_duration <= 7.0 + 1e-6, f"Expected duration <= 7.0s, got {adjusted_duration}s"
    assert "rollingConfidence" in long_seg
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
