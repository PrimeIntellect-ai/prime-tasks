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
import os
import subprocess
from datetime import datetime, timedelta, timezone

import pytest
import requests

URL = "http://127.0.0.1:8080/api/v1/telemetry"
VIDEO_PATH = "/app/traffic_feed.mp4"
VALID_HEADERS = {"Authorization": "Bearer TRL-992-DATA"}
BASE_TIME = datetime(2024, 5, 1, 8, 0, 0, tzinfo=timezone.utc)


def get_frame_means(video_path, num_frames=3):
    cmd_probe = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height",
        "-of", "csv=s=x:p=0", video_path
    ]
    try:
        output = subprocess.check_output(cmd_probe).decode("utf-8").strip()
        width, height = map(int, output.split("x"))
    except Exception as e:
        pytest.fail(f"Failed to probe video dimensions using ffprobe: {e}")

    cmd_ffmpeg = [
        "ffmpeg", "-i", video_path, "-vframes", str(num_frames),
        "-f", "image2pipe", "-pix_fmt", "gray", "-vcodec", "rawvideo", "-"
    ]
    try:
        raw_video = subprocess.check_output(cmd_ffmpeg, stderr=subprocess.DEVNULL)
    except Exception as e:
        pytest.fail(f"Failed to extract frames using ffmpeg: {e}")

    frame_size = width * height
    means = []
    for i in range(num_frames):
        frame_bytes = raw_video[i * frame_size:(i + 1) * frame_size]
        if not frame_bytes:
            break
        if len(frame_bytes) != frame_size:
            pytest.fail("Video decoder returned an incomplete frame")
        means.append(sum(frame_bytes) / frame_size)
    return means


def iso_timestamp(frame_index):
    dt = BASE_TIME + timedelta(milliseconds=40 * frame_index)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def build_all_expected():
    if not os.path.exists(VIDEO_PATH):
        pytest.fail(f"Video file {VIDEO_PATH} does not exist.")

    means = get_frame_means(VIDEO_PATH, num_frames=100000)
    if len(means) != 50:
        pytest.fail(f"Expected 50 frames in the supplied video, decoded {len(means)}")

    expected = []
    for i, mean in enumerate(means):
        rolling = sum(means[max(0, i - 4):i + 1]) / len(means[max(0, i - 4):i + 1])
        timestamp = iso_timestamp(i)
        expected.append({"timestamp": timestamp, "metric": "brightness", "value": round(mean, 2)})
        expected.append({"timestamp": timestamp, "metric": "rolling_avg", "value": round(rolling, 2)})
    expected.sort(key=lambda item: (item["timestamp"], item["metric"]))
    return expected


ALL_EXPECTED = build_all_expected()


def assert_exact_response(start, end):
    try:
        response = requests.get(
            URL,
            params={"start": start, "end": end},
            headers=VALID_HEADERS,
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")

    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        actual = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    expected = [item for item in ALL_EXPECTED if start <= item["timestamp"] <= end]
    assert isinstance(actual, list), "Expected response to be a JSON array."
    assert len(actual) == len(expected), f"Expected {len(expected)} records, got {len(actual)}."
    for i, (observed, wanted) in enumerate(zip(actual, expected)):
        assert isinstance(observed, dict), f"Record {i} is not a JSON object"
        assert observed.get("timestamp") == wanted["timestamp"], (
            f"Record {i}: Expected timestamp {wanted['timestamp']}, got {observed.get('timestamp')}"
        )
        assert observed.get("metric") == wanted["metric"], (
            f"Record {i}: Expected metric {wanted['metric']}, got {observed.get('metric')}"
        )
        assert observed.get("value") == wanted["value"], (
            f"Record {i}: Expected value {wanted['value']}, got {observed.get('value')}"
        )


def test_unauthorized_access():
    """Retain the original missing-header authentication assertion."""
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


@pytest.mark.parametrize("credential", [
    "Bearer WRONG",
    "Bearer TRL-992-DAT",
    "Bearer TRL-992-DATA-extra",
    "bearer TRL-992-DATA",
    "Basic TRL-992-DATA",
    "TRL-992-DATA",
])
def test_arbitrary_incorrect_credentials_are_rejected(credential):
    response = requests.get(
        URL,
        params={"start": iso_timestamp(0), "end": iso_timestamp(49)},
        headers={"Authorization": credential},
        timeout=5,
    )
    assert response.status_code == 401, (
        f"Expected 401 for incorrect credential {credential!r}, got {response.status_code}"
    )


def test_authorized_access_and_data_correctness():
    """Retain the original first-three-frame correctness assertions."""
    means = get_frame_means(VIDEO_PATH, num_frames=3)
    if len(means) < 3:
        pytest.fail("Could not extract 3 frames from the video.")

    rolling_avgs = []
    for i in range(len(means)):
        window = means[max(0, i - 4):i + 1]
        rolling_avgs.append(sum(window) / len(window))

    timestamps = [
        "2024-05-01T08:00:00.000Z",
        "2024-05-01T08:00:00.040Z",
        "2024-05-01T08:00:00.080Z",
    ]
    expected_data = []
    for i in range(3):
        expected_data.append({
            "timestamp": timestamps[i], "metric": "brightness", "value": round(means[i], 2)
        })
        expected_data.append({
            "timestamp": timestamps[i], "metric": "rolling_avg", "value": round(rolling_avgs[i], 2)
        })
    expected_data.sort(key=lambda item: (item["timestamp"], item["metric"]))

    response = requests.get(
        URL,
        params={"start": timestamps[0], "end": timestamps[2]},
        headers=VALID_HEADERS,
        timeout=5,
    )
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        actual_data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert isinstance(actual_data, list), "Expected response to be a JSON array."
    assert len(actual_data) == len(expected_data), (
        f"Expected {len(expected_data)} records, got {len(actual_data)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get("timestamp") == expected["timestamp"]
        assert actual.get("metric") == expected["metric"]
        assert actual.get("value") == expected["value"]


def test_complete_video_is_processed():
    assert_exact_response(iso_timestamp(0), iso_timestamp(49))


@pytest.mark.parametrize("start,end", [
    (iso_timestamp(7), iso_timestamp(13)),
    (iso_timestamp(21), iso_timestamp(21)),
    (iso_timestamp(45), iso_timestamp(49)),
    ("2024-05-01T08:00:00.101Z", "2024-05-01T08:00:00.199Z"),
    ("2024-05-01T08:00:02.000Z", "2024-05-01T08:00:03.000Z"),
])
def test_general_start_end_filtering(start, end):
    assert_exact_response(start, end)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
