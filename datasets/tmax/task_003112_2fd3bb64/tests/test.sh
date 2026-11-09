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
import random
import sqlite3
import requests
import pytest

try:
    import cv2
    import numpy as np
except ImportError:
    pass  # Agent is expected to install the video-processing dependencies it uses.

BASE_URL = "http://127.0.0.1:8080"
VIDEO_PATH = "/app/video.mp4"


def get_expected_brightness(video_path, frame_idx):
    cap = cv2.VideoCapture(video_path)
    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
    ret, frame = cap.read()
    cap.release()
    if not ret:
        raise ValueError(f"Could not read frame {frame_idx} from {video_path}")
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    return float(np.mean(gray))


def get_frame_count(video_path):
    cap = cv2.VideoCapture(video_path)
    count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    cap.release()
    return count


frame_count = get_frame_count(VIDEO_PATH)
assert frame_count >= 5, f"Test video unexpectedly has only {frame_count} frames"

# Always retain the original frame-5 check, but choose the other successful
# requests dynamically so a server specialized to one fixed frame cannot pass.
other_frames = [i for i in range(frame_count) if i != 5]
selected_frames = [5] + random.SystemRandom().sample(other_frames, 4)
random.SystemRandom().shuffle(selected_frames)
expected_brightness = {
    frame_idx: get_expected_brightness(VIDEO_PATH, frame_idx)
    for frame_idx in selected_frames
}


def test_server_listening_and_bad_requests():
    resp = requests.post(f"{BASE_URL}/analyze", json={"wrong_key": 10}, timeout=5)
    assert resp.status_code == 400, f"Expected 400 for missing 'frame' key, got {resp.status_code}"

    resp = requests.post(f"{BASE_URL}/analyze", json={"frame": -5}, timeout=5)
    assert resp.status_code == 400, f"Expected 400 for negative frame, got {resp.status_code}"

    # Non-integer values must be rejected and must not consume the success quota.
    for value in (1.5, "5", True):
        resp = requests.post(f"{BASE_URL}/analyze", json={"frame": value}, timeout=5)
        assert resp.status_code == 400, \
            f"Expected 400 for non-integer frame {value!r}, got {resp.status_code}"


def test_rate_limiting_and_correctness():
    for i, frame_idx in enumerate(selected_frames):
        resp = requests.post(
            f"{BASE_URL}/analyze", json={"frame": frame_idx}, timeout=10
        )
        assert resp.status_code == 200, \
            f"Expected 200 for valid request {i + 1} (frame {frame_idx}), got {resp.status_code}"
        data = resp.json()
        assert "brightness" in data, "Response JSON missing 'brightness' key"
        assert abs(data["brightness"] - expected_brightness[frame_idx]) < 0.1, \
            f"Expected frame {frame_idx} brightness ~{expected_brightness[frame_idx]}, got {data['brightness']}"

    # The sixth valid request should be rejected even though the earlier invalid
    # requests did not count toward the limit.
    resp = requests.post(
        f"{BASE_URL}/analyze", json={"frame": selected_frames[0]}, timeout=5
    )
    assert resp.status_code == 429, f"Expected 429 for 6th valid request, got {resp.status_code}"


def test_database_state():
    db_path = "/app/metrics.db"
    assert os.path.isfile(db_path), f"Database file not found at {db_path}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM metrics;")
    count = cursor.fetchone()[0]
    assert count == 5, f"Expected exactly 5 rows in metrics table, got {count}"

    cursor.execute("SELECT frame, brightness FROM metrics ORDER BY id;")
    rows = cursor.fetchall()
    for row, requested_frame in zip(rows, selected_frames):
        assert row[0] == requested_frame, \
            f"Expected persisted frame {requested_frame}, got {row[0]}"
        assert isinstance(row[1], float), "Brightness should be a float"
        assert abs(row[1] - expected_brightness[requested_frame]) < 0.1, \
            f"Persisted brightness for frame {requested_frame} is incorrect: {row[1]}"

    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
