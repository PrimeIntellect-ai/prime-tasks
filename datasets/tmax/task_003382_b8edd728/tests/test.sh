#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest
import cv2


def test_config_recreated():
    config_path = '/home/user/service_repo/config.py'
    assert os.path.exists(config_path), f"Expected {config_path} to be recreated."
    with open(config_path, 'r') as f:
        content = f.read()
    assert 'sk-live-a1b2c3d4e5f60789' in content, "config.py does not contain the correct API_KEY."


def test_memory_leak_fixed_and_script_runs():
    script_path = '/home/user/service_repo/video_processor.py'
    video_path = '/app/stream.mp4'
    results_path = '/home/user/results.json'

    # Remove results.json if it exists to ensure the script generates a fresh one
    if os.path.exists(results_path):
        os.remove(results_path)

    cmd = ["/usr/bin/time", "-v", "python", script_path, video_path]
    result = subprocess.run(cmd, capture_output=True, text=True)

    assert result.returncode == 0, f"Process failed to run. stderr: {result.stderr}\nstdout: {result.stdout}"

    max_rss = None
    for line in result.stderr.split('\n'):
        if "Maximum resident set size (kbytes):" in line:
            max_rss = int(line.split(":")[1].strip())
            break

    assert max_rss is not None, "Could not read RSS from /usr/bin/time output."
    assert max_rss <= 150000, f"Memory threshold exceeded! max_rss={max_rss} KB, threshold=150000 KB. The memory leak is not fully fixed."


def test_results_json_valid():
    results_path = '/home/user/results.json'
    video_path = '/app/stream.mp4'
    assert os.path.exists(results_path), f"{results_path} was not generated."

    with open(results_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} is not valid JSON.")

    assert "frames" in data, "Key 'frames' missing from results.json"
    assert "total_intensity" in data, "Key 'total_intensity' missing from results.json"
    assert isinstance(data["frames"], int), "'frames' should be an integer"
    assert isinstance(data["total_intensity"], (int, float)), "'total_intensity' should be a number"
    assert data["frames"] > 0, "Expected at least 1 frame to be processed."

    # Independently recompute the original implementation's mathematical result.
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not open test video {video_path}."
    expected_frames = 0
    expected_total_intensity = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        expected_total_intensity += int(frame.mean())
        expected_frames += 1
    cap.release()

    expected = {
        "frames": expected_frames,
        "total_intensity": expected_total_intensity,
    }
    assert data == expected, f"Incorrect video analysis: expected {expected}, got {data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
