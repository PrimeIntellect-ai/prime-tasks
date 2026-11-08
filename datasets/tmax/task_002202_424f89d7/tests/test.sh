#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import math
import hashlib
import tempfile
import subprocess
import requests
from PIL import Image

def test_cron_file_exists_and_correct():
    cron_path = "/home/user/pipeline.cron"
    assert os.path.isfile(cron_path), f"Cron file {cron_path} does not exist."

    with open(cron_path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip() and not line.strip().startswith("#")]
    assert len(lines) > 0, "Cron file is empty or contains only comments."

    # Check if any line matches the 5-minute interval for /home/user/process.sh
    pattern1 = r"^(\*/5|0,5,10,15,20,25,30,35,40,45,50,55|5,10,15,20,25,30,35,40,45,50,55,0)\s+\*\s+\*\s+\*\s+\*\s+/home/user/process\.sh"
    pattern2 = r"^5\s+\*\s+\*\s+\*\s+\*\s+/home/user/process\.sh" # This would be "at minute 5", but the task says "every 5 minutes", so */5 is expected. We'll allow standard every 5 min expressions.

    valid = False
    for line in lines:
        if re.search(r"^\s*(?:\*/5|0,5,10,15,20,25,30,35,40,45,50,55)\s+\*\s+\*\s+\*\s+\*\s+/home/user/process\.sh", line):
            valid = True
            break

    assert valid, f"No valid cron schedule found for /home/user/process.sh every 5 minutes in {cron_path}. Found: {content}"

def test_api_stats():
    # 1. Compute ground truth
    video_path = "/app/traffic_monitor.mp4"
    assert os.path.isfile(video_path), f"Video file {video_path} is missing."

    with tempfile.TemporaryDirectory() as tmpdir:
        # Extract frames at 1 fps
        cmd = ["ffmpeg", "-i", video_path, "-vf", "fps=1", os.path.join(tmpdir, "frame_%04d.png")]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

        frames = sorted([f for f in os.listdir(tmpdir) if f.endswith(".png")])
        assert len(frames) > 0, "No frames extracted from video."

        unique_frames = []
        last_hash = None

        for frame in frames:
            frame_path = os.path.join(tmpdir, frame)
            with open(frame_path, "rb") as f:
                file_hash = hashlib.md5(f.read()).hexdigest()

            if file_hash != last_hash:
                unique_frames.append(frame_path)
                last_hash = file_hash

        brightness_values = []
        for frame_path in unique_frames:
            with Image.open(frame_path) as img:
                grayscale = img.convert("L")
                pixels = list(grayscale.getdata())
                avg_brightness = sum(pixels) / len(pixels)
                brightness_values.append(avg_brightness)

        rolling_averages = []
        for i in range(len(brightness_values)):
            start_idx = max(0, i - 2)
            window = brightness_values[start_idx:i+1]
            rolling_averages.append(sum(window) / len(window))

        expected_min = min(rolling_averages)
        expected_max = max(rolling_averages)
        expected_avg = sum(rolling_averages) / len(rolling_averages)

        expected_min_round = round(expected_min, 2)
        expected_max_round = round(expected_max, 2)
        expected_avg_round = round(expected_avg, 2)

    # 2. Query the API
    try:
        response = requests.get("http://127.0.0.1:8080/stats", timeout=5)
        response.raise_for_status()
    except Exception as e:
        assert False, f"Failed to connect to HTTP API at http://127.0.0.1:8080/stats: {e}"

    try:
        data = response.json()
    except Exception as e:
        assert False, f"API did not return valid JSON: {response.text}"

    assert "min" in data, "Key 'min' missing from JSON response."
    assert "max" in data, "Key 'max' missing from JSON response."
    assert "avg" in data, "Key 'avg' missing from JSON response."

    assert math.isclose(data["min"], expected_min_round, abs_tol=0.02), f"Expected min ~{expected_min_round}, got {data['min']}"
    assert math.isclose(data["max"], expected_max_round, abs_tol=0.02), f"Expected max ~{expected_max_round}, got {data['max']}"
    assert math.isclose(data["avg"], expected_avg_round, abs_tol=0.02), f"Expected avg ~{expected_avg_round}, got {data['avg']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
