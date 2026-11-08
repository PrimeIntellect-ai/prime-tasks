#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import functools
import json
import os
import re
import shutil
import subprocess

import cv2
import numpy as np
import requests

BASE_URL = "http://127.0.0.1:9090"
HEADERS = {"Authorization": "Bearer SECRET_DATA_TOKEN"}
MANIFEST_PATH = "/home/user/manifest.json"
FRAMES_DIR = "/home/user/frames"
VALID_STATUSES = {"black", "duplicate", "clean"}


@functools.lru_cache(maxsize=1)
def independently_recompute_results():
    reference_dir = "/tmp/verifier_reference_frames"
    shutil.rmtree(reference_dir, ignore_errors=True)
    os.makedirs(reference_dir)

    subprocess.run(
        [
            "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", "/app/dirty_feed.mp4", "-vf", "fps=10",
            os.path.join(reference_dir, "frame_%04d.jpg"),
        ],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    pattern = re.compile(r"frame_\d{4}\.jpg")
    reference_names = sorted(
        name for name in os.listdir(reference_dir) if pattern.fullmatch(name)
    )
    assert reference_names, "Independent 10 fps extraction produced no frames"

    assert os.path.isdir(FRAMES_DIR), f"Frame directory missing at {FRAMES_DIR}"
    submitted_names = sorted(
        name for name in os.listdir(FRAMES_DIR) if pattern.fullmatch(name)
    )
    assert submitted_names == reference_names, (
        "Extracted frame filenames/count do not match an independent 10 fps extraction"
    )

    classifications = {}
    previous = None
    for index, name in enumerate(reference_names):
        submitted_path = os.path.join(FRAMES_DIR, name)
        assert os.path.isfile(submitted_path), f"Missing extracted frame {name}"

        submitted = cv2.imread(submitted_path, cv2.IMREAD_COLOR)
        reference = cv2.imread(os.path.join(reference_dir, name), cv2.IMREAD_COLOR)
        assert submitted is not None, f"Unreadable JPEG frame {name}"
        assert reference is not None, f"Could not read independently extracted frame {name}"
        assert submitted.shape == reference.shape, f"Wrong dimensions for {name}"

        # JPEG quality was not prescribed, so allow normal encoder variation while
        # still requiring every submitted frame to correspond to the source video.
        source_mae = float(np.mean(np.abs(
            submitted.astype(np.float32) - reference.astype(np.float32)
        )))
        assert source_mae <= 8.0, (
            f"{name} does not correspond to the source video (MAE {source_mae:.3f})"
        )

        brightness = float(np.mean(submitted.astype(np.float32)))
        if brightness < 5.0:
            status = "black"
        elif index > 0:
            mae = float(np.mean(np.abs(
                submitted.astype(np.float32) - previous.astype(np.float32)
            )))
            status = "duplicate" if mae < 1.0 else "clean"
        else:
            status = "clean"

        classifications[name] = status
        previous = submitted

    assert classifications[reference_names[0]] != "duplicate", (
        "The first frame cannot be a duplicate"
    )

    summary = {
        "total_frames": len(reference_names),
        "black_frames": sum(v == "black" for v in classifications.values()),
        "duplicate_frames": sum(v == "duplicate" for v in classifications.values()),
        "clean_frames": sum(v == "clean" for v in classifications.values()),
    }
    return classifications, summary


def load_manifest():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file missing at {MANIFEST_PATH}"
    with open(MANIFEST_PATH, "r", encoding="utf-8") as handle:
        return json.load(handle)


def test_manifest_exists():
    expected_frames, expected_summary = independently_recompute_results()
    data = load_manifest()
    assert "summary" in data, "Manifest missing 'summary' key"
    assert "frames" in data, "Manifest missing 'frames' key"

    summary = data["summary"]
    assert "total_frames" in summary
    assert "black_frames" in summary
    assert "duplicate_frames" in summary
    assert "clean_frames" in summary
    assert summary == expected_summary, "Manifest summary does not match recomputed results"
    assert data["frames"] == expected_frames, (
        "Manifest per-frame entries do not match classifications recomputed from the frames"
    )
    assert summary["total_frames"] > 0, "Total frames should be greater than 0"
    assert summary["total_frames"] == (
        summary["black_frames"] + summary["duplicate_frames"] + summary["clean_frames"]
    )


def test_server_auth_enforcement():
    for path in ("/summary", "/frame/frame_0001.jpg", "/frame/nonexistent_frame_9999.jpg"):
        resp = requests.get(f"{BASE_URL}{path}", timeout=5)
        assert resp.status_code == 401, (
            f"Expected 401 for missing auth on {path}, got {resp.status_code}"
        )
        resp = requests.get(
            f"{BASE_URL}{path}",
            headers={"Authorization": "Bearer WRONG_TOKEN"},
            timeout=5,
        )
        assert resp.status_code == 401, (
            f"Expected 401 for wrong auth on {path}, got {resp.status_code}"
        )


def test_server_summary_endpoint():
    _, expected_summary = independently_recompute_results()
    resp = requests.get(f"{BASE_URL}/summary", headers=HEADERS, timeout=5)
    assert resp.status_code == 200, f"Expected 200 for /summary, got {resp.status_code}"
    data = resp.json()
    assert "total_frames" in data, "Summary response missing 'total_frames'"
    assert "black_frames" in data, "Summary response missing 'black_frames'"
    assert "duplicate_frames" in data, "Summary response missing 'duplicate_frames'"
    assert "clean_frames" in data, "Summary response missing 'clean_frames'"
    assert data["total_frames"] > 0, "Total frames should be greater than 0"
    assert data == expected_summary, "Server summary does not match recomputed results"


def test_server_frame_endpoints():
    expected_frames, _ = independently_recompute_results()
    for filename, expected_status in expected_frames.items():
        resp = requests.get(
            f"{BASE_URL}/frame/{filename}", headers=HEADERS, timeout=5
        )
        assert resp.status_code == 200, f"Expected 200 for {filename}, got {resp.status_code}"
        body = resp.json()
        assert body.get("status") in VALID_STATUSES, f"Invalid status returned for {filename}"
        assert body.get("status") == expected_status, (
            f"Wrong classification for {filename}: expected {expected_status}, "
            f"got {body.get('status')}"
        )


def test_server_404_endpoint():
    resp = requests.get(
        f"{BASE_URL}/frame/nonexistent_frame_9999.jpg",
        headers=HEADERS,
        timeout=5,
    )
    assert resp.status_code == 404, (
        f"Expected 404 for nonexistent frame, got {resp.status_code}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
