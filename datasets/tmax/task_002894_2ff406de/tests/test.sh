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
from functools import lru_cache

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
VIDEO = "/app/telemetry.mp4"
RAW_DATA = "/home/user/feedback.jsonl"


@lru_cache(maxsize=1)
def expected_results():
    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height", "-of", "json", VIDEO,
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    frame_size = width * height * 3

    decoded = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", VIDEO,
            "-map", "0:v:0", "-vsync", "0",
            "-pix_fmt", "rgb24", "-f", "rawvideo", "-",
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    assert len(decoded) % frame_size == 0, "Video did not decode into complete RGB frames"
    frame_count = len(decoded) // frame_size
    assert frame_count == 60, f"Expected 60 video frames, got {frame_count}"

    black_seconds = []
    for second in range(frame_count):
        frame = decoded[second * frame_size:(second + 1) * frame_size]
        if max(frame) <= 2:
            black_seconds.append(second)
    assert black_seconds == [15, 16, 17, 45, 46], (
        f"Unexpected completely-black video seconds: {black_seconds}"
    )

    windows = []
    for second in black_seconds:
        if not windows or second != windows[-1][-1] + 1:
            windows.append([second])
        else:
            windows[-1].append(second)

    with open(RAW_DATA, "r", encoding="utf-8") as fh:
        raw = [json.loads(line) for line in fh if line.strip()]

    assert len(raw) == 10, f"Expected 10 raw records, got {len(raw)}"

    removed_ids = set()
    for window in windows:
        by_email = {}
        window_set = set(window)
        for record in raw:
            if record["ingest_time_sec"] in window_set:
                by_email.setdefault(record["email"], []).append(record)
        for records in by_email.values():
            keeper = min(records, key=lambda record: record["id"])
            removed_ids.update(record["id"] for record in records if record is not keeper)

    cleaned = []
    for record in raw:
        if record["id"] in removed_ids:
            continue
        local, separator, domain = record["email"].partition("@")
        assert separator and local and domain, f"Invalid source email: {record['email']}"
        masked = dict(record)
        masked["email"] = "[MASKED]@" + domain
        cleaned.append(masked)

    return {
        "total_raw": len(raw),
        "total_cleaned": len(cleaned),
        "removed_ids": sorted(removed_ids),
    }, cleaned


def test_stats_endpoint():
    """Verify the /stats endpoint returns the correct summary statistics."""
    try:
        response = requests.get(f"{BASE_URL}/stats", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /stats endpoint: {e}")

    assert response.status_code == 200, f"Expected status code 200 for /stats, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from /stats is not valid JSON. Response text: {response.text}")

    assert "total_raw" in data, "Missing 'total_raw' in /stats response"
    assert data["total_raw"] == 10, f"Expected total_raw to be 10, got {data['total_raw']}"

    assert "total_cleaned" in data, "Missing 'total_cleaned' in /stats response"
    assert data["total_cleaned"] == 7, f"Expected total_cleaned to be 7, got {data['total_cleaned']}"

    assert "removed_ids" in data, "Missing 'removed_ids' in /stats response"
    removed_ids = sorted(data["removed_ids"])
    assert removed_ids == [4, 5, 8], f"Expected removed_ids to be [4, 5, 8], got {removed_ids}"

    expected_stats, _ = expected_results()
    assert data["total_raw"] == expected_stats["total_raw"]
    assert data["total_cleaned"] == expected_stats["total_cleaned"]
    assert sorted(data["removed_ids"]) == expected_stats["removed_ids"]


def test_cleaned_endpoint():
    """Verify the /cleaned endpoint returns the complete deduplicated and masked JSONL data."""
    try:
        response = requests.get(f"{BASE_URL}/cleaned", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to /cleaned endpoint: {e}")

    assert response.status_code == 200, f"Expected status code 200 for /cleaned, got {response.status_code}"
    media_type = response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
    assert media_type == "text/plain", f"Expected Content-Type text/plain, got {response.headers.get('Content-Type')}"

    try:
        body = response.content.decode("utf-8")
    except UnicodeDecodeError as e:
        pytest.fail(f"/cleaned response is not valid UTF-8: {e}")

    lines = [line for line in body.split("\n") if line.strip()]
    assert len(lines) == 7, f"Expected 7 records in /cleaned response, got {len(lines)}"

    expected_ids = {1, 2, 3, 6, 7, 9, 10}
    received_ids = set()
    received_records = []

    for i, line in enumerate(lines):
        try:
            record = json.loads(line)
        except ValueError:
            pytest.fail(f"Line {i+1} in /cleaned response is not valid JSON: {line}")

        assert "id" in record, f"Missing 'id' in record: {record}"
        received_ids.add(record["id"])

        assert "email" in record, f"Missing 'email' in record: {record}"
        email = record["email"]
        assert email.startswith("[MASKED]@"), f"Email '{email}' is not properly masked. Expected prefix '[MASKED]@'."
        received_records.append(record)

    assert received_ids == expected_ids, f"Expected IDs {expected_ids} in cleaned data, but got {received_ids}"

    _, expected_cleaned = expected_results()
    expected_by_id = {record["id"]: record for record in expected_cleaned}
    assert len(received_ids) == len(received_records), "The cleaned response contains duplicate IDs"
    for record in received_records:
        assert record == expected_by_id[record["id"]], (
            f"Record {record['id']} does not preserve the source fields and exact masked domain: {record}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
