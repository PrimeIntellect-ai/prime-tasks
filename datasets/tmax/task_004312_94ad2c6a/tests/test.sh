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
import subprocess
from collections import Counter

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
VIDEO_PATH = "/app/ui_test.mp4"
RAW_PATH = "/home/user/raw_translations.jsonl"


def derive_active_windows():
    """Use ffmpeg to sample one frame per second and reduce each frame to its mean brightness."""
    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", VIDEO_PATH,
            "-vf", "fps=1,scale=1:1,format=gray",
            "-f", "rawvideo", "-pix_fmt", "gray", "pipe:1",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=30,
    )
    brightness = list(result.stdout)
    assert brightness, "ffmpeg extracted no frames from the video"

    windows = []
    start = None
    for second, mean_intensity in enumerate(brightness):
        if mean_intensity > 10 and start is None:
            start = second
        elif mean_intensity <= 10 and start is not None:
            windows.append((start, second - 1))
            start = None
    if start is not None:
        windows.append((start, len(brightness) - 1))
    return windows


def derive_expected(windows):
    """Bucket raw records into video windows and retain the longest text per key/window."""
    selected = {}
    with open(RAW_PATH, "r", encoding="utf-8") as raw_file:
        for line_number, line in enumerate(raw_file, 1):
            if not line.strip():
                continue
            record = json.loads(line)
            assert all(k in record for k in ("timestamp", "loc_key", "text")), \
                f"Raw record on line {line_number} is missing a required key"

            window_index = next(
                (i for i, (start, end) in enumerate(windows)
                 if start <= record["timestamp"] <= end),
                None,
            )
            if window_index is None:
                continue

            bucket_key = (window_index, record["loc_key"])
            current = selected.get(bucket_key)
            if current is None or len(record["text"]) > len(current["text"]):
                selected[bucket_key] = record

    return sorted(selected.values(), key=lambda record: record["timestamp"])


WINDOWS = derive_active_windows()
EXPECTED_DATA = derive_expected(WINDOWS)


def canonical_records(records):
    return Counter(json.dumps(record, sort_keys=True, separators=(",", ":")) for record in records)


def test_stats_endpoint():
    """Verify the /stats endpoint returns the video-derived deduplication statistics."""
    try:
        response = requests.get(f"{BASE_URL}/stats", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/stats: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from /stats is not valid JSON. Response text: {response.text}")

    assert "total_unique_screens" in data, "Missing 'total_unique_screens' in /stats response"
    assert "total_deduplicated_records" in data, "Missing 'total_deduplicated_records' in /stats response"

    # Preserve the original fixture assertions and also tie them to independently derived results.
    assert len(WINDOWS) == 5, f"Expected video analysis to find 5 screens, got {len(WINDOWS)}"
    assert len(EXPECTED_DATA) == 15, f"Expected raw-data deduplication to produce 15 records, got {len(EXPECTED_DATA)}"
    assert data["total_unique_screens"] == 5, f"Expected 5 unique screens, got {data['total_unique_screens']}"
    assert data["total_deduplicated_records"] == 15, f"Expected 15 deduplicated records, got {data['total_deduplicated_records']}"
    assert data["total_unique_screens"] == len(WINDOWS)
    assert data["total_deduplicated_records"] == len(EXPECTED_DATA)


def test_data_endpoint():
    """Verify /data contains the actual longest raw record per video-derived window and key."""
    try:
        response = requests.get(f"{BASE_URL}/data", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/data: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from /data is not valid JSON. Response text: {response.text}")

    assert isinstance(data, list), f"Expected /data to return a JSON array, got {type(data).__name__}"
    assert len(data) == 15, f"Expected 15 records in /data response, got {len(data)}"

    timestamps = [record.get("timestamp", 0) for record in data]
    assert timestamps == sorted(timestamps), "Records in /data are not sorted by timestamp ascending"

    for i, record in enumerate(data):
        assert "timestamp" in record, f"Record at index {i} missing 'timestamp'"
        assert "loc_key" in record, f"Record at index {i} missing 'loc_key'"
        assert "text" in record, f"Record at index {i} missing 'text'"

    assert canonical_records(data) == canonical_records(EXPECTED_DATA), \
        "/data does not contain the longest raw record for every loc_key in each video-derived screen window"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
