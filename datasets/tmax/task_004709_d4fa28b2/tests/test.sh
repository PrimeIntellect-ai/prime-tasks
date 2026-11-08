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
import json
import math
import os
import random
import subprocess

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer devops_admin_2024"}
VIDEO_PATH = "/app/telemetry_feed.mp4"


def get_frame_count(video_path):
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
            "-show_entries", "stream=nb_read_frames",
            "-of", "default=noprint_wrappers=1:nokey=1", video_path,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    return int(result.stdout.strip())


def get_frame_pixels(video_path, frame_number):
    cmd = [
        "ffmpeg", "-y", "-i", video_path,
        "-vf", f"select='eq(n\\,{frame_number})'",
        "-vframes", "1", "-f", "rawvideo", "-pix_fmt", "gray", "-",
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    return result.stdout


def compute_variance(pixels):
    assert pixels, "ffmpeg did not return the requested frame"
    n = len(pixels)
    mean = sum(pixels) / n
    return sum((x - mean) ** 2 for x in pixels) / n


def request_json(path):
    response = requests.get(f"{BASE_URL}{path}", headers=AUTH_HEADER, timeout=15)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}: {response.text}"
    try:
        return response.json()
    except json.JSONDecodeError as exc:
        pytest.fail(f"Endpoint did not return valid JSON: {exc}: {response.text}")


def validate_alert_array(data):
    assert isinstance(data, list), "Alerts endpoint must return a JSON array"
    for item in data:
        assert isinstance(item, int) and not isinstance(item, bool), \
            f"Alerts array must contain integer frame numbers, got {type(item)}"
    assert len(data) == len(set(data)), "Alerts response contains duplicate frame numbers"
    return set(data)


def test_auth_enforcement():
    try:
        response = requests.get(f"{BASE_URL}/api/variance?frame=10", timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not listening on 127.0.0.1:8080")
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized for missing auth header, got {response.status_code}"

    bad_header = {"Authorization": "Bearer wrong_token"}
    response = requests.get(f"{BASE_URL}/api/variance?frame=10", headers=bad_header, timeout=5)
    assert response.status_code == 401, \
        f"Expected 401 Unauthorized for incorrect auth header, got {response.status_code}"

    response = requests.get(f"{BASE_URL}/api/alerts?threshold=150", timeout=5)
    assert response.status_code == 401, "Alerts endpoint accepted a request without authentication"
    response = requests.get(
        f"{BASE_URL}/api/alerts?threshold=150", headers=bad_header, timeout=5
    )
    assert response.status_code == 401, "Alerts endpoint accepted an incorrect token"


def test_variance_endpoint_against_video():
    assert os.path.isfile(VIDEO_PATH), "Telemetry feed is missing"
    frame_count = get_frame_count(VIDEO_PATH)
    assert frame_count > 50, "Telemetry feed has too few frames"

    # Keep the original frame and add unpredictable frames so a constant response
    # cannot satisfy the endpoint contract.
    candidates = [n for n in range(frame_count) if n != 50]
    frames = [50] + random.SystemRandom().sample(candidates, min(4, len(candidates)))

    for frame_to_test in frames:
        data = request_json(f"/api/variance?frame={frame_to_test}")
        assert isinstance(data, dict), "Variance endpoint must return a JSON object"
        assert "frame" in data, "Response JSON missing 'frame' key"
        assert "variance" in data, "Response JSON missing 'variance' key"
        assert data["frame"] == frame_to_test, \
            f"Response identified frame {data['frame']} instead of requested frame {frame_to_test}"

        variance = data["variance"]
        assert isinstance(variance, (int, float)) and not isinstance(variance, bool), \
            "Variance must be a number"
        assert not math.isnan(variance), "Variance calculation resulted in NaN"
        assert not math.isinf(variance), "Variance calculation resulted in Infinity"
        assert variance >= 0, "Variance cannot be negative"

        expected_variance = compute_variance(get_frame_pixels(VIDEO_PATH, frame_to_test))
        assert math.isclose(variance, expected_variance, rel_tol=1e-2, abs_tol=1.0), \
            f"Variance {variance} for frame {frame_to_test} does not match expected {expected_variance}"


def test_alerts_endpoint_filters_frames():
    frame_count = get_frame_count(VIDEO_PATH)

    # Preserve the original threshold/type assertions.
    alerts_150 = validate_alert_array(request_json("/api/alerts?threshold=150.0"))

    # Pixel-derived brightness/variance smoothing is nonnegative. Therefore every
    # processed frame must strictly exceed -1, while no valid smoothed telemetry
    # value from this 8-bit feed can exceed this deliberately enormous threshold.
    alerts_low = validate_alert_array(request_json("/api/alerts?threshold=-1"))
    alerts_high = validate_alert_array(request_json("/api/alerts?threshold=1000000000"))

    zero_based = set(range(frame_count))
    one_based = set(range(1, frame_count + 1))
    assert alerts_low in (zero_based, one_based), \
        f"Low-threshold query must return every frame exactly once; got {len(alerts_low)} of {frame_count}"
    assert alerts_high == set(), "An impossibly high threshold returned false-positive alerts"

    alerts_100 = validate_alert_array(request_json("/api/alerts?threshold=100.0"))
    assert alerts_150 <= alerts_100 <= alerts_low, \
        "Alert results are not correctly filtered as the threshold increases"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-x", "--tb=short"]))
TEST_EOF

status=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
