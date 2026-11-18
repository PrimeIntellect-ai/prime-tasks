#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import math
import shutil
import subprocess
import tempfile
from functools import lru_cache

import numpy as np
import pytest
import requests
from PIL import Image

API_BASE_URL = "http://127.0.0.1:8080/api/v1/frame"
AUTH_HEADER = {"Authorization": "Bearer secret-video-token"}

@lru_cache(maxsize=1)
def reference_frames():
    workdir = tempfile.mkdtemp(prefix="verifier_dashcam_")
    video_path = os.path.join(workdir, "dashcam.mp4")
    frames_dir = os.path.join(workdir, "frames")
    os.makedirs(frames_dir)

    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "testsrc=duration=5:size=320x240:rate=10",
        "-c:v", "libx264", video_path,
    ], check=True)
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", video_path, "-vf", "fps=5",
        os.path.join(frames_dir, "frame_%d.jpg"),
    ], check=True)

    names = sorted(
        (name for name in os.listdir(frames_dir) if re.fullmatch(r"frame_\d+\.jpg", name)),
        key=lambda name: int(re.fullmatch(r"frame_(\d+)\.jpg", name).group(1)),
    )
    assert names, "Verifier failed to create reference frames"
    return [os.path.join(frames_dir, name) for name in names]

def image_array(path):
    with Image.open(path) as image:
        assert image.format == "JPEG", f"Not a JPEG image: {path}"
        assert image.size == (320, 240), f"Unexpected frame dimensions for {path}: {image.size}"
        image = image.convert("RGB").resize((160, 120), Image.Resampling.LANCZOS)
        return np.asarray(image, dtype=np.float32)

def test_pipeline_status_log():
    log_path = "/home/user/pipeline_status.log"
    assert os.path.exists(log_path), f"Log file missing: {log_path}"
    with open(log_path, "r") as f:
        raw_content = f.read()
    content = raw_content.strip()
    assert re.match(r"^Total frames processed: \d+$", content), f"Invalid log content: {content}"

    expected_count = len(reference_frames())
    expected_line = f"Total frames processed: {expected_count}"
    assert raw_content in (expected_line, expected_line + "\n"), \
        f"Status log must contain exactly one line with the extracted-frame count; got: {raw_content!r}"

def test_frames_extracted():
    frames_dir = "/home/user/frames"
    assert os.path.exists(frames_dir), f"Frames directory missing: {frames_dir}"
    frames = [f for f in os.listdir(frames_dir) if f.startswith("frame_") and f.endswith(".jpg")]
    assert len(frames) > 0, "No frames extracted"

    references = reference_frames()
    expected_names = [f"frame_{i}.jpg" for i in range(1, len(references) + 1)]
    assert sorted(frames) == sorted(expected_names), \
        f"Expected exactly the sequential 5 FPS frames {expected_names}, got {sorted(frames)}"

    reference_arrays = [image_array(path) for path in references]
    for index, expected_name in enumerate(expected_names):
        submitted = image_array(os.path.join(frames_dir, expected_name))
        rmses = [float(np.sqrt(np.mean((submitted - reference) ** 2)))
                 for reference in reference_arrays]
        closest = int(np.argmin(rmses))
        assert closest == index, \
            f"{expected_name} does not correspond to the expected temporal frame from dashcam.mp4"
        assert rmses[index] <= 30.0, \
            f"{expected_name} does not match the frame extracted from dashcam.mp4 (RMSE {rmses[index]:.2f})"

def test_api_auth_missing():
    resp = requests.get(f"{API_BASE_URL}/1")
    assert resp.status_code == 401, f"Expected 401 for missing auth, got {resp.status_code}"

def test_api_auth_invalid():
    resp = requests.get(f"{API_BASE_URL}/1", headers={"Authorization": "Bearer wrong-token"})
    assert resp.status_code == 401, f"Expected 401 for invalid auth, got {resp.status_code}"

def test_api_404_not_found():
    resp = requests.get(f"{API_BASE_URL}/999999", headers=AUTH_HEADER)
    assert resp.status_code == 404, f"Expected 404 for non-existent frame, got {resp.status_code}"

    first_missing = len(reference_frames()) + 1
    resp = requests.get(f"{API_BASE_URL}/{first_missing}", headers=AUTH_HEADER)
    assert resp.status_code == 404, f"Expected 404 for frame {first_missing}, got {resp.status_code}"

def compute_frame_features(frame_id, frames_dir="/home/user/frames"):
    def get_brightness(fid):
        img_path = os.path.join(frames_dir, f"frame_{fid}.jpg")
        if not os.path.exists(img_path):
            return None
        img = Image.open(img_path).convert('L')
        pixels = list(img.getdata())
        return sum(pixels) / len(pixels)

    b_curr = get_brightness(frame_id)
    if b_curr is None:
        return None

    b_prev1 = get_brightness(frame_id - 1) if frame_id > 1 else None
    b_prev2 = get_brightness(frame_id - 2) if frame_id > 2 else None

    # Rolling avg for current frame
    vals = [b_curr]
    if b_prev1 is not None: vals.append(b_prev1)
    if b_prev2 is not None: vals.append(b_prev2)
    rolling_avg = sum(vals) / len(vals)

    # Rolling avg for previous frame
    is_flash = False
    if frame_id > 1:
        prev_vals = []
        if b_prev1 is not None: prev_vals.append(b_prev1)
        if b_prev2 is not None: prev_vals.append(b_prev2)
        b_prev3 = get_brightness(frame_id - 3) if frame_id > 3 else None
        if b_prev3 is not None: prev_vals.append(b_prev3)

        prev_rolling_avg = sum(prev_vals) / len(prev_vals)
        if b_curr > 1.5 * prev_rolling_avg:
            is_flash = True

    return {
        "brightness": round(b_curr, 2),
        "rolling_avg": round(rolling_avg, 2),
        "is_flash": is_flash
    }

def test_api_valid_frames():
    frames_dir = "/home/user/frames"
    frames = [f for f in os.listdir(frames_dir) if f.startswith("frame_") and f.endswith(".jpg")]
    total_frames = len(frames)
    if total_frames == 0:
        pytest.skip("No frames found to test API")

    test_ids = list(range(1, len(reference_frames()) + 1))

    for fid in test_ids:
        expected = compute_frame_features(fid)
        assert expected is not None, f"Could not compute features for frame {fid}"

        resp = requests.get(f"{API_BASE_URL}/{fid}", headers=AUTH_HEADER)
        assert resp.status_code == 200, f"Expected 200 for frame {fid}, got {resp.status_code}"

        data = resp.json()
        assert "frame_id" in data
        assert data["frame_id"] == fid
        assert "brightness" in data
        assert "rolling_avg" in data
        assert "is_flash" in data

        assert math.isclose(data["brightness"], expected["brightness"], abs_tol=0.1), \
            f"Frame {fid} brightness mismatch. Expected {expected['brightness']}, got {data['brightness']}"
        assert math.isclose(data["rolling_avg"], expected["rolling_avg"], abs_tol=0.1), \
            f"Frame {fid} rolling_avg mismatch. Expected {expected['rolling_avg']}, got {data['rolling_avg']}"
        assert data["is_flash"] == expected["is_flash"], \
            f"Frame {fid} is_flash mismatch. Expected {expected['is_flash']}, got {data['is_flash']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
