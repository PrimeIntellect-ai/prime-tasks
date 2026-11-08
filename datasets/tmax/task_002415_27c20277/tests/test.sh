#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import shutil
import subprocess
import tempfile

import cv2
import numpy as np
import pytest
import requests

RAW = "/home/user/raw_signal.csv"
CLEANED = "/home/user/cleaned_signal.json"
PIPELINE = "/home/user/pipeline.sh"
LOG = "/home/user/pipeline.log"
VIDEO = "/app/experiment.mp4"
HEADERS = {"Authorization": "Bearer ds-secret-token"}
EXPECTED = None


def derive_expected(video_path):
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not open {video_path}"
    intensities = []
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            intensities.append(float(np.mean(gray)))
    finally:
        cap.release()

    assert intensities, "Video contained no decodable frames"
    mean = float(np.mean(intensities))
    sample_std = float(np.std(intensities, ddof=1))
    kept = [
        (index, value)
        for index, value in enumerate(intensities)
        if abs(value - mean) <= 3 * sample_std
    ]
    cleaned = []
    for position, (frame_index, _) in enumerate(kept):
        start = max(0, position - 4)
        smoothed = sum(value for _, value in kept[start:position + 1]) / (position - start + 1)
        cleaned.append({
            "frame_index": frame_index,
            "smoothed_intensity": smoothed,
        })
    return intensities, cleaned


def clear_outputs():
    for path in (RAW, CLEANED, LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_pipeline():
    assert os.path.isfile(PIPELINE), "Missing /home/user/pipeline.sh"
    assert not os.path.islink(PIPELINE), "/home/user/pipeline.sh must be a real file"
    result = subprocess.run(
        ["/bin/bash", PIPELINE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def validate_generated_files(video_path):
    expected_raw, expected_cleaned = derive_expected(video_path)

    assert os.path.isfile(RAW), "Missing /home/user/raw_signal.csv"
    with open(RAW, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["frame_index", "intensity"], (
            f"raw_signal.csv has incorrect columns: {reader.fieldnames}"
        )
        rows = list(reader)

    assert len(rows) == len(expected_raw), (
        f"Expected {len(expected_raw)} raw rows, got {len(rows)}"
    )
    for index, (row, expected_intensity) in enumerate(zip(rows, expected_raw)):
        assert set(row) == {"frame_index", "intensity"}
        try:
            actual_index = int(row["frame_index"])
            actual_intensity = float(row["intensity"])
        except (TypeError, ValueError) as exc:
            pytest.fail(f"Invalid raw CSV row {index}: {row} ({exc})")
        assert actual_index == index, f"Incorrect frame_index in raw row {index}"
        assert math.isfinite(actual_intensity), f"Non-finite intensity in raw row {index}"
        assert abs(actual_intensity - expected_intensity) <= 1e-6, (
            f"Incorrect intensity for frame {index}: expected {expected_intensity}, got {actual_intensity}"
        )

    assert os.path.isfile(CLEANED), "Missing /home/user/cleaned_signal.json"
    with open(CLEANED) as f:
        actual_cleaned = json.load(f)
    assert isinstance(actual_cleaned, list), "cleaned_signal.json must contain a JSON list"
    assert len(actual_cleaned) == len(expected_cleaned), (
        f"Expected {len(expected_cleaned)} cleaned rows, got {len(actual_cleaned)}"
    )
    for position, (actual, expected) in enumerate(zip(actual_cleaned, expected_cleaned)):
        assert isinstance(actual, dict), f"Cleaned item {position} is not an object"
        assert set(actual) == {"frame_index", "smoothed_intensity"}, (
            f"Cleaned item {position} has incorrect fields"
        )
        assert actual["frame_index"] == expected["frame_index"], (
            f"Incorrect frame_index at cleaned position {position}"
        )
        value = actual["smoothed_intensity"]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), (
            f"Invalid smoothed_intensity at cleaned position {position}"
        )
        assert math.isfinite(float(value))
        assert abs(float(value) - expected["smoothed_intensity"]) <= 1e-6, (
            f"Incorrect smoothed_intensity at cleaned position {position}: "
            f"expected {expected['smoothed_intensity']}, got {value}"
        )

    return expected_cleaned


def make_probe_video(path):
    values = [20, 24, 28, 32, 36, 21, 25, 29, 33, 37, 22, 26, 30, 34, 38, 240, 23]
    with tempfile.TemporaryDirectory() as frame_dir:
        for index, value in enumerate(values):
            frame = np.full((72, 96, 3), value, dtype=np.uint8)
            assert cv2.imwrite(os.path.join(frame_dir, f"frame_{index:03d}.png"), frame)
        subprocess.run(
            [
                "ffmpeg", "-loglevel", "error", "-framerate", "10",
                "-i", os.path.join(frame_dir, "frame_%03d.png"),
                "-c:v", "libx264", "-crf", "0", "-pix_fmt", "yuv444p",
                "-y", path,
            ],
            check=True,
            timeout=30,
        )


@pytest.fixture(scope="session", autouse=True)
def execute_and_verify_pipeline():
    global EXPECTED
    assert os.path.isfile(PIPELINE), "Missing /home/user/pipeline.sh"

    with tempfile.TemporaryDirectory() as temp_dir:
        backup = os.path.join(temp_dir, "experiment.mp4")
        probe = os.path.join(temp_dir, "probe.mp4")
        shutil.copy2(VIDEO, backup)
        make_probe_video(probe)
        try:
            shutil.copy2(probe, VIDEO)
            clear_outputs()
            run_pipeline()
            validate_generated_files(VIDEO)
        finally:
            shutil.copy2(backup, VIDEO)

    clear_outputs()
    run_pipeline()
    EXPECTED = validate_generated_files(VIDEO)
    yield


def test_files_exist():
    """Check if required files are generated."""
    assert os.path.exists(RAW), "Missing /home/user/raw_signal.csv"
    assert os.path.exists(CLEANED), "Missing /home/user/cleaned_signal.json"
    assert os.path.exists(PIPELINE), "Missing /home/user/pipeline.sh"
    assert os.path.exists(LOG), "Missing /home/user/pipeline.log"


def test_pipeline_log_content():
    """Check if the pipeline log contains the required lines."""
    with open(LOG, "r") as f:
        log_content = f.read()

    assert "[INFO] Starting extraction" in log_content, "Missing '[INFO] Starting extraction' in log"
    assert "[INFO] Extraction complete" in log_content, "Missing '[INFO] Extraction complete' in log"
    assert "[INFO] Starting cleaning" in log_content, "Missing '[INFO] Starting cleaning' in log"
    assert "[INFO] Cleaning complete" in log_content, "Missing '[INFO] Cleaning complete' in log"
    assert log_content.splitlines()[-1] == "[INFO] Cleaning complete", (
        "The last pipeline log line must be '[INFO] Cleaning complete'"
    )


@pytest.mark.parametrize("endpoint", ["/api/data", "/api/status"])
@pytest.mark.parametrize("headers", [None, {"Authorization": "Bearer wrong-token"}])
def test_http_api_requires_auth_for_all_endpoints(endpoint, headers):
    try:
        response = requests.get(f"http://127.0.0.1:8080{endpoint}", headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server: {e}")
    assert response.status_code == 401, (
        f"Expected HTTP 401 for {endpoint} without valid auth, got {response.status_code}"
    )


def test_http_api_no_auth():
    """Check that /api/data requires authorization."""
    response = requests.get("http://127.0.0.1:8080/api/data", timeout=5)
    assert response.status_code == 401, f"Expected HTTP 401 without auth, got {response.status_code}"


def test_http_api_data_with_auth():
    """Check that /api/data returns the complete correct JSON array with auth."""
    try:
        response = requests.get("http://127.0.0.1:8080/api/data", headers=HEADERS, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 with auth, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected application/json content type"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /api/data is not valid JSON")

    assert isinstance(data, list), "Expected a JSON array from /api/data"
    assert len(data) == 98, f"Expected 98 items in the cleaned data, got {len(data)}"
    assert len(data) == len(EXPECTED)
    for position, (actual, expected) in enumerate(zip(data, EXPECTED)):
        assert isinstance(actual, dict), f"API item {position} is not an object"
        assert actual.get("frame_index") == expected["frame_index"], (
            f"API returned incorrect frame_index at position {position}"
        )
        value = actual.get("smoothed_intensity")
        assert isinstance(value, (int, float)) and not isinstance(value, bool)
        assert abs(float(value) - expected["smoothed_intensity"]) <= 1e-6, (
            f"API returned incorrect smoothed value at position {position}"
        )

    item_52 = next((item for item in data if item.get("frame_index") == 52), None)
    assert item_52 is not None, "Missing frame_index 52 in the cleaned data"
    assert abs(item_52.get("smoothed_intensity", 0) - 100.0) < 1e-5, (
        f"Expected smoothed_intensity of 100.0 for index 52, got {item_52.get('smoothed_intensity')}"
    )

    with open(CLEANED) as f:
        on_disk = json.load(f)
    assert data == on_disk, "/api/data does not return cleaned_signal.json contents"


def test_http_api_status_with_auth():
    """Check that /api/status returns the correct latest log entry."""
    try:
        response = requests.get("http://127.0.0.1:8080/api/status", headers=HEADERS, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 with auth, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected application/json content type"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response from /api/status is not valid JSON")

    with open(LOG) as f:
        latest = f.read().splitlines()[-1]
    assert data.get("latest_log") == latest
    assert data.get("latest_log") == "[INFO] Cleaning complete", (
        f"Expected latest_log to be '[INFO] Cleaning complete', got {data.get('latest_log')}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
